// App/Feedback/FeedbackController.swift
import AnnotationKit
import AppKit
import CaptureKit
import FeedbackKit
import KeyboardShortcuts
import OCRKit
import SharedKit

/// Fork: owns feedback sessions. Each saved capture goes into the active
/// session's folder under `~/Feedback`. This code makes no network calls.
@MainActor
final class FeedbackController {
    static let shared = FeedbackController()

    let store: FeedbackSessionStore
    private(set) var session: FeedbackSession?
    private(set) var folderURL: URL?

    private weak var captureCoordinator: CaptureCoordinator?
    private var settings: AppSettings?
    private var inlineEditor: InlineAnnotationEditorWindow?
    private var fullEditor: AnnotationEditorWindow?
    private let statusItem = FeedbackStatusItem()
    private let notePanel = FeedbackNotePanel()
    private var shortcutPanel: FeedbackShortcutPanel?

    init(rootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Feedback", isDirectory: true)) {
        store = FeedbackSessionStore(rootURL: rootURL)
    }

    func start(captureCoordinator: CaptureCoordinator, settings: AppSettings) {
        self.captureCoordinator = captureCoordinator
        self.settings = settings
        captureCoordinator.feedbackSink = { [weak self] result in
            self?.openEditor(for: result)
        }
        KeyboardShortcuts.onKeyDown(for: .feedbackCapture) { [weak self] in
            self?.capture()
        }
        statusItem.onCopyPrompt = { [weak self] in
            Task { await self?.copyPrompt() }
        }
        statusItem.onOpenFolder = { [weak self] in
            self?.openFolder()
        }
        statusItem.onEndSession = { [weak self] in
            Task { try? await self?.endSession() }
        }
        statusItem.onShowShortcut = { [weak self] in
            self?.showShortcutPanel()
        }
        // A session left active before a relaunch shows its status item again.
        Task { await refresh() }
    }

    // MARK: - Session actions (hotkey, status menu, App Intents)

    @discardableResult
    func startSession(name: String?) async throws -> FeedbackSession {
        let session = try await store.start(name: name ?? "")
        await refresh()
        return session
    }

    /// Starts a session named "feedback" when none is active, then an area capture.
    func capture() {
        Task {
            do {
                if await store.activeSession == nil {
                    try await store.start(name: FeedbackNaming.defaultSlug)
                }
                await refresh()
                captureCoordinator?.captureAreaForFeedback()
            } catch {
                report(error, context: "Feedback capture did not start")
            }
        }
    }

    /// Puts the active session's prompt on the clipboard and returns it.
    @discardableResult
    func copyPrompt() async -> String? {
        guard let session = await store.activeSession, let folder = await store.activeFolderURL else {
            NSSound.beep()
            return nil
        }
        let prompt = PromptBuilder.render(session, folderPath: folder.path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        return prompt
    }

    @discardableResult
    func endSession() async throws -> FeedbackSession {
        defer { Task { await refresh() } }
        notePanel.close()
        return try await store.end()
    }

    func openFolder() {
        guard let folderURL else { return }
        NSWorkspace.shared.open(folderURL)
    }

    func showShortcutPanel() {
        let panel = shortcutPanel ?? FeedbackShortcutPanel()
        shortcutPanel = panel
        panel.show()
    }

    private func refresh() async {
        session = await store.activeSession
        folderURL = await store.activeFolderURL
        statusItem.update(session: session)
    }

    // MARK: - Editor

    private func openEditor(for result: CaptureResult) {
        if result.mode == .area,
           let screen = NSScreen.screens.first(where: { $0.displayID == result.displayID }),
           openInlineEditor(for: result, screen: screen) {
            return
        }
        openFullEditor(for: result)
    }

    private func openInlineEditor(for result: CaptureResult, screen: NSScreen) -> Bool {
        let screenLocalRect = CaptureDisplayGeometry.screenLocalRect(
            fromTopLeftCaptureRect: result.captureRect,
            screenHeight: screen.frame.height
        )
        guard screenLocalRect.width > 0,
              screenLocalRect.height > 0,
              CaptureDisplayGeometry.displayScale(
                imageSize: CGSize(width: result.image.width, height: result.image.height),
                screenRect: screenLocalRect
              ) != nil else {
            return false
        }

        inlineEditor?.close()
        inlineEditor = InlineAnnotationEditorWindow(
            image: result.image,
            screen: screen,
            screenLocalRect: screenLocalRect,
            onSave: { [weak self] rendered in
                self?.saveFromInlineEditor(rendered, result: result)
            },
            onCopy: { [weak self] rendered in
                // In a session, Copy also keeps the capture.
                ImageUtilities.copyToPasteboard(rendered, format: .png)
                self?.saveFromInlineEditor(rendered, result: result)
            },
            onPin: { [weak self] rendered, _ in
                // In a session, Pin keeps the capture instead of pinning it.
                self?.saveFromInlineEditor(rendered, result: result)
            },
            onClose: { [weak self] in
                self?.inlineEditor = nil
            }
        )
        inlineEditor?.show()
        return true
    }

    private func saveFromInlineEditor(_ rendered: CGImage, result: CaptureResult) {
        guard let editor = inlineEditor else { return }
        save(rendered: rendered, objects: editor.document.objects, result: result)
    }

    /// The full editor opens when the inline editor cannot, for example when
    /// the capture's display is gone.
    private func openFullEditor(for result: CaptureResult) {
        guard let settings else { return }
        fullEditor?.close()
        fullEditor = AnnotationEditorWindow(
            image: result.image,
            anchorScreen: NSScreen.screens.first { $0.displayID == result.displayID },
            sourceAppName: result.appName,
            sourceWindowTitle: result.windowName,
            captureDate: result.timestamp,
            screenshotOutput: settings.screenshotOutputOptions,
            screenshotFilenameTemplate: settings.screenshotFilenameTemplate,
            onSave: { [weak self] rendered in
                guard let self, let editor = self.fullEditor else { return false }
                self.save(rendered: rendered, objects: editor.document.objects, result: result)
                self.fullEditor = nil
                return true
            },
            onCopy: { rendered in
                ImageUtilities.copyToPasteboard(rendered, format: .png)
            },
            onPin: { _, _ in },
            onClose: { [weak self] in
                self?.fullEditor = nil
            }
        )
        fullEditor?.show()
    }

    // MARK: - Save pipeline

    /// Maps the marks, runs on-device OCR on the clean image, sizes both PNG
    /// files for export, adds the capture, then opens the note panel.
    private func save(rendered: CGImage, objects: [any AnnotationObject], result: CaptureResult) {
        let clean = result.image
        let source = PixelSize(width: rendered.width, height: rendered.height)
        let target = ImageSizing.resizedSize(source, limits: .feedbackExport)
        // Mark coordinates match the rendered image only when the editor kept
        // the capture's size. The inline editor never crops or grows the canvas.
        let sameGeometry = clean.width == rendered.width && clean.height == rendered.height
        let marks = sameGeometry ? FeedbackMarkMapper.marks(from: objects, source: source, target: target) : []
        let cleanTarget = sameGeometry
            ? target
            : ImageSizing.resizedSize(PixelSize(width: clean.width, height: clean.height), limits: .feedbackExport)

        Task {
            do {
                let regions = (try? await TextRecognizer.recognize(image: clean)) ?? []
                let lines = sameGeometry
                    ? regions.map { FeedbackTextLine(text: $0.text, box: ImageSizing.scale($0.boundingBox, from: source, to: target)) }
                    : []
                guard let annotatedPNG = FeedbackImageExport.png(rendered, size: target),
                      let cleanPNG = FeedbackImageExport.png(clean, size: cleanTarget) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let ocrText = regions.map(\.text).joined(separator: "\n")
                let capture = try await store.addCapture(FeedbackCaptureInput(
                    annotatedPNG: annotatedPNG,
                    cleanPNG: cleanPNG,
                    size: target,
                    sourceApp: result.appName,
                    windowTitle: result.windowName,
                    ocrText: ocrText.isEmpty ? nil : ocrText,
                    marks: OCRMatcher.assignText(to: marks, lines: lines)
                ))
                await refresh()
                // `self` is the app-lifetime singleton, so a strong capture is safe.
                notePanel.show(captureIndex: capture.index, badges: capture.badgeNumbers.sorted()) { text in
                    Task { await self.saveNote(text, capture: capture.index) }
                }
            } catch {
                report(error, context: "Feedback capture was not saved")
            }
        }
    }

    private func saveNote(_ text: String, capture index: Int) async {
        do {
            try await store.updateNote(capture: index, text: text)
        } catch {
            report(error, context: "Feedback note was not saved")
        }
        await refresh()
    }

    private func report(_ error: Error, context: String) {
        DiagnosticLogger.append(error: error, context: context, category: "Feedback")
        NSSound.beep()
    }
}
