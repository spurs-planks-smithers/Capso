// Packages/FeedbackKit/Sources/FeedbackKit/CaptureSearch.swift
import Foundation

/// Fork: the search of the Find Capture window (#125, Drew, 2026-11-08).
///
/// A capture matches when every word of the query appears in at least one of
/// its fields: the app name, the window title, each mark's instruction, the
/// general note, the round name, and the capture name. OCR text never feeds a
/// field, so text on the screen cannot make a capture match. The match is a
/// substring match that ignores case and diacritics, so "cafe" finds "Café".
/// Results come newest first. Two results with the same date keep a fixed
/// order by their tie-break key.
public enum CaptureSearch {
    /// The text one capture can match, folded once when it is made.
    public struct Fields: Equatable, Sendable {
        /// Folded, non-empty field texts.
        public let texts: [String]

        public init(
            appName: String?,
            windowTitle: String?,
            marks: [FeedbackMark],
            note: String?,
            roundName: String?,
            captureName: String?
        ) {
            let raw = [appName, windowTitle] + marks.map(\.instruction) + [note, roundName, captureName]
            texts = raw.compactMap { $0 }.map(CaptureSearch.fold).filter { !$0.isEmpty }
        }

        /// The fields of a round capture. `ocrText` of the capture and of its
        /// marks stays out.
        public init(capture: FeedbackCapture, roundName: String?, captureName: String?) {
            self.init(
                appName: capture.sourceApp,
                windowTitle: capture.windowTitle,
                marks: capture.marks,
                note: capture.note,
                roundName: roundName,
                captureName: captureName
            )
        }
    }

    /// One searchable value with its date and its tie-break key.
    public struct Entry<Value> {
        public var value: Value
        public var date: Date
        /// Orders entries with the same date, smallest first.
        public var tieBreak: String
        public var fields: Fields

        public init(value: Value, date: Date, tieBreak: String, fields: Fields) {
            self.value = value
            self.date = date
            self.tieBreak = tieBreak
            self.fields = fields
        }
    }

    /// The folded words of a query. White space splits the words. Punctuation
    /// at the start or end of a word goes, so "logo," finds "logo". A word with
    /// nothing left is dropped. So a blank query, a query of punctuation only,
    /// and a query of characters that fold to nothing all have no words, and
    /// they return every capture, as an empty query does. Punctuation inside a
    /// word stays and must match as typed ("main.swift").
    public static func words(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace)
            // White space can stay when a combining mark joins it to its
            // character, so it is trimmed after the fold as well.
            .map { fold(String($0)).trimmingCharacters(in: Self.edgeCharacters) }
            .filter { !$0.isEmpty }
    }

    /// True when every word appears in at least one field. An empty word
    /// list matches everything.
    public static func matches(_ fields: Fields, words: [String]) -> Bool {
        words.allSatisfy { word in fields.texts.contains { $0.contains(word) } }
    }

    /// The values that match `query`, newest first. An empty or blank query
    /// returns every value.
    public static func results<Value>(_ entries: [Entry<Value>], query: String) -> [Value] {
        let words = words(in: query)
        return entries
            .filter { matches($0.fields, words: words) }
            .sorted { lhs, rhs in
                lhs.date != rhs.date ? lhs.date > rhs.date : lhs.tieBreak < rhs.tieBreak
            }
            .map(\.value)
    }

    private static let edgeCharacters = CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)

    /// Lowercase with no diacritics, so "Café" and "CAFE" compare equal.
    /// Invisible characters (zero-width and other default-ignorable
    /// characters) go too. So does a combining mark that the diacritic fold
    /// leaves, such as one with no letter before it. The query and the fields
    /// fold the same way, so a match never depends on these characters.
    static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: folded.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark: false
            default: !scalar.properties.isDefaultIgnorableCodePoint
            }
        })
        return String(scalars)
    }
}

extension CaptureSearch.Entry: Sendable where Value: Sendable {}
extension CaptureSearch.Entry: Equatable where Value: Equatable {}
