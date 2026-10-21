// App/Feedback/FeedbackController.swift
import AnnotationKit
import AppKit
import CaptureKit
import FeedbackKit
import KeyboardShortcuts
import OCRKit
import os
import SharedKit

/// Fork: timing and state of the feedback path, in the macOS system log.
/// Read with: log show --last 10m --predicate 'subsystem == "com.drewschulz.capso.feedback"'
enum FeedbackLog {
    static let logger = Logger(subsystem: "com.drewschulz.capso.feedback", category: "Feedback")
}

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
            FeedbackLog.logger.notice("hotkey pressed")
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
                try await store.startIfNeeded(name: FeedbackNaming.defaultSlug)
                await refresh()
                FeedbackLog.logger.notice("session ready, area capture requested")
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
        FeedbackLog.logger.notice("capture received \(result.image.width)x\(result.image.height), opening editor")
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

    /// Opens the note panel at once, then maps the marks, runs on-device OCR on
    /// the clean image, sizes both PNG files, and adds the capture. OCR can take
    /// 30 s when the Neural Engine is cold (measured 2026-10-20), so the note
    /// must not wait for it. A note typed before the capture is stored is held
    /// in `PendingNote` and saved right after.
    private func save(rendered: CGImage, objects: [any AnnotationObject], result: CaptureResult) {
        FeedbackLog.logger.notice("save started, \(objects.count) marks")
        let source = PixelSize(width: rendered.width, height: rendered.height)
        let target = ImageSizing.resizedSize(source, limits: .feedbackExport)
        // Mark coordinates match the rendered image only when the editor kept
        // the capture's size. The inline editor never crops or grows the canvas.
        let sameGeometry = result.image.width == rendered.width && result.image.height == rendered.height
        let marks = sameGeometry ? FeedbackMarkMapper.marks(from: objects, source: source, target: target) : []

        // The clean copy keeps Redact marks applied, so redacted content never
        // reaches the bundle. When marks cannot be mapped, the rendered image
        // is the clean copy too.
        let redactions = objects.filter { $0 is PixelateObject }
        let clean: CGImage
        if !sameGeometry {
            clean = rendered
        } else if redactions.isEmpty {
            clean = result.image
        } else if let redacted = AnnotationRenderer.render(sourceImage: result.image, objects: redactions) {
            clean = redacted
        } else {
            report(CocoaError(.fileWriteUnknown), context: "Feedback capture was not saved: redaction failed")
            return
        }

        // `self` is the app-lifetime singleton, so strong captures are safe.
        let pending = PendingNote()
        let expectedIndex = (session?.captures.map(\.index).max() ?? 0) + 1
        notePanel.show(captureIndex: expectedIndex, badges: Set(marks.compactMap(\.badge)).sorted()) { text in
            pending.text = text
            if let index = pending.captureIndex {
                Task { await self.saveNote(text, capture: index) }
            }
        }

        Task {
            do {
                let ocrStart = Date()
                let regions = (try? await TextRecognizer.recognize(image: clean)) ?? []
                FeedbackLog.logger.notice("OCR finished: \(regions.count) lines in \(Date().timeIntervalSince(ocrStart), format: .fixed(precision: 1)) s")
                let lines = sameGeometry
                    ? OCRMatcher.removingRedacted(
                        regions.map { FeedbackTextLine(text: $0.text, box: ImageSizing.scale($0.boundingBox, from: source, to: target)) },
                        marks: marks
                    )
                    : []
                guard let annotatedPNG = FeedbackImageExport.png(rendered, size: target),
                      let cleanPNG = FeedbackImageExport.png(clean, size: target) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let ocrText = (sameGeometry ? lines.map(\.text) : regions.map(\.text)).joined(separator: "\n")
                // A session can end while the editor is open. Start a new one
                // rather than lose the capture.
                try await store.startIfNeeded(name: FeedbackNaming.defaultSlug)
                let capture = try await store.addCapture(FeedbackCaptureInput(
                    annotatedPNG: annotatedPNG,
                    cleanPNG: cleanPNG,
                    size: target,
                    sourceApp: result.appName,
                    windowTitle: result.windowName,
                    ocrText: ocrText.isEmpty ? nil : ocrText,
                    marks: OCRMatcher.assignText(to: marks, lines: lines)
                ))
                FeedbackLog.logger.notice("capture \(capture.index) stored")
                pending.captureIndex = capture.index
                if let text = pending.text {
                    await saveNote(text, capture: capture.index)
                } else {
                    await refresh()
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

    /// Holds a note typed before its capture is stored, or the capture's index
    /// once it is stored. Whichever arrives second saves the note.
    @MainActor
    private final class PendingNote {
        var text: String?
        var captureIndex: Int?
    }

    private func report(_ error: Error, context: String) {
        FeedbackLog.logger.error("\(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
        DiagnosticLogger.append(error: error, context: context, category: "Feedback")
        NSSound.beep()
    }
}
