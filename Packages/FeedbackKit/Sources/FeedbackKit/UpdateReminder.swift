// Packages/FeedbackKit/Sources/FeedbackKit/UpdateReminder.swift
import Foundation

/// The offline update reminder (#203). Nextshot never goes online, so it
/// cannot tell whether a newer build exists. About a week after a build first
/// runs, it says one may be out and links to nextshot.dev. The page compares
/// versions in the browser.
///
/// This type holds the rules, the stored state, the words, and the link. It
/// reads no clock, opens nothing, and makes no request, so a test can run
/// every case. The link is the one place a URL literal is allowed in this
/// package (`NetworkSourceScanTests` lists it).
public enum UpdateReminder {
    /// A build must have run this long before the reminder shows (7 days).
    public static let waitSeconds: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Words

    public static let rowTitle = "Get the latest version…"

    /// Two short lines, because a toast is one line of text per row and does
    /// not wrap. The menu name is "Nshot" or "Nshot Dev".
    public static func toastText(productName: String, menuName: String) -> String {
        "New \(productName) builds ship often.\n\(productName) stays offline, so check the \(menuName) menu."
    }

    // MARK: - Link

    private static let siteURL = URL(string: "https://nextshot.dev/")!

    /// `https://nextshot.dev/#from=0.5.0`. The version sits after the `#`,
    /// which a browser never sends to a server, so the site learns nothing.
    /// Only letters, digits, dots, and hyphens pass, so the text cannot add a
    /// query or a second fragment.
    public static func link(version: String) -> URL {
        let safe = version.unicodeScalars.filter {
            ($0.value < 128) && (CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-")
        }
        guard !safe.isEmpty else { return siteURL }
        var parts = URLComponents(url: siteURL, resolvingAgainstBaseURL: false)!
        parts.fragment = "from=" + String(safe)
        return parts.url ?? siteURL
    }

    // MARK: - Switches

    /// The Settings toggle. On until the person turns it off.
    public static let enabledKey = "updateReminder.enabled"

    public static func isEnabled(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    /// The three switches that can turn the reminder off. The feature flag is
    /// the app owner's control, the toggle is the person's, and the third
    /// hands the job to Sparkle if the update flag ever turns on (roadmap M3).
    public struct Gates: Equatable, Sendable {
        public var flagOn: Bool
        public var enabled: Bool
        public var automaticUpdates: Bool

        public init(flagOn: Bool, enabled: Bool, automaticUpdates: Bool) {
            self.flagOn = flagOn
            self.enabled = enabled
            self.automaticUpdates = automaticUpdates
        }

        var allowsReminder: Bool { flagOn && enabled && !automaticUpdates }
    }

    // MARK: - State

    /// What the app keeps between launches, for the build that ran last.
    public struct State: Equatable, Sendable {
        /// `CFBundleVersion` of the build that ran last.
        public var buildSeen: String?
        /// When that build first ran.
        public var buildFirstRun: Date?
        /// The build that already showed its toast.
        public var toastShownForBuild: String?
        /// The build whose row the person clicked.
        public var rowHiddenForBuild: String?

        public init(
            buildSeen: String? = nil,
            buildFirstRun: Date? = nil,
            toastShownForBuild: String? = nil,
            rowHiddenForBuild: String? = nil
        ) {
            self.buildSeen = buildSeen
            self.buildFirstRun = buildFirstRun
            self.toastShownForBuild = toastShownForBuild
            self.rowHiddenForBuild = rowHiddenForBuild
        }

        static let buildSeenKey = "updateReminder.buildSeen"
        static let buildFirstRunKey = "updateReminder.buildFirstRun"
        static let toastShownKey = "updateReminder.toastShownForBuild"
        static let rowHiddenKey = "updateReminder.rowHiddenForBuild"

        public init(defaults: UserDefaults) {
            self.init(
                buildSeen: defaults.string(forKey: Self.buildSeenKey),
                buildFirstRun: defaults.object(forKey: Self.buildFirstRunKey) as? Date,
                toastShownForBuild: defaults.string(forKey: Self.toastShownKey),
                rowHiddenForBuild: defaults.string(forKey: Self.rowHiddenKey)
            )
        }

        /// A mark that is nil removes its key, so no stale value stays.
        public func save(to defaults: UserDefaults) {
            func put(_ value: Any?, _ key: String) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            put(buildSeen, Self.buildSeenKey)
            put(buildFirstRun, Self.buildFirstRunKey)
            put(toastShownForBuild, Self.toastShownKey)
            put(rowHiddenForBuild, Self.rowHiddenKey)
        }
    }

    public enum Display: Equatable, Sendable {
        case nothing
        /// The menu row shows. No toast now.
        case row
        /// The menu row shows, and the toast shows once, now.
        case toastAndRow

        public var showsRow: Bool { self != .nothing }
        public var showsToast: Bool { self == .toastAndRow }
    }

    public struct Result: Equatable, Sendable {
        /// The state to store. The toast mark is already set when `display`
        /// asks for the toast.
        public var state: State
        public var display: Display
    }

    // MARK: - Rules

    /// Decides what to show and what to store.
    ///
    /// - A new build restarts the clock and clears both marks, so a person who
    ///   just updated stays quiet for another week.
    /// - A clock set back restarts the wait. The marks stay.
    /// - The reminder needs the switches on, 7 days since the build first ran,
    ///   and at least one saved round.
    /// - The toast shows once per build, at an idle moment. The row shows from
    ///   day 7 until the person clicks it.
    ///
    /// `hasRounds` and `isIdle` run only when the earlier rules pass, because
    /// each one reads state the app would rather not read on every call.
    public static func evaluate(
        state: State,
        now: Date,
        build: String,
        gates: Gates,
        hasRounds: () -> Bool,
        isIdle: () -> Bool
    ) -> Result {
        var next = state
        if next.buildSeen != build {
            next = State(buildSeen: build, buildFirstRun: now)
        } else if let first = next.buildFirstRun {
            if first > now { next.buildFirstRun = now }
        } else {
            next.buildFirstRun = now
        }

        guard gates.allowsReminder,
              let first = next.buildFirstRun,
              now.timeIntervalSince(first) >= waitSeconds,
              next.rowHiddenForBuild != build,
              hasRounds()
        else { return Result(state: next, display: .nothing) }

        if next.toastShownForBuild != build, isIdle() {
            next.toastShownForBuild = build
            return Result(state: next, display: .toastAndRow)
        }
        return Result(state: next, display: .row)
    }

    /// The person clicked the row. It hides, and so does the toast, for this
    /// build.
    public static func hidingRow(_ state: State, build: String) -> State {
        var next = state
        next.rowHiddenForBuild = build
        return next
    }
}
