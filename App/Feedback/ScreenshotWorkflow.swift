import AnnotationKit
import AppKit
import CaptureKit
import FeedbackKit
import ImageIO
import SharedKit

/// A complete image snapshot for the existing round save pipeline.
struct FeedbackPromotionInput {
    let rendered: CGImage
    let clean: CGImage
    let metadata: ScreenshotMetadata
}

/// Coordinates local screenshot copy, immutable versions, and explicit promotion.
@MainActor
final class ScreenshotWorkflow {
    private let history: ScreenshotHistoryStore
    private let settings: AppSettings
    private let rootURL: URL
    private let rounds: () async -> [FeedbackRound]
    private let promote: (FeedbackPromotionInput) async throws -> Void
    private let imageIntent: () -> Void
    private let toast: (String) -> Void
    private let quickLook = FeedbackQuickLook()
    private var editor: AnnotationEditorWindow?
    private var busy = false
    private var recovery: ScreenshotRecoveryWindow?
    private var browser: ScreenshotHistoryWindow?
    private var savedEditorSnapshot: (png: Data, marks: [FeedbackMark], item: ScreenshotHistoryItem)?
    var editorIsOpen: Bool { editor != nil || recovery != nil }
    var isBusy: Bool { busy }

    init(settings: AppSettings, rootURL: URL,
         rounds: @escaping () async -> [FeedbackRound],
         promote: @escaping (FeedbackPromotionInput) async throws -> Void,
         imageIntent: @escaping () -> Void, toast: @escaping (String) -> Void) throws {
        self.settings = settings
        self.rootURL = rootURL
        self.rounds = rounds
        self.promote = promote
        self.imageIntent = imageIntent
        self.toast = toast
        history = try ScreenshotHistoryStore(rootURL: rootURL.appendingPathComponent("ScreenshotHistory", isDirectory: true))
    }

    func items() async throws -> [ScreenshotHistoryItem] {
        let roundSnapshot = await rounds()
        let local = try await history.items()
        return ScreenshotHistoryIndex.items(local: local, rounds: roundSnapshot, rootURL: rootURL)
    }

    func showHistory() {
        Task {
            do {
                if browser == nil {
                    browser = ScreenshotHistoryWindow(
                        onCopy: { [weak self] item, variant in self?.copy(item, variant: variant) },
                        onPreview: { [weak self] item in self?.quickLook.show(item.annotatedURL) },
                        onAnnotate: { [weak self] item in self?.annotate(item) }
                    )
                }
                browser?.show(items: try await items())
            } catch { report(error) }
        }
    }

    func annotateLatest() {
        guard !busy, !editorIsOpen else { NSSound.beep(); return }
        busy = true
        Task {
            do {
                guard let latest = try await items().first else {
                    busy = false
                    toast("No screenshots yet. Press Option+Shift+4 to take one.")
                    return
                }
                busy = false
                openAnnotationEditor(latest)
            } catch { busy = false; report(error) }
        }
    }

    func copy(_ item: ScreenshotHistoryItem, variant: ScreenshotImageVariant) {
        do {
            let url: URL
            switch variant {
            case .annotated: url = item.annotatedURL
            case .withoutAnnotations:
                guard let clean = item.cleanURL else { throw WorkflowError.cleanUnavailable }
                url = clean
            }
            let image = try load(url)
            guard ImageUtilities.copyToPasteboard(image, format: settings.screenshotClipboardFormat) else {
                throw WorkflowError.clipboard
            }
            imageIntent()
            toast("Screenshot copied")
        } catch { report(error) }
    }

    func copyFresh(_ rendered: CGImage, result: CaptureResult, objects: [any AnnotationObject],
                   retainOnFailure: Bool = false, close: @escaping () -> Void = {}) {
        guard !busy else { NSSound.beep(); return }
        busy = true
        Task {
            defer { busy = false }
            do {
                guard ImageUtilities.copyToPasteboard(rendered, format: settings.screenshotClipboardFormat) else {
                    throw WorkflowError.clipboard
                }
                imageIntent()
                let sameSize = rendered.width == result.image.width && rendered.height == result.image.height
                let size = PixelSize(width: rendered.width, height: rendered.height)
                let marks = sameSize ? FeedbackMarkMapper.marks(from: objects, source: size, target: size) : []
                let clean = sameSize ? try cleanImage(base: result.image, objects: objects) : nil
                let metadata = ScreenshotMetadata(
                    createdAt: result.timestamp, capturedAt: result.timestamp, size: size,
                    appName: result.appName, windowTitle: result.windowName, marks: marks, note: nil,
                    hasReliableCleanImage: clean != nil,
                    hasReliableBadges: sameSize && Set(marks.compactMap(\.badge)).count == marks.compactMap(\.badge).count
                )
                let write = try encoded(rendered, clean: clean, metadata: metadata)
                _ = try await history.save(write)
                recovery?.close()
                recovery = nil
                close()
                toast(history.retentionError == nil ? "Screenshot copied and saved" : "Screenshot saved. History cleanup needs a retry.")
                await refreshBrowser()
            } catch {
                busy = false
                let retry: () -> Void = { [weak self] in
                    self?.copyFresh(rendered, result: result, objects: objects,
                                    retainOnFailure: retainOnFailure, close: close)
                }
                if retainOnFailure {
                    recovery?.close()
                    recovery = ScreenshotRecoveryWindow(image: rendered, error: error, retry: retry) { [weak self] in
                        self?.recovery?.close()
                        self?.recovery = nil
                    }
                    recovery?.makeKeyAndOrderFront(nil)
                } else {
                    report(error, retry: retry)
                }
            }
        }
    }

    private func annotate(_ selected: ScreenshotHistoryItem) {
        guard !editorIsOpen, !busy else { NSSound.beep(); return }
        busy = true
        Task {
            do {
                // Browser rows can predate completed notes. Resolve by stable source identity.
                let currentItems = try await items()
                guard let current = currentItems.first(where: { $0.id == selected.id }) else {
                    throw WorkflowError.image
                }
                browser?.update(items: currentItems)
                busy = false
                openAnnotationEditor(current)
            } catch { busy = false; report(error) }
        }
    }

    private func openAnnotationEditor(_ item: ScreenshotHistoryItem) {
        guard !editorIsOpen, !busy else { NSSound.beep(); return }
        do {
            let image = try load(item.annotatedURL)
            savedEditorSnapshot = nil
            let defaultTool = FeedbackDefaultTool.begin()
            editor = AnnotationEditorWindow(
                image: image, sourceAppName: item.appName, sourceWindowTitle: item.windowTitle,
                captureDate: item.capturedAt, screenshotOutput: settings.screenshotOutputOptions,
                screenshotFilenameTemplate: settings.screenshotFilenameTemplate,
                onSave: { [weak self] rendered in
                    self?.finishEdit(rendered, source: item, addToRound: false)
                    return false
                },
                onCopy: { _ in }, onPin: { _, _ in },
                onClose: { [weak self] in
                    defaultTool.restore()
                    self?.editor = nil
                    self?.savedEditorSnapshot = nil
                },
                copyResult: { [weak self] rendered in
                    self?.finishEdit(rendered, source: item, addToRound: false)
                    return false
                },
                onAddToRound: item.metadata.hasReliableBadges && item.cleanURL != nil ? { [weak self] rendered in
                    self?.finishEdit(rendered, source: item, addToRound: true)
                } : nil
            )
            editor?.document.reservedCounterNumbers = Set(item.marks.compactMap(\.badge))
            editor?.document.enforcesUniqueCounterNumbers = true
            editor?.document.allowsCanvasResize = false
            editor?.document.allowsPin = false
            editor?.show()
            if !item.metadata.hasReliableBadges || item.cleanURL == nil {
                toast("Older image metadata is incomplete. Image copy remains available.")
            }
        } catch { report(error) }
    }

    private func finishEdit(_ rendered: CGImage, source: ScreenshotHistoryItem, addToRound: Bool) {
        guard !busy, let window = editor else { NSSound.beep(); return }
        busy = true
        let objects = window.document.objects
        Task {
            defer { busy = false }
            do {
                if !addToRound {
                    guard ImageUtilities.copyToPasteboard(rendered, format: settings.screenshotClipboardFormat) else {
                        throw WorkflowError.clipboard
                    }
                    imageIntent()
                }
                let version = try await saveVersion(rendered, source: source, objects: objects)
                if addToRound {
                    guard version.metadata.hasReliableBadges, let url = version.cleanURL else {
                        throw WorkflowError.cleanUnavailable
                    }
                    try await promote(FeedbackPromotionInput(rendered: try load(version.annotatedURL),
                                                             clean: try load(url), metadata: version.metadata))
                }
                window.close()
                if history.retentionError != nil { toast("Screenshot saved. History cleanup needs a retry.") }
                else { toast(addToRound ? "Screenshot added to round" : "Screenshot copied and saved") }
                await refreshBrowser()
            } catch {
                busy = false
                report(error) { [weak self] in self?.finishEdit(rendered, source: source, addToRound: addToRound) }
            }
        }
    }

    private func saveVersion(_ rendered: CGImage, source: ScreenshotHistoryItem,
                             objects: [any AnnotationObject]) async throws -> ScreenshotHistoryItem {
        guard !objects.isEmpty else { return source }
        let size = PixelSize(width: rendered.width, height: rendered.height)
        guard size == source.size else { throw WorkflowError.geometry }
        let newMarks = FeedbackMarkMapper.marks(from: objects, source: size, target: size)
        let marks = source.marks + newMarks
        let badges = marks.compactMap(\.badge)
        guard badges.count == Set(badges).count else { throw WorkflowError.badges }
        guard let annotatedPNG = ImageUtilities.pngData(from: rendered) else { throw WorkflowError.encoding }
        if let saved = savedEditorSnapshot, saved.png == annotatedPNG, saved.marks == marks { return saved.item }
        let clean: CGImage?
        if let url = source.cleanURL { clean = try cleanImage(base: load(url), objects: objects) }
        else { clean = nil }
        let metadata = ScreenshotMetadata(
            parent: source.id, createdAt: Date(), capturedAt: source.capturedAt, size: size,
            appName: source.appName, windowTitle: source.windowTitle, marks: marks, note: source.note,
            hasReliableCleanImage: clean != nil, hasReliableBadges: source.metadata.hasReliableBadges
        )
        let cleanPNG = clean.flatMap(ImageUtilities.pngData)
        guard clean == nil || cleanPNG != nil else { throw WorkflowError.encoding }
        let write = ScreenshotWrite(metadata: metadata, annotatedPNG: annotatedPNG, cleanPNG: cleanPNG)
        let result = try await history.save(write)
        savedEditorSnapshot = (write.annotatedPNG, marks, result)
        return result
    }

    private func encoded(_ image: CGImage, clean: CGImage?, metadata: ScreenshotMetadata) throws -> ScreenshotWrite {
        guard let png = ImageUtilities.pngData(from: image) else { throw WorkflowError.encoding }
        let cleanPNG = clean.flatMap(ImageUtilities.pngData)
        guard clean == nil || cleanPNG != nil else { throw WorkflowError.encoding }
        return ScreenshotWrite(metadata: metadata, annotatedPNG: png, cleanPNG: cleanPNG)
    }

    private func cleanImage(base: CGImage, objects: [any AnnotationObject]) throws -> CGImage {
        let redactions = objects.filter { $0 is PixelateObject }
        guard !redactions.isEmpty else { return base }
        guard let image = AnnotationRenderer.render(sourceImage: base, objects: redactions) else {
            throw WorkflowError.encoding
        }
        return image
    }

    private func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw WorkflowError.image }
        return image
    }

    private func refreshBrowser() async {
        guard browser != nil else { return }
        if let items = try? await items() { browser?.update(items: items) }
    }

    private func report(_ error: Error, retry: (() -> Void)? = nil) {
        NSSound.beep()
        let alert = NSAlert()
        alert.messageText = "Screenshot action could not finish"
        alert.informativeText = error.localizedDescription
        if let retry {
            alert.informativeText += "\nYour screenshot remains available. Try this action again?"
            alert.addButton(withTitle: "Try Again")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                Task { @MainActor in retry() }
            }
        } else {
            alert.runModal()
        }
    }

    private enum WorkflowError: LocalizedError {
        case image, encoding, clipboard, cleanUnavailable, geometry, badges
        var errorDescription: String? {
            switch self {
            case .image: "The screenshot file is missing or unreadable."
            case .encoding: "The screenshot could not be encoded safely."
            case .clipboard: "The screenshot could not be copied. Try again."
            case .cleanUnavailable: "A reliable clean image or badge history is unavailable for this older screenshot."
            case .geometry: "This edit changes the canvas size. Keep the original size to preserve clean copy."
            case .badges: "A new badge duplicates an earlier number. Choose a different number."
            }
        }
    }
}
