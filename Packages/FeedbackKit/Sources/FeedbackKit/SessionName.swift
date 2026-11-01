// Packages/FeedbackKit/Sources/FeedbackKit/SessionName.swift
import Foundation

/// The first line of a pasted prompt: `Session Name: <app> - <name>` (#198,
/// Drew, 2026-10-31). Agent tools name a session from the first message, and
/// every prompt used to start with the same tag, so a user with several rounds
/// saw one name many times.
///
/// The name is a summary of all the captures that the on-device model wrote
/// (`SummaryNames`, #200), when one is stored under the key of these captures'
/// words. Otherwise it is the Recent Rounds title (`RoundTitle`): the
/// reviewer's own words, 50 characters at most. When the reviewer wrote no
/// words it is a date and time label, so two rounds never share a name. A
/// summary goes through the same clean-up and the same 50 character limit. The
/// app comes first: the
/// source app of the captures, the same name that the Recent Rounds subtitle
/// shows ("Google Chrome"). Window titles and OCR text never feed the line,
/// because a web page sets them. It makes no network call.
public enum SessionName {
    public static let label = "Session Name: "

    /// Between the app and the name.
    static let appSeparator = " - "

    /// Longest app part in characters, the ellipsis included.
    static let maxAppLength = 40

    /// A round prompt, and a round zip README.
    public static func line(for round: FeedbackRound, summaries: SummaryNames = .none, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        line(captures: round.captures, date: round.startedAt, summaries: summaries, timeZone: timeZone, locale: locale)
    }

    /// A capture prompt. A capture has no round, so the date label is the
    /// capture's own time.
    public static func line(for capture: FeedbackCapture, summaries: SummaryNames = .none, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        line(captures: [capture], date: capture.capturedAt, summaries: summaries, timeZone: timeZone, locale: locale)
    }

    /// A selection prompt and a selection zip README. They pass their captures
    /// in capture-time order, and the date label is the first capture's time.
    /// Nil when no capture is selected.
    public static func line(forSelection captures: [FeedbackCapture], summaries: SummaryNames = .none, timeZone: TimeZone = .current, locale: Locale = .current) -> String? {
        guard let first = captures.first else { return nil }
        return line(captures: captures, date: first.capturedAt, summaries: summaries, timeZone: timeZone, locale: locale)
    }

    private static func line(captures: [FeedbackCapture], date: Date, summaries: SummaryNames, timeZone: TimeZone, locale: Locale) -> String {
        let name = name(captures: captures, date: date, summaries: summaries, timeZone: timeZone, locale: locale)
        guard let app = app(of: captures) else { return label + name }
        return label + app + appSeparator + name
    }

    private static func name(captures: [FeedbackCapture], date: Date, summaries: SummaryNames, timeZone: TimeZone, locale: Locale) -> String {
        // A stored summary is cleaned again here, so a hand-edited names file
        // cannot forge the bundle tag. `safe` can lengthen a title (it splits
        // emoji joined by a zero-width joiner), so the 50 character limit
        // applies again after it.
        if let summary = summaries.name(for: captures).map(safe).map({ RoundTitle.shortened($0) }), !summary.isEmpty {
            return summary
        }
        if let title = RoundTitle.title(forCaptures: captures).map(safe).map({ RoundTitle.shortened($0) }), !title.isEmpty {
            return title
        }
        return FeedbackLibrary.dateLabel(date, timeZone: timeZone, locale: locale)
    }

    /// The source apps, as the Recent Rounds subtitle picks them: distinct, in
    /// capture order, two at most, then " +N" for the rest (no comma before
    /// it). The whole part is 40 characters at most. Nil when no capture
    /// has an app name. An app name comes from the app's bundle, not from page
    /// content, but it gets the same cleaning as the name.
    static func app(of captures: [FeedbackCapture]) -> String? {
        var apps: [String] = []
        for app in captures.compactMap(\.sourceApp).map(safe) where !app.isEmpty && !apps.contains(app) {
            apps.append(app)
        }
        guard !apps.isEmpty else { return nil }
        // The "+N" stays whole: only the names are cut to fit.
        let more = apps.count > 2 ? " +\(apps.count - 2)" : ""
        return RoundTitle.shortened(apps.prefix(2).joined(separator: ", "), limit: maxAppLength - more.count) + more
    }

    /// One line with no `<`, `>`, or backtick, so reviewer text cannot forge
    /// the bundle tag or close a code span. Each of those characters and each
    /// run of white space becomes one space. Control and format characters
    /// (zero-width and tag characters among them) and other invisible
    /// characters (the Hangul filler among them) go.
    static func safe(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace || scalar == "<" || scalar == ">" || scalar == "`" {
                scalars.append(" ")
                continue
            }
            if scalar.properties.isDefaultIgnorableCodePoint {
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .surrogate, .privateUse, .unassigned:
                continue
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }
}
