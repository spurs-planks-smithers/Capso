// Packages/FeedbackKit/Sources/FeedbackKit/SessionName.swift
import Foundation

/// The first line of a pasted prompt: `Session Name: <name>` (#198, Drew,
/// 2026-10-31). Agent tools name a session from the first message, and every
/// prompt used to start with the same tag, so a user with several rounds saw
/// one name many times.
///
/// The name is the Recent Rounds title (`RoundTitle`): the reviewer's own
/// words, 50 characters at most. When the reviewer wrote no words it is a date
/// and time label, so two rounds never share a name. Window titles and OCR
/// text never feed it. It makes no network call.
public enum SessionName {
    public static let label = "Session Name: "

    /// A round prompt, and a round zip README.
    public static func line(for round: FeedbackRound, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        label + name(title: RoundTitle.title(for: round), date: round.startedAt, timeZone: timeZone, locale: locale)
    }

    /// A capture prompt. A selection prompt and a selection zip README pass
    /// their first capture, in capture-time order. A capture has no round, so
    /// the date label is the capture's own time.
    public static func line(for capture: FeedbackCapture, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        label + name(title: RoundTitle.title(for: capture), date: capture.capturedAt, timeZone: timeZone, locale: locale)
    }

    private static func name(title: String?, date: Date, timeZone: TimeZone, locale: Locale) -> String {
        // `safe` can lengthen a title (it splits emoji joined by a zero-width
        // joiner), so the 50 character limit applies again after it.
        if let title = title.map(safe).map(RoundTitle.shortened), !title.isEmpty {
            return title
        }
        return FeedbackLibrary.dateLabel(date, timeZone: timeZone, locale: locale)
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
