// App/Sources/AppDelegate.swift
import AppKit
import SharedKit
import ShareKit
import OCRKit
import KeyboardShortcuts
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Static reference to the live AppDelegate. Use this instead of
    /// `NSApp.delegate as? AppDelegate`, which fails under SwiftUI's
    /// `@NSApplicationDelegateAdaptor` proxy wrapping.
    static private(set) var shared: AppDelegate?

    private var menuBarController: MenuBarController?
    let settings = AppSettings()
    let permissionManager = PermissionManager()
    private(set) var captureCoordinator: CaptureCoordinator?
    private(set) var recordingCoordinator: RecordingCoordinator?
    let desktopIconsCover = DesktopIconsCover()
    private(set) var ocrCoordinator: OCRCoordinator?
    private(set) var translationCoordinator: TranslationCoordinator?
    private(set) var historyCoordinator: HistoryCoordinator?
    private(set) var shareCoordinator: ShareCoordinator?
    private var preferencesWindow: PreferencesWindow?
    private var automationURLRequestBuffer = AutomationURLRequestBuffer()
    private var imageFileOpenBuffer = ImageFileOpenBuffer()
    /// Sparkle update coordinator used by preferences and manual update checks.
    private(set) var updateManager: UpdateManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A hosted unit-test bundle only needs the AppKit run loop. Avoid
        // registering global shortcuts, touching real settings, or starting
        // coordinators in the separate test-host process.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        SingleInstanceGuard.quitIfAnotherCopyRuns() // Fork: App/Feedback
        ForkDefaults.register() // Fork: App/Feedback

        Self.shared = self
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleReopen(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEReopenApplication)
        )
        DiagnosticLogger.installUncaughtExceptionHandler()

        // Show tooltips faster (default is ~2s, reduce to 0.3s)
        UserDefaults.standard.set(300, forKey: "NSInitialToolTipDelay")

        _ = Capabilities.current
        if Capabilities.current.automaticUpdates { updateManager = UpdateManager() }
        if Capabilities.current.standaloneCapture { migrateShortcutsIfNeeded() }
        settings.startTrial()
        captureCoordinator = CaptureCoordinator(settings: settings)
        recordingCoordinator = RecordingCoordinator(settings: settings)
        ocrCoordinator = OCRCoordinator(settings: settings)
        translationCoordinator = TranslationCoordinator(settings: settings)
        historyCoordinator = HistoryCoordinator(settings: settings)
        shareCoordinator = makeShareCoordinator(settings: settings)
        captureCoordinator!.ocrCoordinator = ocrCoordinator
        captureCoordinator!.translationCoordinator = translationCoordinator
        captureCoordinator!.recordingCoordinator = recordingCoordinator
        captureCoordinator!.historyCoordinator = historyCoordinator
        captureCoordinator!.shareCoordinator = shareCoordinator
        historyCoordinator!.shareCoordinator = shareCoordinator
        recordingCoordinator!.historyCoordinator = historyCoordinator
        historyCoordinator!.onEditRecording = { [weak recordingCoordinator] source in
            recordingCoordinator?.openEditor(for: source)
        }
        recordingCoordinator!.desktopIconsCover = desktopIconsCover
        if Capabilities.current.recordingTools { recordingCoordinator!.recoverInterruptedRecording() }
        preferencesWindow = PreferencesWindow(settings: settings, permissionManager: permissionManager, updateManager: updateManager)
        if settings.diagnosticLoggingEnabled {
            DiagnosticLogger.append(
                "App launched version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown") build=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")",
                category: "App"
            )
        }
        menuBarController = MenuBarController(
            settings: settings,
            captureCoordinator: captureCoordinator!,
            recordingCoordinator: recordingCoordinator!,
            ocrCoordinator: ocrCoordinator!,
            translationCoordinator: translationCoordinator!,
            historyCoordinator: historyCoordinator!,
            desktopIconsCover: desktopIconsCover,
            onShowPreferences: { [weak self] in self?.showPreferences() }
        )
        registerGlobalShortcuts()
        FeedbackController.shared.start(captureCoordinator: captureCoordinator!, settings: settings) // Fork: App/Feedback
        performPendingAutomationURLAction()
        performPendingImageFileOpen()
        if Capabilities.current.standaloneCapture { historyCoordinator?.runCleanup() }

        NotificationCenter.default.addObserver(
            forName: .openScreenshotSettings,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let tabRaw = (notification.object as? PreferencesTab)?.rawValue
            MainActor.assumeIsolated {
                let tab = tabRaw.flatMap(PreferencesTab.init(rawValue:)) ?? .screenshots
                self?.preferencesWindow?.show(tab: tab)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .openPreferencesTab,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let tabRaw = (notification.object as? PreferencesTab)?.rawValue
            MainActor.assumeIsolated {
                let tab = tabRaw.flatMap(PreferencesTab.init(rawValue:)) ?? .general
                self?.preferencesWindow?.show(tab: tab)
            }
        }
        Task {
            await permissionManager.checkScreenRecordingPermission()
        }
        // Load Vision's OCR models off the critical path so the first
        // "Capture Text" of a session doesn't stall on one-time model setup.
        if !OCRProcessFallback.shouldSkipPrewarm {
            Task.detached(priority: .utility) {
                await TextRecognizer.prewarm()
            }
        }
    }

    /// One-time migration: clear stale KeyboardShortcuts UserDefaults so new defaults apply.
    private func migrateShortcutsIfNeeded() {
        let migrationKey = "shortcutsMigratedToOptionShift"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            KeyboardShortcuts.reset(.captureArea, .captureFullscreen, .captureWindow, .captureText, .recordScreen)
            UserDefaults.standard.set(true, forKey: migrationKey)
        }

        let translationMigrationKey = "captureAndTranslateShortcutMigratedToOptionShift"
        guard !UserDefaults.standard.bool(forKey: translationMigrationKey) else { return }
        let oldDefault = KeyboardShortcuts.Shortcut(.t, modifiers: [.command, .shift])
        if KeyboardShortcuts.getShortcut(for: .captureAndTranslate) == oldDefault {
            KeyboardShortcuts.reset(.captureAndTranslate)
        }
        UserDefaults.standard.set(true, forKey: translationMigrationKey)
    }

    private func registerGlobalShortcuts() {
        KeyboardShortcuts.disable(KeyboardShortcuts.Name.allCapso.filter { !Capabilities.allowsShortcut($0) })
        func register(_ name: KeyboardShortcuts.Name, action: @escaping () -> Void) {
            guard Capabilities.allowsShortcut(name) else { return }
            KeyboardShortcuts.onKeyDown(for: name, action: action)
        }
        register(.captureArea) { [weak self] in
            self?.captureCoordinator?.captureArea()
        }
        register(.captureAllInOne) { [weak self] in
            self?.captureCoordinator?.captureAllInOne()
        }
        register(.captureFullscreen) { [weak self] in
            self?.captureCoordinator?.captureFullscreen()
        }
        register(.captureWindow) { [weak self] in
            self?.captureCoordinator?.captureWindow()
        }
        register(.captureText) { [weak self] in
            self?.ocrCoordinator?.startInstantOCR()
        }
        register(.recordScreen) { [weak self] in
            self?.recordingCoordinator?.startRecordingFlow()
        }
        register(.recordFullscreen) { [weak self] in
            self?.recordingCoordinator?.startFullScreenRecordingFlow()
        }
        register(.captureScrolling) { [weak self] in
            self?.captureCoordinator?.captureScrolling()
        }
        register(.selfTimerCapture) { [weak self] in
            self?.captureCoordinator?.captureAreaWithSelfTimer()
        }
        register(.captureAreaToClipboard) { [weak self] in
            self?.captureCoordinator?.captureAreaToClipboard()
        }
        register(.captureAreaAndShare) { [weak self] in
            self?.captureCoordinator?.captureAreaAndShare()
        }
        register(.captureAreaAndAnnotate) { [weak self] in
            self?.captureCoordinator?.captureAreaAndAnnotate()
        }
        register(.captureAreaAndPin) { [weak self] in
            self?.captureCoordinator?.captureAreaAndPin()
        }
        register(.pinFromClipboard) { [weak self] in
            self?.captureCoordinator?.pinFromClipboard()
        }
        register(.togglePins) { [weak self] in
            self?.captureCoordinator?.togglePinsVisibility()
        }
        register(.editClipboardImage) { [weak self] in
            self?.captureCoordinator?.editClipboardImage()
        }
        register(.captureLastArea) { [weak self] in
            self?.captureCoordinator?.replayLastCapture()
        }
        register(.screenshotHistory) { [weak self] in
            self?.historyCoordinator?.toggleWindow()
        }
        register(.captureAndTranslate) { [weak self] in
            guard let self else { return }
            // If the user pressed the global Translate shortcut while a Quick
            // Access panel has focus
            // (hovered / clicked), translate THAT capture rather than
            // starting a brand-new capture flow. The global hotkey otherwise
            // always wins over the panel's local `.keyboardShortcut`.
            if self.captureCoordinator?.invokeQuickAccessTranslateIfKey() == true {
                return
            }
            self.translationCoordinator?.startCaptureAndTranslate()
        }
        register(.translateSelectedText) { [weak self] in
            self?.translationCoordinator?.translateSelectedText()
        }
        register(.translateTypedText) { [weak self] in
            self?.translationCoordinator?.translateTypedText()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let (imageFiles, remainder) = ImageFileOpenRequest.partition(urls: urls)

        // Opening image files is never gated by the Automation URLs toggle —
        // that setting only governs the `capso://` automation scheme.
        if !imageFiles.isEmpty, Capabilities.current.standaloneCapture {
            imageFileOpenBuffer.enqueue(imageFiles)
            performPendingImageFileOpen()
        }

        if !imageFiles.isEmpty, !Capabilities.current.standaloneCapture {
            let alert = NSAlert()
            alert.messageText = "Image editing is unavailable"
            alert.informativeText = "This version focuses on feedback rounds. Your image file stays unchanged."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        guard !remainder.isEmpty, Capabilities.current.automationURLs else { return }

        guard let actionURL = remainder.first(where: { AutomationURLAction(url: $0) != nil }),
              let action = AutomationURLAction(url: actionURL) else {
            logAutomationURL("Ignored unsupported request")
            return
        }
        guard Capabilities.allowsAutomation(action) else { return }
        guard settings.automationURLsEnabled || askToAllowAutomationURLs(for: actionURL) else {
            logAutomationURL("Ignored request because Automation URLs are disabled")
            return
        }

        automationURLRequestBuffer.enqueue(action)
        performPendingAutomationURLAction()
    }

    /// Asks once whether other apps may control Capso. Returns whether to run the command.
    private func askToAllowAutomationURLs(for url: URL) -> Bool {
        guard !settings.automationURLsAsked else { return false }
        settings.automationURLsAsked = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Another app wants to control Capso")
        alert.informativeText = String(localized: "It sent this command:\n\(url.absoluteString)\n\nAllow other apps to start captures and recordings with Capso? You can change this later in Settings → General.")
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Don't Allow"))
        let allowed = alert.runModal() == .alertFirstButtonReturn
        settings.automationURLsEnabled = allowed
        return allowed
    }

    private func performPendingImageFileOpen() {
        guard Capabilities.current.standaloneCapture else { return }
        guard let urls = imageFileOpenBuffer.takeIfReady(coordinatorIsReady: captureCoordinator != nil) else {
            return
        }
        captureCoordinator?.openImageFiles(urls)
    }

    private func performPendingAutomationURLAction() {
        let selectionIsActive = captureCoordinator?.isCaptureSelectionActive ?? false
        guard let action = automationURLRequestBuffer.takeIfReady(
            coordinatorIsReady: captureCoordinator != nil,
            captureSelectionIsActive: selectionIsActive
        ), let captureCoordinator else {
            return
        }

        guard Capabilities.allowsAutomation(action) else { return }
        switch action {
        case .captureArea:
            captureCoordinator.captureArea()
        case .captureFullscreen:
            captureCoordinator.markNextCaptureAsAutomated()
            captureCoordinator.captureFullscreen()
        case .captureWindow:
            captureCoordinator.captureWindow()
        case .captureAllInOne:
            captureCoordinator.captureAllInOne()
        case .captureScrolling:
            captureCoordinator.captureScrolling()
        case .captureSelfTimer:
            captureCoordinator.captureAreaWithSelfTimer()
        case .captureLastArea:
            captureCoordinator.markNextCaptureAsAutomated()
            captureCoordinator.replayLastCapture()
        case .captureAreaToClipboard:
            captureCoordinator.captureAreaToClipboard()
        case .captureAreaAndShare:
            captureCoordinator.captureAreaAndShare()
        case .captureAreaAndAnnotate:
            captureCoordinator.captureAreaAndAnnotate()
        case .captureAreaAndPin:
            captureCoordinator.captureAreaAndPin()
        case .pinFromClipboard:
            captureCoordinator.pinFromClipboard()
        case .editClipboardImage:
            captureCoordinator.editClipboardImage()
        case .openImageFile:
            captureCoordinator.openImageFilesWithPanel()
        case .captureOCR:
            ocrCoordinator?.startInstantOCR()
        case .captureAndTranslate:
            translationCoordinator?.startCaptureAndTranslate()
        case .translateSelectedText:
            translationCoordinator?.translateSelectedText()
        case .translateTypedText:
            translationCoordinator?.translateTypedText()
        case .recordArea:
            recordingCoordinator?.startRecordingFlow()
        case .recordFullscreen:
            recordingCoordinator?.startFullScreenRecordingFlow()
        case .openHistory:
            historyCoordinator?.showWindow()
        case .openPreferences:
            showPreferences()
        case .hideDesktopIcons:
            desktopIconsCover.setHiddenManually(true)
        case .showDesktopIcons:
            desktopIconsCover.setHiddenManually(false)
        case .toggleDesktopIcons:
            desktopIconsCover.setHiddenManually(!desktopIconsCover.isHiddenManually)
        }
        logAutomationURL("Performed action \(String(describing: action))")
    }

    private func logAutomationURL(_ message: String) {
        guard settings.diagnosticLoggingEnabled else { return }
        DiagnosticLogger.append(message, category: "AutomationURL")
    }

    /// Called when the user reopens the app while it's already running
    /// (Spotlight, Launchpad, Finder). Launch — including Launch at Login —
    /// stays silent. Reopen always shows Preferences, since the menu bar icon
    /// may be hidden by the user or crowded out behind the notch. Handled as a
    /// raw Apple Event because SwiftUI never forwards
    /// `applicationShouldHandleReopen` to the adaptor delegate.
    @objc private func handleReopen(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        showPreferences()
    }

    func showPreferences() {
        preferencesWindow?.show()
    }

    /// Rebuild the live `ShareCoordinator` from current `AppSettings` + Keychain.
    /// Called after the Cloud Share wizard saves new credentials, and after the
    /// user resets the configuration — so the next capture's share button
    /// reflects the current state without requiring a relaunch.
    func refreshShareCoordinator() {
        shareCoordinator = makeShareCoordinator(settings: settings)
        captureCoordinator?.shareCoordinator = shareCoordinator
        historyCoordinator?.shareCoordinator = shareCoordinator
    }

    private func makeShareCoordinator(settings: AppSettings) -> ShareCoordinator? {
        guard
            Capabilities.current.cloudShare,
            settings.isCloudShareConfigured,
            let providerRaw = settings.cloudShareProvider,
            let provider = ShareProvider(rawValue: providerRaw),
            let urlPrefix = settings.cloudShareURLPrefix,
            let bucket = settings.cloudShareBucket
        else {
            return nil
        }

        let keychain = KeychainHelper(service: "com.awesomemacapps.capso.share.\(provider.rawValue)")
        guard
            let access = AppDelegate.keychainString(keychain, account: "accessKey"),
            let secret = AppDelegate.keychainString(keychain, account: "secretKey")
        else {
            return nil
        }

        var fields: [String: String] = [:]
        if let accountID = settings.cloudShareAccountID {
            fields["accountID"] = accountID
        }
        if let region = settings.cloudShareRegion {
            fields["region"] = region
        }
        if let endpoint = settings.cloudShareEndpoint {
            fields["endpoint"] = endpoint
        }
        if let pathPrefix = settings.cloudSharePathPrefix {
            fields["pathPrefix"] = pathPrefix
        }

        let config = ShareConfig(provider: provider, urlPrefix: urlPrefix, bucket: bucket, fields: fields)
        guard let destination = try? ShareDestinationFactory.make(config: config, accessKey: access, secretKey: secret) else {
            return nil
        }
        return ShareCoordinator(destination: destination) { [settings] in
            settings.cloudShareCopyLinkWhenUploadStarts
        }
    }

    /// Read a string from Keychain. Returns nil on missing entry or known recoverable errors.
    /// Any unexpected error triggers an assertion failure in debug builds.
    private static func keychainString(_ keychain: KeychainHelper, account: String) -> String? {
        do {
            return try keychain.get(account: account)
        } catch KeychainError.interactionNotAllowed {
            // Keychain locked (e.g., app launched at login before user logs in).
            // Returning nil leaves the coordinator nil; the user can re-enter
            // Settings → Cloud Share to trigger refreshShareCoordinator().
            return nil
        } catch {
            assertionFailure("Unexpected Keychain error reading '\(account)': \(error)")
            return nil
        }
    }
}
