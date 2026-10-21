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
/// session's folder under `defaultRootURL`. This code makes no network calls.
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
    private var escapeMonitor: Any?
    /// Saves in progress, so `endSession()` can wait for them.
    private var saveTasks: [UUID: Task<Void, Never>] = [:]
    private let statusItem = FeedbackStatusItem()
    private let notePanel = FeedbackNotePanel()
    private var shortcutPanel: FeedbackShortcutPanel?
    private var toast: ToastWindow?
    /// End Session while it waits for saves and ends the session.
    private var ending: Task<FeedbackSession, Error>?

    /// `~/Library/Application Support/CapsoFeedback`: the standard place for an
    /// app's data. It stays out of the home folder, and macOS privacy controls
    /// do not guard it, so any agent the user starts can read the bundles.
    nonisolated static let defaultRootURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CapsoFeedback", isDirectory: true)

    init(rootURL: URL = FeedbackController.defaultRootURL) {
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
        statusItem.onCopyLastCapture = { [weak self] in
            Task { await self?.copyLastCapturePrompt() }
        }
        statusItem.onOpenFolder = { [weak self] in
            self?.openFolder()
        }
        statusItem.onEndSession = { [weak self] in
            FeedbackLog.logger.notice("menu: End Session")
            Task {
                do {
                    try await self?.endSession()
                } catch {
                    self?.report(error, context: "Feedback session did not end")
                }
            }
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

    /// Starts an area capture. The first saved capture starts a session named
    /// "feedback" when none is active, so a screenshot copied with Esc leaves
    /// no empty session behind.
    func capture() {
        FeedbackLog.logger.notice("area capture requested")
        captureCoordinator?.captureAreaForFeedback()
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

    /// Waits for saves in progress first. OCR can take 30 s, and the note
    /// panel can finish before the save does, so ending at once would start a
    /// new session for that capture. A capture saved during the wait waits
    /// for `ending` and then goes into a new session.
    @discardableResult
    func endSession() async throws -> FeedbackSession {
        defer { Task { await refresh() } }
        notePanel.close()
        let saves = Array(saveTasks.values)
        FeedbackLog.logger.notice("end session: waiting for \(saves.count) saves")
        let ending = Task {
            for task in saves {
                await task.value
            }
            let session = try await self.store.end()
            FeedbackLog.logger.notice("end session: ended, \(session.captures.count) captures")
            return session
        }
        self.ending = ending
        defer {
            if self.ending == ending {
                self.ending = nil
            }
        }
        return try await ending.value
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

    private func openEditor(for captured: CaptureResult) {
        // Area captures carry no window title. Read the window under the
        // selection now, before the editor covers the screen.
        // The app name and window title must name the same window. The
        // frontmost app (captured.appName) can differ from the window under
        // the selection, for example on a second display.
        let underneath = captured.windowName == nil ? FeedbackWindowTitle.window(for: captured) : nil
        let result = CaptureResult(
            image: captured.image,
            mode: captured.mode,
            captureRect: captured.captureRect,
            windowName: captured.windowName ?? underneath?.title,
            appName: underneath?.ownerName ?? captured.appName,
            appBundleIdentifier: underneath == nil ? captured.appBundleIdentifier : nil,
            timestamp: captured.timestamp,
            displayID: captured.displayID
        )
        FeedbackLog.logger.notice("capture received \(result.image.width)x\(result.image.height), window title found: \(result.windowName != nil), opening editor")
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
                self?.removeEscapeMonitor()
            }
        )
        inlineEditor?.show()
        installEscapeMonitor(image: result.image, screen: screen)
        return true
    }

    /// Upstream's `AnnotationEscapePolicy` never closes the editor on Esc.
    /// Here, Esc on an editor with no marks yet copies the screenshot to the
    /// clipboard and closes the editor, ready to paste into an email (Drew,
    /// 2026-10-21; it replaces the earlier "back to area selection" rule).
    /// With marks present, upstream's step-back behavior stays, so Esc never
    /// throws away work.
    private func installEscapeMonitor(image: CGImage, screen: NSScreen) {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Caps Lock, keypad, and fn flags do not change what Esc means.
            let isPlainEscape = event.keyCode == 53
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.capsLock, .numericPad, .function]).isEmpty
            guard isPlainEscape else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                // A text mark joins `document.objects` only when its editing
                // ends, so text being typed must keep upstream's Esc (commit).
                guard let editor = self.inlineEditor, editor.isKeyWindow,
                      editor.document.objects.isEmpty, !(editor.firstResponder is NSText) else {
                    return false
                }
                // The image itself, in the user's clipboard format, so it
                // pastes into an email body.
                let copied = ImageUtilities.copyToPasteboard(image, format: self.settings?.screenshotClipboardFormat ?? .png)
                FeedbackLog.logger.notice("Esc on an empty editor: screenshot copied \(copied)")
                // A failed copy keeps the editor open, so the capture is not lost.
                guard copied else {
                    NSSound.beep()
                    return true
                }
                editor.close()
                self.showToast("Screenshot copied", screen: screen)
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
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

    /// Opens the note panel at once, then sizes both PNG files and adds the
    /// capture. On-device OCR runs after that and adds the screen text. OCR can
    /// take 30 s when the Neural Engine is cold (measured 2026-10-20), so
    /// neither the note nor the copied prompt waits for it. An answer given
    /// before the capture is stored is held in `PendingAnswers` and saved
    /// right after. When the note panel finishes, the capture's prompt goes
    /// on the clipboard.
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
        let pending = PendingAnswers()
        let name = FeedbackNaming.captureName(
            windowTitle: result.windowName,
            sourceApp: result.appName,
            capturedAt: result.timestamp,
            timeZone: store.timeZone
        )
        // Read now, not inside the task: End Session waits for the saves that
        // exist when it starts, so a save that started before it must not
        // wait for it in turn.
        let endingAtSave = ending

        // Stores the capture without screen text, so the copied prompt never
        // waits for OCR. It is set before the note panel opens, so the
        // panel's callbacks always find it.
        pending.stored = Task { () -> Int? in
            do {
                guard let annotatedPNG = FeedbackImageExport.png(rendered, size: target),
                      let cleanPNG = FeedbackImageExport.png(clean, size: target) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                // A capture saved while End Session runs waits for it and then
                // goes into a new session, so its answers have a session to go to.
                _ = try? await endingAtSave?.value
                // A session can end while the editor is open. Start a new one
                // rather than lose the capture.
                try await store.startIfNeeded(name: FeedbackNaming.defaultSlug)
                let capture = try await store.addCapture(FeedbackCaptureInput(
                    annotatedPNG: annotatedPNG,
                    cleanPNG: cleanPNG,
                    size: target,
                    capturedAt: result.timestamp,
                    sourceApp: result.appName,
                    windowTitle: result.windowName,
                    marks: marks
                ))
                // File names hold window-title text, so the log keeps only the number.
                FeedbackLog.logger.notice("capture \(capture.index) stored")
                pending.captureIndex = capture.index
                // Answers given before the capture was stored. Later answers
                // are saved as they arrive.
                for (step, text) in pending.answers {
                    await saveAnswer(step, text, capture: capture.index)
                }
                await refresh()
                return capture.index
            } catch {
                report(error, context: "Feedback capture was not saved")
                // The session may have started before the failure, so the
                // menu must show it.
                await refresh()
                return nil
            }
        }

        let screen = NSScreen.screens.first { $0.displayID == result.displayID }
        notePanel.show(
            title: name,
            badges: Set(marks.compactMap(\.badge)).sorted(),
            previews: circlePreviews(rendered: rendered, objects: sameGeometry ? objects : [], result: result),
            overview: rendered,
            onAnswer: { step, text in
                pending.answers.append((step, text))
                if let index = pending.captureIndex {
                    pending.writes.append(Task { await self.saveAnswer(step, text, capture: index) })
                }
            },
            onFinish: {
                Task { await self.copyCapturePrompt(pending: pending, screen: screen) }
            }
        )

        // End Session waits for this task, so it never ends a session before
        // the screen text is in.
        let saveID = UUID()
        saveTasks[saveID] = Task {
            defer { self.saveTasks[saveID] = nil }
            guard let index = await pending.stored?.value else { return }
            let ocrStart = Date()
            let regions = (try? await TextRecognizer.recognize(image: clean)) ?? []
            FeedbackLog.logger.notice("OCR finished: \(regions.count) lines in \(Date().timeIntervalSince(ocrStart), format: .fixed(precision: 1)) s")
            let lines = sameGeometry
                ? OCRMatcher.removingRedacted(
                    regions.map { FeedbackTextLine(text: $0.text, box: ImageSizing.scale($0.boundingBox, from: source, to: target)) },
                    marks: marks
                )
                : []
            let ocrText = (sameGeometry ? lines.map(\.text) : regions.map(\.text)).joined(separator: "\n")
            do {
                try await store.setScreenText(
                    capture: index,
                    ocrText: ocrText.isEmpty ? nil : ocrText,
                    markTexts: OCRMatcher.assignText(to: marks, lines: lines).map(\.ocrText)
                )
            } catch {
                report(error, context: "Feedback screen text was not saved")
            }
            await refresh()
        }
    }

    /// Waits until the capture and every answer are stored, then puts the
    /// capture's prompt on the clipboard. One paste hands it to any agent.
    private func copyCapturePrompt(pending: PendingAnswers, screen: NSScreen?) async {
        guard let index = await pending.stored?.value else { return }
        for write in pending.writes {
            await write.value
        }
        // One read of the session, so the capture and its folder always match.
        guard let session = await store.activeSession,
              let capture = session.captures.first(where: { $0.index == index }) else {
            NSSound.beep()
            return
        }
        putOnClipboard(capture, in: session, screen: screen)
    }

    /// Copy Last Capture in the menu: the newest capture's prompt again, for
    /// when something else (such as a dictation tool) replaced the clipboard.
    func copyLastCapturePrompt() async {
        guard let session = await store.activeSession, let capture = session.captures.last else {
            NSSound.beep()
            return
        }
        putOnClipboard(capture, in: session, screen: nil)
    }

    private func putOnClipboard(_ capture: FeedbackCapture, in session: FeedbackSession, screen: NSScreen?) {
        let folder = store.rootURL.appendingPathComponent(session.folderName, isDirectory: true)
        let prompt = PromptBuilder.renderCapture(capture, folderPath: folder.path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        FeedbackLog.logger.notice("capture \(capture.index) prompt copied, \(prompt.count) characters")
        showToast("Prompt copied. Paste it into your agent.", screen: screen)
    }

    private func showToast(_ message: String, screen: NSScreen?) {
        toast?.orderOut(nil)
        toast = ToastWindow(message: message, screen: screen)
        toast?.show(autoDismissAfter: 2.5)
    }

    /// One crop of the annotated capture per circle, in the capture's own
    /// pixels, with about 150 points of context around each circle.
    private func circlePreviews(rendered: CGImage, objects: [any AnnotationObject], result: CaptureResult) -> [Int: CGImage] {
        let size = PixelSize(width: rendered.width, height: rendered.height)
        let marks = FeedbackMarkMapper.marks(from: objects, source: size, target: size)
        let pixelsPerPoint = max(Double(result.image.width) / max(Double(result.captureRect.width), 1), 1)
        let crops = PreviewCrop.cropsByBadge(
            marks: marks,
            imageSize: size,
            margin: Int(150 * pixelsPerPoint),
            aspectRatio: FeedbackNotePanel.previewAspectRatio
        )
        return crops.compactMapValues { box in
            rendered.cropping(to: CGRect(x: box.x1, y: box.y1, width: box.x2 - box.x1, height: box.y2 - box.y1))
        }
    }

    private func saveAnswer(_ step: FeedbackNoteStep, _ text: String, capture index: Int) async {
        do {
            switch step {
            case .circle(let badge):
                try await store.setInstruction(capture: index, badge: badge, text: text)
            case .note:
                try await store.setNote(capture: index, text: text)
            }
        } catch {
            report(error, context: "Feedback answer was not saved")
        }
        await refresh()
    }

    /// Holds answers given before the capture is stored, the capture's index
    /// once it is stored, and the saves the copied prompt must wait for.
    @MainActor
    private final class PendingAnswers {
        var answers: [(FeedbackNoteStep, String)] = []
        var captureIndex: Int?
        /// Stores the capture. Its value is the capture index, or nil when the save failed.
        var stored: Task<Int?, Never>?
        /// Answers saved after the capture was stored.
        var writes: [Task<Void, Never>] = []
    }

    private func report(_ error: Error, context: String) {
        // Error descriptions can contain file names, which hold window-title
        // text, so only the domain and code are public.
        let nsError = error as NSError
        FeedbackLog.logger.error("\(context, privacy: .public): \(nsError.domain, privacy: .public) \(nsError.code) \(nsError.localizedDescription, privacy: .private)")
        DiagnosticLogger.append(error: error, context: context, category: "Feedback")
        NSSound.beep()
    }
}
