// App/Feedback/FeedbackUpdateReminder.swift
import AppKit
import FeedbackKit

/// Fork: the offline update reminder (#203). Nextshot never goes online, so
/// it cannot tell whether a newer build exists. About a week after a build
/// first runs, it shows one toast and a "Get the latest version…" row in the
/// Nshot menu. The row opens nextshot.dev in the browser. The app makes no
/// request. `UpdateReminder` in FeedbackKit holds the rules.
///
/// The closures keep this class free of the controller, so a test can pass
/// fakes and a private `UserDefaults` suite.
@MainActor
final class FeedbackUpdateReminder {
    /// The toast waits this long after launch, so it never lands in the
    /// start-up rush after a login.
    static let launchDelay: TimeInterval = 60
    /// How often a long-running copy looks again.
    static let recheckInterval: TimeInterval = 3 * 60 * 60

    private let defaults: UserDefaults
    private let version: String
    private let build: String
    private let now: () -> Date
    private let gates: () -> UpdateReminder.Gates
    private let hasRounds: () -> Bool
    private let isIdle: () -> Bool
    private let showToast: (String) -> Void
    private let openLink: (URL) -> Void
    private var launchTimer: Timer?
    private var recheckTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        version: String,
        build: String,
        now: @escaping () -> Date = Date.init,
        gates: @escaping () -> UpdateReminder.Gates,
        hasRounds: @escaping () -> Bool,
        isIdle: @escaping () -> Bool,
        showToast: @escaping (String) -> Void,
        openLink: @escaping (URL) -> Void
    ) {
        self.defaults = defaults
        self.version = version
        self.build = build
        self.now = now
        self.gates = gates
        self.hasRounds = hasRounds
        self.isIdle = isIdle
        self.showToast = showToast
        self.openLink = openLink
    }

    /// Stops the timers and the wake watch. The app never calls this, since
    /// the controller lives as long as the app. A test does.
    func stop() {
        launchTimer?.invalidate()
        recheckTimer?.invalidate()
        launchTimer = nil
        recheckTimer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    /// Starts this build's clock at once. The first toast check comes 60
    /// seconds later, then at each wake and every 3 hours.
    func start() {
        evaluate(allowToast: false)
        launchTimer = Timer.scheduledTimer(withTimeInterval: Self.launchDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.recheck() }
        }
        recheckTimer = Timer.scheduledTimer(withTimeInterval: Self.recheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recheck() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recheck() }
        }
    }

    /// One look with the toast allowed: the launch delay, a wake, or the
    /// 3-hour timer. The toast shows only at an idle moment, once per build.
    func recheck() {
        evaluate(allowToast: true)
    }

    /// Whether the menu shows the row now. It reads the live switches, so a
    /// click on the row, the Settings toggle, or the flag changes the menu at
    /// its next open. It never shows the toast.
    func menuRowVisible() -> Bool {
        let shows = evaluate(allowToast: false).showsRow
        if shows { FeedbackLog.logger.notice("update reminder: row in menu") }
        return shows
    }

    /// The row was clicked: open the site and hide the row for this build.
    func openSite() {
        openLink(UpdateReminder.link(version: version))
        UpdateReminder.hidingRow(UpdateReminder.State(defaults: defaults), build: build).save(to: defaults)
        FeedbackLog.logger.notice("update reminder: site opened")
    }

    @discardableResult
    private func evaluate(allowToast: Bool) -> UpdateReminder.Display {
        let result = UpdateReminder.evaluate(
            state: UpdateReminder.State(defaults: defaults),
            now: now(),
            build: build,
            gates: gates(),
            hasRounds: hasRounds,
            isIdle: { allowToast && self.isIdle() }
        )
        result.state.save(to: defaults)
        if result.display.showsToast {
            FeedbackLog.logger.notice("update reminder: toast")
            showToast(UpdateReminder.toastText(productName: ForkBranding.name, menuName: ForkBranding.shortName))
        }
        return result.display
    }
}
