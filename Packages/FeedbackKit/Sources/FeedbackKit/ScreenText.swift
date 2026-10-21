// Packages/FeedbackKit/Sources/FeedbackKit/ScreenText.swift
import Foundation

/// Cleans text that comes from the screen (OCR, window titles, app names) or
/// from another app (a Shortcuts input). Any web page or document can supply
/// it, so the agent must not mistake it for part of the bundle.
///
/// It removes invisible format characters (zero-width, bidirectional, and
/// Unicode tag characters), removes bundle-tag lookalikes until none can be
/// rebuilt, and caps the length in Unicode scalars.
enum ScreenText {
    /// A field only needs to be long enough to search the code for.
    static let maxFieldLength = 200
    /// The OCR text of a whole capture.
    static let maxBlockLength = 5000
    static let maxNameLength = 100

    static func clean(_ text: String, singleLine: Bool, maxScalars: Int) -> String {
        let visible = text.unicodeScalars.filter { $0.properties.generalCategory != .format }
        var text = String(String.UnicodeScalarView(visible))
        if singleLine {
            text = text.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
        }

        var previous: String
        repeat {
            previous = text
            text = text.replacingOccurrences(
                of: #"</?\s*feedback_bundle[^>]*>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        } while text != previous

        if text.unicodeScalars.count > maxScalars {
            text = String(String.UnicodeScalarView(text.unicodeScalars.prefix(maxScalars))) + "..."
        }
        return text
    }

    /// `clean` for an optional field. Text that is empty after cleaning becomes nil.
    static func field(_ text: String?, singleLine: Bool = true, maxScalars: Int = maxFieldLength) -> String? {
        guard let text else { return nil }
        let cleaned = clean(text, singleLine: singleLine, maxScalars: maxScalars)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : cleaned
    }
}
