// App/Feedback/FindCaptureCoordinator.swift
import AppKit
import FeedbackKit

/// Fork: what the Find Capture window asks the controller to do (#125). The
/// controller owns the checks and every round action, so the Nshot menu and
/// the window run one code path.
struct FindCaptureActions {
    var toggle: @MainActor (FeedbackBasketKey) -> Void
    var quickLook: @MainActor (URL) -> Void
    var copySelected: @MainActor () -> Void
    var zipSelected: @MainActor () -> Void
    var clearSelection: @MainActor () -> Void
    /// Each round action takes the round's folder name.
    var copyRoundPrompt: @MainActor (String) -> Void
    var zipRound: @MainActor (String) -> Void
    var openFolder: @MainActor (String) -> Void
    var resumeRound: @MainActor (String) -> Void
}

/// Fork: opens and fills the Find Capture window (#125, Drew, 2026-11-08).
///
/// It works with the `screenshotCopy` capability off, the default: then it
/// lists round captures only. With the capability on, saved screenshots join
/// the list. The index runs off the main actor. It reads the stored summary
/// names and never asks the model, and it skips the per-capture
/// `-screenshot.json` file. It reads local files only.
@MainActor
final class FindCaptureCoordinator {
    struct Sources {
        /// Every compatible round, the active round included.
        var rounds: @MainActor () async -> [FeedbackRound]
        /// The saved screenshots. Empty with `screenshotCopy` off.
        var localItems: @MainActor () async -> [ScreenshotHistoryItem]
        /// The stored on-device names. None while the feature is off.
        var summaryNames: @MainActor () -> SummaryNames
    }

    private let rootURL: URL
    private let sources: Sources
    private let window: ScreenshotHistoryWindow
    /// Each reload takes the next number. A result applies only while its
    /// number is the latest, so an older, slower read never wins.
    private var generation = 0
    /// When the last load started.
    private var lastLoad: ContinuousClock.Instant?
    /// A become-key reload this soon after a load is skipped. Opening the
    /// window loads, then makes it key. Closing Quick Look makes it key again.
    private static let keyReloadGap: Duration = .seconds(1)

    init(rootURL: URL, sources: Sources, actions: FindCaptureActions) {
        self.rootURL = rootURL
        self.sources = sources
        window = ScreenshotHistoryWindow(actions: actions)
        window.onBecomeKey = { [weak self] in self?.windowBecameKey() }
    }

    /// One load per open: it starts before the window becomes key, so the
    /// become-key reload that follows is skipped.
    /// - Parameter query: The text from the menu's search field, or nil from
    ///   the "Find Capture..." row. With a query, the search field shows it
    ///   (empty text clears the field) and the app and round filters reset,
    ///   so the query searches every capture. With nil, the window keeps its
    ///   search and filters.
    func show(basket: FeedbackBasket, roundActive: Bool, query: String? = nil) {
        window.presentation.basket = basket
        window.presentation.roundActive = roundActive
        if query != nil { window.presentation.filterResetRequest &+= 1 }
        reload()
        window.show(query: query)
    }

    private func windowBecameKey() {
        if let lastLoad, ContinuousClock.now - lastLoad < Self.keyReloadGap { return }
        reload()
    }

    /// The controller's checks changed, from the menu or from this window.
    func basketDidChange(_ basket: FeedbackBasket) {
        window.presentation.basket = basket
    }

    /// The active round started, ended, or saved a capture.
    func roundDidChange(active: Bool) {
        window.presentation.roundActive = active
        if window.isVisible { reload() }
    }

    private func reload() {
        generation &+= 1
        lastLoad = .now
        let current = generation
        let rootURL = rootURL
        let sources = sources
        window.presentation.zipEnabled = Flags.isOn(.zipHandoff)
        Task { [weak self] in
            let rounds = await sources.rounds()
            let local = await sources.localItems()
            let summaries = sources.summaryNames()
            let sessionTitle = Flags.isOn(.sessionTitle)
            let items = await Task.detached(priority: .userInitiated) {
                ScreenshotHistoryIndex.items(
                    local: local, rounds: rounds, rootURL: rootURL,
                    summaries: summaries, sessionTitle: sessionTitle, now: Date(),
                    includeProvenance: false
                )
            }.value
            guard let self, self.generation == current else { return }
            self.window.presentation.importedRounds = Set(
                rounds.filter { $0.importedAt != nil }.map(\.folderName)
            )
            self.window.presentation.setItems(items)
        }
    }
}
