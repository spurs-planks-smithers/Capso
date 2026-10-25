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
/// Read with: log show --last 10m --predicate 'subsystem == "com.drewschulz.nextshot"'
enum FeedbackLog {
    static let logger = Logger(subsystem: "com.drewschulz.nextshot", category: "Feedback")
}

/// Fork: owns feedback rounds. Each saved capture goes into the active
/// round's folder under `defaultRootURL`. This code makes no network calls.
/// It tells `FeedbackJev` when a capture is ready. Only JevKit sends a
/// request, and only with Jev flags on.
@MainActor
final class FeedbackController {
    static let shared = FeedbackController()

    let store: FeedbackRoundStore
    private let jev: FeedbackJev
    private(set) var round: FeedbackRound?
    private(set) var folderURL: URL?

    private weak var captureCoordinator: CaptureCoordinator?
    private var settings: AppSettings?
    private var inlineEditor: InlineAnnotationEditorWindow?
    private var fullEditor: AnnotationEditorWindow?
    private var keyMonitor: Any?
    private let captureBackdrop = FeedbackCaptureBackdrop()
    private let firstDotHint = FeedbackFirstDotHint()
    /// Saves in progress, so `endRound()` can wait for them.
    private var saveTasks: [UUID: Task<Void, Never>] = [:]
    private let statusItem = FeedbackStatusItem()
    private let notePanel = FeedbackNotePanel()
    private var shortcutPanel: FeedbackShortcutPanel?
    private var toast: ToastWindow?
    private let help = FeedbackHelpOverlay()
    private var selectionPhase = SelectionPhase.none
    /// Checks the coordinator's live state while a selection phase is set.
    private var selectionWatch: Task<Void, Never>?
    /// The screen the help box shows on: the pointer's screen at the hotkey,
    /// then the capture's screen.
    private var helpScreen: NSScreen?
    /// End Round while it waits for saves and ends the round.
    private var ending: Task<FeedbackRound, Error>?
    /// True while Copy Prompt and End Round from the menu or its key runs, so
    /// a second press copies nothing more.
    private var copyingRoundPrompt = false
    /// The captures checked in the Recent menu.
    private var basket = FeedbackBasket()
    /// Zip Round and Zip N Selected (#85). Made in `start`.
    private var zip: FeedbackZip?
    private let quickLook = FeedbackQuickLook()
    /// The Recent list as read from disk. The menu asks for it on every open
    /// and every submenu open. The cache decodes a `feedback.json` only when
    /// its modification date or size changed, so an ended or resumed round
    /// shows at once and an unchanged one costs a file attribute read.
    private var roundCache = FeedbackRoundCache()
    /// The unreadable folders named in the last log line, so an unchanged list
    /// logs once, not on every menu open.
    private var loggedUnreadable: [String] = []
    private static let promptCopiedToast = "Prompt copied. Paste it into your agent."
    private static let promptCopiedRoundEndedToast = "Prompt copied. Round ended.\nResume it from Recent Rounds in the \(ForkBranding.shortName) menu."

    /// `~/Library/Application Support/Nextshot`: the standard place for an
    /// app's data. It stays out of the home folder, and macOS privacy controls
    /// do not guard it, so any agent the user starts can read the bundles.
    nonisolated static let defaultRootURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Nextshot", isDirectory: true)

    /// The bundle folder before the Nextshot rename (2026-10-21).
    nonisolated static let legacyRootURL = defaultRootURL.deletingLastPathComponent()
        .appendingPathComponent("CapsoFeedback", isDirectory: true)

    init(rootURL: URL = FeedbackController.defaultRootURL) {
        if rootURL == Self.defaultRootURL {
            Self.moveLegacyFolder(to: rootURL)
        }
        store = FeedbackRoundStore(rootURL: rootURL)
        jev = FeedbackJev(rootURL: rootURL)
    }

    /// Moves the bundles from the folder used before the rename, once. The
    /// active round moves with them. A failed move leaves the old folder
    /// as it was.
    private static func moveLegacyFolder(to rootURL: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: legacyRootURL.path),
              !fileManager.fileExists(atPath: rootURL.path) else { return }
        do {
            try fileManager.moveItem(at: legacyRootURL, to: rootURL)
            FeedbackLog.logger.notice("bundle folder moved to Nextshot")
        } catch {
            let nsError = error as NSError
            FeedbackLog.logger.error("bundle folder move failed: \(nsError.domain, privacy: .public) \(nsError.code)")
        }
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
        connectRoundKeys()
        // Before any recorder can exist, so the guard holds each key's old value.
        FeedbackShortcutGuard.rememberCurrentKeys()
        statusItem.onCopyPromptAndEndRound = { [weak self] in
            FeedbackLog.logger.notice("menu: Copy Prompt and End Round")
            self?.copyPromptAndEndRoundFromMenuOrKey()
        }
        statusItem.onCopyLastCapture = { [weak self] in
            Task { await self?.copyLastCapturePrompt() }
        }
        statusItem.onOpenFolder = { [weak self] in
            self?.openFolder()
        }
        statusItem.onEndRound = { [weak self] in
            FeedbackLog.logger.notice("menu: End Round")
            self?.copyPromptAndEndRoundFromMenuOrKey()
        }
        statusItem.onShowShortcut = { [weak self] in
            self?.showShortcutPanel()
        }
        statusItem.onShowSettings = {
            AppDelegate.shared?.showPreferences()
        }
        zip = FeedbackZip(
            rootURL: store.rootURL,
            waitForSaves: { [weak self] in await self?.waitForSaves() },
            showToast: { [weak self] message in self?.showToast(message, screen: nil) },
            showShare: { [weak self] url in self?.statusItem.showSharePicker(for: url) },
            report: { [weak self] error, context in self?.report(error, context: context) }
        )
        connectHistoryMenu()
        notePanel.onClosed = { [weak self] in
            self?.updateHelp()
        }
        // The help box shows again once the hotkey's capture has frozen the
        // screen, so the frozen image never holds it.
        NotificationCenter.default.addObserver(forName: .capsoCaptureDidFreezeDesktop, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.selectionPhase == .starting else { return }
                self.selectionPhase = .selecting
                self.updateHelp()
            }
        }
        // Posted when the selection ends, before a selected area opens the
        // editor. The task runs after the editor is open.
        NotificationCenter.default.addObserver(forName: .capsoCaptureDidEnd, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.selectionPhase != .none else { return }
                Task { @MainActor in
                    self.selectionPhase = .none
                    self.updateHelp()
                }
            }
        }
        // The status item shows at launch, with or without a round. A
        // round left active before a relaunch shows its count.
        Task { await refresh() }
        jev.warmUp()
    }

    // MARK: - Round actions (hotkey, status menu, App Intents)

    @discardableResult
    func startRound(name: String?) async throws -> FeedbackRound {
        let round = try await store.start(name: name ?? "")
        await refresh()
        return round
    }

    /// Starts an area capture. The first saved capture starts a round named
    /// "feedback" when none is active, so a screenshot copied with Esc leaves
    /// no empty round behind.
    func capture() {
        FeedbackLog.logger.notice("area capture requested")
        let previousPhase = selectionPhase
        let previousScreen = helpScreen
        let selectionWasUp = captureCoordinator?.isCaptureSelectionActive == true
        help.hide()
        selectionPhase = .starting
        helpScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        captureCoordinator?.captureAreaForFeedback()
        // The coordinator starts no selection when one is already up, or
        // when it is gone. Then no end notification comes, and `.starting`
        // would hide the help box until a later capture (#27). A selection
        // that starts sets the coordinator's live state before the call
        // returns. When one was already up, the phase it had comes back, so
        // a selection of ours still shows its keys. The screen comes back
        // too, so a pointer on another display does not move the box (#28).
        if selectionWasUp || captureCoordinator?.isCaptureSelectionActive != true {
            FeedbackLog.logger.notice("area capture not started: a selection is up or the coordinator is gone")
            selectionPhase = selectionWasUp ? previousPhase : .none
            helpScreen = previousScreen
            updateHelp()
        } else {
            watchSelection()
        }
    }

    /// A selection can end with no `.capsoCaptureDidEnd`, for example when
    /// the overlay fails after its delay (#28). Then `selectionPhase` would
    /// keep the help box hidden, or stuck on the select keys, until some
    /// later change. While a phase is set, this checks the coordinator's live
    /// state a few times a second. The coordinator builds a selection in one
    /// main-thread pass, so a check never sees a half-built one. When the
    /// selection is gone, the box shows the current stage again.
    private func watchSelection() {
        selectionWatch?.cancel()
        selectionWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled, self.selectionPhase != .none else { return }
                if self.captureCoordinator?.isCaptureSelectionActive != true {
                    FeedbackLog.logger.notice("area selection ended with no end notification")
                    self.selectionPhase = .none
                    self.updateHelp()
                    return
                }
            }
        }
    }

    /// Copy Prompt and End Round. The menu row, its hotkey, and the Copy
    /// Feedback Prompt Shortcuts action all come here. Copying the active
    /// round's whole prompt ends the round (Drew, 2026-10-24). End Round, its
    /// menu row and Option+Shift+E, comes here too: an ended round's prompt
    /// is on the clipboard and the same toast says so (Drew, 2026-10-24). The round ends
    /// first, so the prompt holds each capture whose save was in progress.
    /// The prompt comes from the ended round, so it matches the `prompt.md`
    /// that `end()` writes. Resume in Recent reopens the round. With a Jev
    /// feature on, the copy waits at most 500 ms for a running capture and
    /// points to refined.md.
    @discardableResult
    func copyPromptAndEndRound() async throws -> String {
        let round = try await endRound()
        let folder = store.rootURL.appendingPathComponent(round.folderName, isDirectory: true)
        await jev.settle(folderName: round.folderName)
        let prompt = PromptBuilder.render(round, folderPath: folder.path, refined: jev.pointsToRefinedFiles)
        copyToClipboard(prompt, toast: Self.promptCopiedRoundEndedToast, screen: nil)
        FeedbackLog.logger.notice("round prompt copied, round ended, \(prompt.count) characters")
        return prompt
    }

    /// The menu row and the hotkey. A second press while the first one runs
    /// does nothing, so one round gives one copy (#26). The check and the
    /// flag come before the first `await`, so two presses cannot both pass.
    /// No active round means nothing to copy: no beep. Other failures beep
    /// and are logged, except when this press joined an end that another
    /// press started: that press reports it, so one failure beeps once.
    private func copyPromptAndEndRoundFromMenuOrKey() {
        Task {
            guard !copyingRoundPrompt else { return }
            copyingRoundPrompt = true
            defer { copyingRoundPrompt = false }
            let joining = ending != nil
            do {
                try await copyPromptAndEndRound()
            } catch FeedbackRoundStore.StoreError.noActiveRound {
                FeedbackLog.logger.notice("copy prompt and end round: no active round")
            } catch {
                if joining {
                    FeedbackLog.logger.notice("copy prompt and end round: the joined end failed")
                } else {
                    report(error, context: "Round prompt was not copied")
                }
            }
        }
    }

    /// Waits for every save in progress, without ending the round. A zip
    /// (#85) waits here, so it holds each capture that is being stored.
    private func waitForSaves() async {
        for task in Array(saveTasks.values) {
            await task.value
        }
    }

    /// Waits for saves in progress first. OCR can take 30 s, and the note
    /// panel can finish before the save does, so ending at once would start a
    /// new round for that capture. A capture saved during the wait waits
    /// for `ending` and then goes into a new round.
    @discardableResult
    func endRound() async throws -> FeedbackRound {
        // One end at a time (#26). A call during an end gets that end's
        // result. A second end would beep after a good end, or end the round
        // that a capture saved during the wait starts.
        if let ending {
            return try await ending.value
        }
        defer { Task { await refresh() } }
        notePanel.close()
        let saves = Array(saveTasks.values)
        FeedbackLog.logger.notice("end round: waiting for \(saves.count) saves")
        let ending = Task {
            for task in saves {
                await task.value
            }
            let round = try await self.store.end()
            FeedbackLog.logger.notice("end round: ended, \(round.captures.count) captures")
            return round
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
        round = await store.activeRound
        folderURL = await store.activeFolderURL
        statusItem.update(round: round)
        updateRoundShortcuts()
        updateHelp()
    }

    // MARK: - Round keys

    /// The four round keys, each on the same path as its menu row. They start
    /// off: no round is known until the first refresh.
    private func connectRoundKeys() {
        KeyboardShortcuts.onKeyDown(for: .feedbackCopyLastCapture) { [weak self] in
            FeedbackLog.logger.notice("hotkey: Copy Last Capture Prompt")
            Task {
                // No active round: nothing to copy, and no beep (#26).
                guard let self, await self.store.activeRound != nil else { return }
                await self.copyLastCapturePrompt()
            }
        }
        KeyboardShortcuts.onKeyDown(for: .feedbackCopyPromptAndEndRound) { [weak self] in
            FeedbackLog.logger.notice("hotkey: Copy Prompt and End Round")
            guard let self, self.roundEndKeyAllowed() else { return }
            self.copyPromptAndEndRoundFromMenuOrKey()
        }
        KeyboardShortcuts.onKeyDown(for: .feedbackOpenRoundFolder) { [weak self] in
            FeedbackLog.logger.notice("hotkey: Open Round Folder")
            self?.openFolder()
        }
        KeyboardShortcuts.onKeyDown(for: .feedbackEndRound) { [weak self] in
            FeedbackLog.logger.notice("hotkey: End Round")
            guard let self, self.roundEndKeyAllowed() else { return }
            self.copyPromptAndEndRoundFromMenuOrKey()
        }
        updateRoundShortcuts()
    }

    /// Option+Shift+R and E beep and do nothing while a capture is open:
    /// being selected, in an editor, or in the note panel (#25). Ending the
    /// round then would save that capture into a new round and close the
    /// note panel before its last answer is saved. The menu rows still end
    /// the round, because a click is deliberate. C and O change nothing, so
    /// they stay active.
    private func roundEndKeyAllowed() -> Bool {
        // `selectionPhase` stays `.starting` when the coordinator does not
        // start the selection, and then no end notification comes. The
        // coordinator's live state confirms that a selection is up.
        let selecting = selectionPhase != .none && captureCoordinator?.isCaptureSelectionActive == true
        let captureOpen = selecting || inlineEditor != nil || fullEditor != nil || notePanel.isOpen
        if captureOpen {
            FeedbackLog.logger.notice("round end key refused: a capture is open")
            NSSound.beep()
        }
        return !captureOpen
    }

    /// Registers the round keys while a round is active and removes them
    /// otherwise (Drew, 2026-10-24). An Option+Shift+letter key types a
    /// character in other apps, so a key that stays registered blocks it.
    /// Both calls do nothing when the state is already right. Settings calls
    /// this after a key change, because the library registers a changed key
    /// at once, with or without a round.
    ///
    /// The library removes a hotkey by its key combination, for every action
    /// that uses it. A round key that shares a combination with an action
    /// that is always on stays registered, so that action keeps working
    /// (#24). Settings refuses such a key, but an upstream recorder can still
    /// set one.
    func updateRoundShortcuts() {
        if round != nil {
            KeyboardShortcuts.enable(KeyboardShortcuts.Name.feedbackRoundKeys)
        } else {
            let alwaysOn = Set(
                (KeyboardShortcuts.Name.allCapso + [.feedbackCapture]).compactMap { KeyboardShortcuts.getShortcut(for: $0) }
            )
            KeyboardShortcuts.disable(KeyboardShortcuts.Name.feedbackRoundKeys.filter { name in
                KeyboardShortcuts.getShortcut(for: name).map { !alwaysOn.contains($0) } ?? false
            })
        }
    }

    // MARK: - Round history (Recent menu)

    /// Gives the status item its data and its actions for the Recent list,
    /// the basket of checked captures, and Resume Round.
    private func connectHistoryMenu() {
        statusItem.stateProvider = { [weak self] in
            guard let self else { return .empty }
            return FeedbackMenuState(
                active: self.round,
                recent: self.recentRounds(),
                basket: self.basket,
                rootURL: self.store.rootURL,
                zipEnabled: Flags.isOn(.zipHandoff)
            )
        }
        statusItem.onZipRecentRound = { [weak self] round in
            FeedbackLog.logger.notice("menu: Zip Round")
            self?.zip?.zipRound(folderName: round.folderName)
        }
        // The basket clears as Copy N Selected clears it, but only when the
        // zip starts: a click during a running zip keeps the checks.
        statusItem.onZipSelected = { [weak self] in
            guard let self else { return }
            FeedbackLog.logger.notice("menu: Zip Selected")
            if self.zip?.zipSelected(self.basket) == true {
                self.basket.removeAll()
            }
        }
        statusItem.onStartRound = { [weak self] in
            self?.capture()
        }
        statusItem.onOpenAllRounds = { [weak self] in
            self?.openAllRounds()
        }
        statusItem.onToggleCapture = { [weak self] key in
            guard let self else { return }
            self.basket.toggle(key)
            self.statusItem.basketDidChange(self.basket)
        }
        statusItem.onClearSelection = { [weak self] in
            self?.basket.removeAll()
        }
        statusItem.onCopySelected = { [weak self] in
            self?.copySelected()
        }
        statusItem.onQuickLook = { [weak self] key in
            self?.showQuickLook(for: key)
        }
        statusItem.onCopyRecentRound = { [weak self] round in
            self?.copyRecentRoundPrompt(round)
        }
        statusItem.onOpenRecentFolder = { [weak self] round in
            guard let self else { return }
            NSWorkspace.shared.open(self.store.rootURL.appendingPathComponent(round.folderName, isDirectory: true))
        }
        statusItem.onResumeRound = { [weak self] round in
            Task { await self?.resumeRound(round) }
        }
    }

    /// The last ended rounds. The cache reads only the folders whose
    /// `feedback.json` changed. Unreadable folders are logged when the list
    /// differs from the last one logged.
    private func recentRounds() -> [FeedbackRound] {
        let listing = roundCache.recent(in: store.rootURL)
        let unreadable = listing.unreadable.sorted()
        if unreadable != loggedUnreadable {
            loggedUnreadable = unreadable
            if !unreadable.isEmpty {
                // Folder names hold the round name, so only the count is public.
                FeedbackLog.logger.error("recent rounds: \(unreadable.count, privacy: .public) unreadable: \(unreadable.joined(separator: ", "), privacy: .private)")
            }
        }
        return listing.rounds
    }

    private func openAllRounds() {
        // The folder does not exist before the first round.
        try? FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(store.rootURL)
    }

    /// Rewrites `manifest.md` and `prompt.md` of each listed folder when they
    /// name an old path, as bundles from before the 2026-10-21 rename do, so a
    /// copied prompt never sends an agent to a folder that is gone. A failed
    /// repair is logged and the copy goes on, because the prompt itself is
    /// built from `feedback.json`.
    private func repairBundles(inFolders folderNames: [String]) async {
        for folderName in Set(folderNames).sorted() {
            guard FeedbackLibrary.bundleFilesNeedRepair(folderName: folderName, in: store.rootURL) else { continue }
            do {
                try await store.repairBundleFiles(folderName: folderName)
                // Folder names hold the round name, so they stay private.
                FeedbackLog.logger.notice("bundle repaired: \(folderName, privacy: .private)")
            } catch {
                let nsError = error as NSError
                FeedbackLog.logger.error("bundle repair failed: \(nsError.domain, privacy: .public) \(nsError.code) \(folderName, privacy: .private)")
            }
        }
    }

    /// Copy N Selected: one capture copies its own prompt, two or more copy
    /// one combined prompt. Both carry the redo line. The basket clears
    /// either way. It clears before the repair, so a second click while the
    /// repair runs finds an empty basket and copies nothing.
    private func copySelected() {
        let selection = basket
        basket.removeAll()
        Task { @MainActor in
            // Repair first, so the rounds read next are the repaired ones.
            await self.repairBundles(inFolders: selection.keys.map(\.folderName))
            let resolved = FeedbackLibrary.entries(for: selection, in: self.store.rootURL)
            switch resolved.entries.count {
            case 0:
                NSSound.beep()
            case 1:
                let entry = resolved.entries[0]
                let prompt = PromptBuilder.renderCapture(entry.capture, folderPath: entry.folderPath, redo: true)
                self.copyToClipboard(prompt, toast: Self.promptCopiedToast, screen: nil)
            case let count:
                let prompt = PromptBuilder.renderSelection(resolved.entries)
                self.copyToClipboard(prompt, toast: "\(count) captures copied\nPaste them into your agent.", screen: nil)
            }
            FeedbackLog.logger.notice("selection copied: \(resolved.entries.count) captures, \(resolved.missing.count) missing")
        }
    }

    private func copyRecentRoundPrompt(_ round: FeedbackRound) {
        Task { @MainActor in
            await self.repairBundles(inFolders: [round.folderName])
            let folder = self.store.rootURL.appendingPathComponent(round.folderName, isDirectory: true)
            let refined = self.jev.pointsToRefinedFiles
                && FileManager.default.fileExists(atPath: folder.appendingPathComponent("refined.md").path)
            let prompt = PromptBuilder.render(round, folderPath: folder.path, redo: true, refined: refined)
            self.copyToClipboard(prompt, toast: Self.promptCopiedToast, screen: nil)
            FeedbackLog.logger.notice("recent round prompt copied, \(prompt.count) characters")
        }
    }

    /// Opens Quick Look on the capture's annotated PNG.
    private func showQuickLook(for key: FeedbackBasketKey) {
        guard let round = FeedbackLibrary.round(named: key.folderName, in: store.rootURL),
              let capture = round.captures.first(where: { $0.index == key.captureIndex }) else {
            NSSound.beep()
            return
        }
        let url = store.rootURL
            .appendingPathComponent(key.folderName, isDirectory: true)
            .appendingPathComponent(capture.imageFile)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        quickLook.show(url)
    }

    /// Reopens an ended round, so the next capture goes into it.
    private func resumeRound(_ listed: FeedbackRound) async {
        do {
            let round = try await store.resume(folderName: listed.folderName)
            FeedbackLog.logger.notice("round resumed, \(round.captures.count) captures")
            await refresh()
        } catch {
            report(error, context: "Feedback round did not resume")
        }
    }

    // MARK: - Help box

    private enum SelectionPhase {
        /// No feedback selection.
        case none
        /// The hotkey was pressed. The screen is not frozen yet.
        case starting
        /// The selection overlay is up on the frozen screen.
        case selecting
    }

    /// Shows the keys for the current stage. The box stays until the round
    /// ends. With no round, it shows only while a capture is in progress.
    private func updateHelp() {
        let stage: FeedbackHelpStage?
        switch selectionPhase {
        case .starting:
            stage = nil
        case .selecting:
            stage = .selecting
        case .none:
            if inlineEditor != nil || fullEditor != nil {
                stage = .marking
            } else if notePanel.isOpen {
                stage = .notes
            } else if round != nil {
                stage = .between
            } else {
                stage = nil
            }
        }
        if let stage {
            help.show(stage, document: inlineEditor?.document, roundActive: round != nil, on: helpScreen)
        } else {
            help.hide()
        }
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
        let defaultTool = FeedbackDefaultTool.begin()
        inlineEditor = InlineAnnotationEditorWindow(
            image: result.image,
            screen: screen,
            screenLocalRect: screenLocalRect,
            onSave: { [weak self] rendered in
                self?.saveFromInlineEditor(rendered, result: result)
            },
            onCopy: { [weak self] rendered in
                // In a round, Copy also keeps the capture.
                ImageUtilities.copyToPasteboard(rendered, format: .png)
                self?.saveFromInlineEditor(rendered, result: result)
            },
            onPin: { [weak self] rendered, _ in
                // In a round, Pin keeps the capture instead of pinning it.
                self?.saveFromInlineEditor(rendered, result: result)
            },
            onClose: { [weak self] in
                defaultTool.restore()
                self?.captureBackdrop.hide()
                self?.firstDotHint.cancel()
                self?.inlineEditor = nil
                self?.removeKeyMonitor()
                self?.updateHelp()
            }
        )
        inlineEditor?.show()
        if let editor = inlineEditor {
            captureBackdrop.show(on: screen, captureFrame: screenLocalRect, below: editor)
            let globalFrame = screenLocalRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
            firstDotHint.schedule(for: editor.document, captureFrame: globalFrame, above: editor)
        }
        installKeyMonitor(image: result.image, screen: screen)
        helpScreen = screen
        updateHelp()
        return true
    }

    /// Keys the inline editor gets here on top of upstream's:
    ///
    /// - Upstream's `AnnotationEscapePolicy` never closes the editor on Esc.
    ///   Here, Esc on an editor with no marks yet copies the screenshot to the
    ///   clipboard and closes the editor, ready to paste into an email (Drew,
    ///   2026-10-21; it replaces the earlier "back to area selection" rule).
    ///   With marks present, upstream's step-back behavior stays, so Esc never
    ///   throws away work.
    /// - Left and Right arrows undo and redo marks (Drew, 2026-10-21). They
    ///   step the document's history directly. They once became Command+Z and
    ///   Shift+Command+Z key events for the toolbar buttons, but a synthetic
    ///   Shift+Command+Z never reached the Redo button: "Z" matched no button,
    ///   and "z" matched Undo (Drew, 2026-10-24).
    ///
    /// Text being typed keeps upstream's keys: Esc commits it, and arrows
    /// move the cursor.
    private func installKeyMonitor(image: CGImage, screen: NSScreen) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Caps Lock, keypad, and fn flags do not change what a key means.
            // Arrow keys always carry the keypad and fn flags.
            let isPlain = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function]).isEmpty
            guard isPlain, [53, 123, 124].contains(event.keyCode) else { return event }
            let keyCode = event.keyCode
            let action = MainActor.assumeIsolated { () -> EditorKeyAction in
                // A text mark joins `document.objects` only when its editing
                // ends, so the first responder tells whether text is being typed.
                guard let editor = self.inlineEditor, editor.isKeyWindow,
                      !(editor.firstResponder is NSText) else {
                    return .pass
                }
                switch keyCode {
                case 123:
                    return Self.stepHistory(of: editor, redo: false) ? .handled : .pass
                case 124:
                    return Self.stepHistory(of: editor, redo: true) ? .handled : .pass
                default:
                    guard editor.document.objects.isEmpty else { return .pass }
                    self.copyScreenshotAndClose(editor, image: image, screen: screen)
                    return .handled
                }
            }
            switch action {
            case .pass: return event
            case .handled: return nil
            }
        }
    }

    private enum EditorKeyAction: Sendable {
        case pass, handled
    }

    /// One undo or redo on the editor's document, then a canvas redraw.
    /// Returns false when there is nothing to step through, so the key passes
    /// on and beeps, as before.
    static func stepHistory(of editor: InlineAnnotationEditorWindow, redo: Bool) -> Bool {
        let document = editor.document
        guard redo ? document.canRedo : document.canUndo else { return false }
        if redo {
            document.redo()
        } else {
            document.undo()
        }
        redrawCanvas(in: editor.contentView)
        return true
    }

    private static func redrawCanvas(in view: NSView?) {
        guard let view else { return }
        if view is AnnotationCanvasNSView {
            view.needsDisplay = true
        }
        for subview in view.subviews {
            redrawCanvas(in: subview)
        }
    }

    /// The image itself, in the user's clipboard format, so it pastes into an
    /// email body. A failed copy keeps the editor open, so the capture is not lost.
    private func copyScreenshotAndClose(_ editor: InlineAnnotationEditorWindow, image: CGImage, screen: NSScreen) {
        let copied = ImageUtilities.copyToPasteboard(image, format: settings?.screenshotClipboardFormat ?? .png)
        FeedbackLog.logger.notice("Esc on an empty editor: screenshot copied \(copied)")
        guard copied else {
            NSSound.beep()
            return
        }
        editor.close()
        showToast("Screenshot copied", screen: screen)
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
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
        let defaultTool = FeedbackDefaultTool.begin()
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
                self.updateHelp()
                return true
            },
            onCopy: { rendered in
                ImageUtilities.copyToPasteboard(rendered, format: .png)
            },
            onPin: { _, _ in },
            onClose: { [weak self] in
                defaultTool.restore()
                self?.fullEditor = nil
                self?.updateHelp()
            }
        )
        fullEditor?.show()
        updateHelp()
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
        // Read now, not inside the task: End Round waits for the saves that
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
                // A capture saved while End Round runs waits for it and then
                // goes into a new round, so its answers have a round to go to.
                _ = try? await endingAtSave?.value
                // A round can end while the editor is open. Start a new one
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
                pending.folderName = await store.activeRound?.folderName
                if let folderName = pending.folderName {
                    jev.captureStored(folderName: folderName, capture: capture.index)
                }
                // Answers given before the capture was stored. Later answers
                // are saved as they arrive.
                for (step, text) in pending.answers {
                    await saveAnswer(step, text, capture: capture.index)
                }
                await refresh()
                return capture.index
            } catch {
                report(error, context: "Feedback capture was not saved")
                // The round may have started before the failure, so the
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
            },
            onEnd: {
                Task { await self.startJev(pending: pending) }
            }
        )
        updateHelp()

        // End Round waits for this task, so it never ends a round before
        // the screen text is in.
        let saveID = UUID()
        pending.screenText = Task {
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
            // Jev jobs get the line boxes from memory: feedback.json keeps
            // only the joined text.
            pending.screenLines = sameGeometry ? lines : nil
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
        saveTasks[saveID] = pending.screenText
    }

    /// Jev starts when the notes are final (the note panel ended) and the
    /// screen text is stored, so every job sees the same complete capture.
    /// It never delays the prompt copy: this runs beside it.
    private func startJev(pending: PendingAnswers) async {
        guard let index = await pending.stored?.value, let folderName = pending.folderName else { return }
        for write in pending.writes {
            await write.value
        }
        await pending.screenText?.value
        jev.captureReady(folderName: folderName, capture: index, screenLines: pending.screenLines)
    }

    /// Waits until the capture and every answer are stored, then puts the
    /// capture's prompt on the clipboard. One paste hands it to any agent.
    private func copyCapturePrompt(pending: PendingAnswers, screen: NSScreen?) async {
        guard let index = await pending.stored?.value else { return }
        for write in pending.writes {
            await write.value
        }
        // One read of the round, so the capture and its folder always match.
        guard let round = await store.activeRound,
              let capture = round.captures.first(where: { $0.index == index }) else {
            NSSound.beep()
            return
        }
        putOnClipboard(capture, in: round, screen: screen)
    }

    /// Copy Last Capture Prompt, from the menu row or its hotkey: the newest
    /// capture's prompt again, for when something else (such as a dictation
    /// tool) replaced the clipboard.
    func copyLastCapturePrompt() async {
        guard let round = await store.activeRound, let capture = round.captures.last else {
            NSSound.beep()
            return
        }
        putOnClipboard(capture, in: round, screen: nil)
    }

    private func putOnClipboard(_ capture: FeedbackCapture, in round: FeedbackRound, screen: NSScreen?) {
        let folder = store.rootURL.appendingPathComponent(round.folderName, isDirectory: true)
        let prompt = PromptBuilder.renderCapture(capture, folderPath: folder.path, refined: jev.pointsToRefinedFiles)
        copyToClipboard(prompt, toast: Self.promptCopiedToast, screen: screen)
        FeedbackLog.logger.notice("capture \(capture.index) prompt copied, \(prompt.count) characters")
    }

    private func copyToClipboard(_ text: String, toast message: String, screen: NSScreen?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast(message, screen: screen)
    }

    private func showToast(_ message: String, screen: NSScreen?) {
        toast?.orderOut(nil)
        toast = ToastWindow(message: message, screen: screen)
        // 3x the old 2.5 s, as for every toast (Drew, 2026-10-24).
        toast?.show(autoDismissAfter: 7.5)
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
        /// The round folder the capture went into, for Jev.
        var folderName: String?
        /// OCR and the screen-text save. Jev starts after it.
        var screenText: Task<Void, Never>?
        /// The OCR lines with boxes in export pixels, redacted lines removed.
        var screenLines: [FeedbackTextLine]?
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
