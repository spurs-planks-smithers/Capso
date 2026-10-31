// Packages/FeedbackKit/Sources/FeedbackKit/RoundTitle.swift
import Foundation

/// A short label for a round, cut from the reviewer's own words with plain
/// code: no model and no network (Drew, 2026-10-28, #164). The Recent menu
/// shows it in place of the date. Screen text (window titles, OCR text) never
/// feeds it, so the label holds only what the reviewer wrote.
public enum RoundTitle {
    /// Longest title in characters, the ellipsis included.
    public static let maxLength = 50

    /// The reviewer's first instruction in capture order, else the first
    /// capture note. Nil when the round holds no reviewer words, so the caller
    /// keeps the date as the row title.
    ///
    /// An answer of fewer than three words ("Bigger") names little. The first
    /// answer of three words or more wins. When none has three words, the
    /// first usable answer wins.
    public static func title(for round: FeedbackRound) -> String? {
        title(forCaptures: round.captures)
    }

    /// The same label for one capture: its own words only. A capture prompt
    /// has no round, so its session name comes from here (#198).
    public static func title(for capture: FeedbackCapture) -> String? {
        title(forCaptures: [capture])
    }

    private static func title(forCaptures captures: [FeedbackCapture]) -> String? {
        let instructions = captures.flatMap { FeedbackItems.split($0).items.compactMap { $0.badge.instruction } }
        let notes = captures.compactMap(\.note)
        let titles = (instructions + notes).compactMap(clean)
        return titles.first { wordCount($0) >= 3 } ?? titles.first
    }

    /// Lead-in words that say nothing about the subject. Longer phrases come
    /// before the phrases they contain ("make sure to" before "make sure").
    private static let leadIns = [
        "please", "pls", "can you", "could you", "would you", "will you",
        "i want you to", "i want to", "i would like to", "i'd like to",
        "we need to", "we should", "you should", "need to",
        "make sure to", "make sure", "also", "and", "so", "ok", "okay", "then", "now",
    ]

    /// One answer as a title, or nil when nothing is left.
    private static func clean(_ answer: String) -> String? {
        var text = answer
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        text = stripLeadIns(text)
        text = firstClause(text)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?-"))
        guard let first = text.first else { return nil }
        text = first.uppercased() + text.dropFirst()
        return shortened(text)
    }

    private static func stripLeadIns(_ text: String) -> String {
        var text = text
        var removed = true
        while removed {
            removed = false
            for lead in leadIns {
                if text.caseInsensitiveCompare(lead) == .orderedSame {
                    text = ""
                    removed = true
                    break
                }
                let prefix = lead + " "
                if let range = text.range(of: prefix, options: [.anchored, .caseInsensitive]) {
                    text.removeSubrange(range)
                    removed = true
                    break
                }
            }
        }
        return text
    }

    /// The text up to the first sentence end: a period, bang, question mark,
    /// semicolon, or colon followed by a space or the end. "$19.99" stays whole.
    private static func firstClause(_ text: String) -> String {
        let marks: Set<Character> = [".", "!", "?", ";", ":"]
        var index = text.startIndex
        while index < text.endIndex {
            if marks.contains(text[index]) {
                let next = text.index(after: index)
                if next == text.endIndex || text[next] == " " {
                    return String(text[..<index])
                }
            }
            index = text.index(after: index)
        }
        return text
    }

    /// At most `maxLength` characters, cut at a word end when one sits in the
    /// back half, with an ellipsis.
    static func shortened(_ text: String) -> String {
        guard text.count > maxLength else { return text }
        var cut = String(text.prefix(maxLength - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= maxLength / 2 {
            cut = String(cut[..<space])
        }
        cut = cut.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?-"))
        return cut + "\u{2026}"
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(separator: " ").count
    }
}
