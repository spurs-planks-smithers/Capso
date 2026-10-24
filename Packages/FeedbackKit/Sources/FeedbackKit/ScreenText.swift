// Packages/FeedbackKit/Sources/FeedbackKit/ScreenText.swift
import Foundation

/// Cleans text that comes from the screen (OCR, window titles, app names) or
/// from another app (a Shortcuts input). Any web page or document can supply
/// it, so the agent must not mistake it for part of the bundle.
///
/// It removes invisible format characters (zero-width, bidirectional, and
/// Unicode tag characters), removes wrapper-tag lookalikes (any opening or
/// closing tag whose name starts with `feedback_`, such as bundle, capture,
/// and selection) until none can be rebuilt, and caps the length in Unicode
/// scalars.
public enum ScreenText {
    /// A field only needs to be long enough to search the code for.
    public static let maxFieldLength = 200
    /// The OCR text of a whole capture.
    public static let maxBlockLength = 5000
    static let maxNameLength = 100

    public static func clean(_ text: String, singleLine: Bool, maxScalars: Int) -> String {
        let visible = text.unicodeScalars.filter { $0.properties.generalCategory != .format }
        var text = String(String.UnicodeScalarView(visible))
        if singleLine {
            text = text.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
        }

        var previous: String
        repeat {
            previous = text
            text = text.replacingOccurrences(
                of: #"</?\s*feedback_[^>]*>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        } while text != previous

        if text.unicodeScalars.count > maxScalars {
            text = String(String.UnicodeScalarView(text.unicodeScalars.prefix(maxScalars))) + "..."
        }
        return text
    }

    /// Wraps screen text in double quotes. Straight and lookalike double quotes
    /// inside it become single quotes, so the text cannot close the quote.
    public static func quoted(_ text: String) -> String {
        var inner = text
        for mark in ["\"", "\u{201C}", "\u{201D}", "\u{FF02}"] {
            inner = inner.replacingOccurrences(of: mark, with: "'")
        }
        return "\"\(inner)\""
    }

    /// `clean` for an optional field. Text that is empty after cleaning becomes nil.
    public static func field(_ text: String?, singleLine: Bool = true, maxScalars: Int = maxFieldLength) -> String? {
        guard let text else { return nil }
        let cleaned = clean(text, singleLine: singleLine, maxScalars: maxScalars)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cleaned
    }
}
