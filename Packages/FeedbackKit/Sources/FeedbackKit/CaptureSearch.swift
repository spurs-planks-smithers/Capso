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

    /// The folded words of a query. Empty for an empty or blank query.
    public static func words(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }.filter { !$0.isEmpty }
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

    /// Lowercase with no diacritics, so "Café" and "CAFE" compare equal.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

extension CaptureSearch.Entry: Sendable where Value: Sendable {}
extension CaptureSearch.Entry: Equatable where Value: Equatable {}
