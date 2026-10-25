// Packages/FeedbackKit/Sources/FeedbackKit/OneBreathSplitter.swift
import Foundation

/// Splits one answer into a part for each circle the reviewer names.
///
/// A reviewer can give notes for several circles in one text, for example a
/// dictation like `1. Make the title brighter.\n2. Remove the line under it.`
/// The splitter finds circle mentions and cuts the answer at each one. It never
/// changes the reviewer's words: every part is an exact substring, and the
/// parts joined in order equal the answer.
///
/// A mention counts only at a part start: the start of the answer, the start
/// of a line, or after a sentence end. A number inside a sentence ("page 3",
/// "3.5 seconds", "10:30") is never a mention.
public enum OneBreathSplitter {
    public enum Strength: String, Sendable, Equatable {
        /// A digit list item at a line start, or a keyword form like "Circle 2".
        case strong
        /// A digit list item after a sentence end, or a spoken form like "Two,".
        case medium
    }

    public struct Mention: Equatable, Sendable {
        public var circle: Int
        public var strength: Strength
        /// The mention token, for example "2." or "Circle two,".
        public var range: Range<String.Index>
    }

    public struct Part: Equatable, Sendable {
        /// Nil for the lead part: text before the first mention.
        public var circle: Int?
        public var mention: Mention?
        public var range: Range<String.Index>
        /// The exact substring, trailing spaces and line breaks included.
        public var text: String
        /// Correction cues found in the part, lowercased, in order, for example ["no,"].
        public var correctionCues: [String]
    }

    public struct Result: Equatable, Sendable {
        /// Every mention found, in order, even when the answer is not one-breath.
        public var mentions: [Mention]
        /// Empty unless `isOneBreath`.
        public var parts: [Part]
        /// Mentions of two or more different circles.
        public var isOneBreath: Bool
        /// The first mention names circle 1.
        public var startsAtOne: Bool
        /// The mentioned circles equal the capture's circles.
        public var coversAllCircles: Bool
    }

    /// Finds the circle mentions in an answer and, when two or more different
    /// circles are named, splits the answer into parts.
    public static func split(_ answer: String, circles: Set<Int>) -> Result {
        let mentions = findMentions(in: answer, circles: circles)
        let mentioned = Set(mentions.map(\.circle))
        let isOneBreath = mentioned.count >= 2
        return Result(
            mentions: mentions,
            parts: isOneBreath ? makeParts(in: answer, mentions: mentions) : [],
            isOneBreath: isOneBreath,
            startsAtOne: mentions.first?.circle == 1,
            coversAllCircles: !mentioned.isEmpty && mentioned == circles
        )
    }

    /// Splits text into clauses for a self-correction question. A clause ends
    /// after a comma or semicolon, and a new clause starts before a cue word.
    /// The clauses joined in order equal the text.
    public static func clauses(in text: String) -> [String] {
        var boundaries: Set<String.Index> = []

        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if (text[index] == "," || text[index] == ";"), next < text.endIndex {
                boundaries.insert(next)
            }
            index = next
        }

        // The space before a cue word stays with the cue's clause.
        for cue in cueMatches(in: text) {
            var boundary = cue.range.lowerBound
            while boundary > text.startIndex {
                let before = text.index(before: boundary)
                guard text[before].isWhitespace else { break }
                boundary = before
            }
            if boundary > text.startIndex {
                boundaries.insert(boundary)
            }
        }

        var clauses: [String] = []
        var clauseStart = text.startIndex
        for boundary in boundaries.sorted() {
            clauses.append(String(text[clauseStart..<boundary]))
            clauseStart = boundary
        }
        if clauseStart < text.endIndex {
            clauses.append(String(text[clauseStart...]))
        }
        return clauses
    }

    // MARK: - Mentions

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
    ]
    private static let keywords: Set<String> = ["circle", "number", "item", "badge"]
    private static let sentenceEnds: Set<Character> = [".", "!", "?", ";", ":"]
    private static let digitListMarks: Set<Character> = [".", ")", ":", ","]
    private static let wordMarks: Set<Character> = [",", ":", "."]
    private static let keywordMarks: Set<Character> = [",", ":", ".", ")"]

    private struct PartStart {
        var index: String.Index
        var isLineStart: Bool
    }

    private static func findMentions(in text: String, circles: Set<Int>) -> [Mention] {
        var mentions: [Mention] = []
        var previousEnd = text.startIndex
        for start in partStarts(in: text) where start.index >= previousEnd {
            guard let mention = mention(in: text, at: start), circles.contains(mention.circle) else { continue }
            mentions.append(mention)
            previousEnd = mention.range.upperBound
        }
        return mentions
    }

    /// Lists every place a mention can start, in text order.
    private static func partStarts(in text: String) -> [PartStart] {
        var starts = [PartStart(index: skipSpaces(in: text, from: text.startIndex), isLineStart: true)]
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character.isNewline {
                starts.append(PartStart(index: skipSpaces(in: text, from: next), isLineStart: true))
            } else if sentenceEnds.contains(character), next < text.endIndex, text[next].isWhitespace {
                // A line break after the sentence end makes a line start instead.
                let after = skipSpaces(in: text, from: next)
                if after < text.endIndex, !text[after].isNewline {
                    starts.append(PartStart(index: after, isLineStart: false))
                }
            }
            index = next
        }
        return starts.sorted { $0.index < $1.index }
    }

    private static func mention(in text: String, at start: PartStart) -> Mention? {
        if let (circle, end) = keywordForm(in: text, at: start.index) {
            return Mention(circle: circle, strength: .strong, range: start.index..<end)
        }
        if let (circle, end) = digitListForm(in: text, at: start.index) {
            return Mention(circle: circle, strength: start.isLineStart ? .strong : .medium, range: start.index..<end)
        }
        if let (circle, end) = wordForm(in: text, at: start.index) {
            return Mention(circle: circle, strength: .medium, range: start.index..<end)
        }
        return nil
    }

    /// "Circle 2," or "Item three:". The mark after the number is optional.
    private static func keywordForm(in text: String, at index: String.Index) -> (circle: Int, end: String.Index)? {
        let wordEnd = run(in: text, from: index) { $0.isLetter }
        guard keywords.contains(text[index..<wordEnd].lowercased()) else { return nil }
        let numberStart = skipSpaces(in: text, from: wordEnd)
        guard numberStart > wordEnd, let (circle, numberEnd) = number(in: text, at: numberStart) else { return nil }
        let end = optionalMark(in: text, at: numberEnd, marks: keywordMarks)
        return isTokenEnd(in: text, at: end) ? (circle, end) : nil
    }

    /// "2." or "2)" or "2:" or "2,".
    private static func digitListForm(in text: String, at index: String.Index) -> (circle: Int, end: String.Index)? {
        guard index < text.endIndex, text[index].isASCIIDigit,
              let (circle, numberEnd) = number(in: text, at: index),
              numberEnd < text.endIndex, digitListMarks.contains(text[numberEnd])
        else { return nil }
        let end = text.index(after: numberEnd)
        return isTokenEnd(in: text, at: end) ? (circle, end) : nil
    }

    /// "Two," or "Three:" or "Four.".
    private static func wordForm(in text: String, at index: String.Index) -> (circle: Int, end: String.Index)? {
        guard index < text.endIndex, !text[index].isASCIIDigit,
              let (circle, numberEnd) = number(in: text, at: index),
              numberEnd < text.endIndex, wordMarks.contains(text[numberEnd])
        else { return nil }
        let end = text.index(after: numberEnd)
        return isTokenEnd(in: text, at: end) ? (circle, end) : nil
    }

    /// Reads a digit number from 1 to 99 or a number word from "one" to "twenty".
    private static func number(in text: String, at index: String.Index) -> (value: Int, end: String.Index)? {
        guard index < text.endIndex else { return nil }
        if text[index].isASCIIDigit {
            let end = run(in: text, from: index) { $0.isASCIIDigit }
            guard text.distance(from: index, to: end) <= 2,
                  let value = Int(text[index..<end]), (1...99).contains(value)
            else { return nil }
            return (value, end)
        }
        let end = run(in: text, from: index) { $0.isLetter }
        guard let value = numberWords[text[index..<end].lowercased()] else { return nil }
        return (value, end)
    }

    // MARK: - Parts

    private static func makeParts(in answer: String, mentions: [Mention]) -> [Part] {
        var parts: [Part] = []
        var partStart = answer.startIndex

        // Text before the first mention is a lead part. Spaces alone join the first part.
        if let first = mentions.first, answer[..<first.range.lowerBound].contains(where: { !$0.isWhitespace }) {
            parts.append(makePart(in: answer, range: answer.startIndex..<first.range.lowerBound, mention: nil))
            partStart = first.range.lowerBound
        }

        for (offset, mention) in mentions.enumerated() {
            let end = offset + 1 < mentions.count ? mentions[offset + 1].range.lowerBound : answer.endIndex
            parts.append(makePart(in: answer, range: partStart..<end, mention: mention))
            partStart = end
        }
        return parts
    }

    private static func makePart(in answer: String, range: Range<String.Index>, mention: Mention?) -> Part {
        let text = String(answer[range])
        return Part(
            circle: mention?.circle,
            mention: mention,
            range: range,
            text: text,
            correctionCues: cueMatches(in: text).map(\.cue)
        )
    }

    // MARK: - Correction cues

    private static let cuePhrases = ["no,", "actually", "i mean", "wait", "scratch that", "sorry"]

    /// Finds each cue as a whole word or phrase, ignoring case, in text order.
    private static func cueMatches(in text: String) -> [(cue: String, range: Range<String.Index>)] {
        var matches: [(cue: String, range: Range<String.Index>)] = []
        var index = text.startIndex
        var previous: Character?
        while index < text.endIndex {
            if previous?.isWordCharacter != true {
                for phrase in cuePhrases {
                    if let end = matchEnd(of: phrase, in: text, at: index) {
                        matches.append((phrase, index..<end))
                        break
                    }
                }
            }
            previous = text[index]
            index = text.index(after: index)
        }
        return matches
    }

    /// The end of `phrase` if it sits at `index` as a whole word, ignoring case.
    private static func matchEnd(of phrase: String, in text: String, at index: String.Index) -> String.Index? {
        var end = index
        for expected in phrase {
            guard end < text.endIndex, text[end].lowercased() == String(expected) else { return nil }
            end = text.index(after: end)
        }
        if let last = phrase.last, last.isLetter, end < text.endIndex, text[end].isWordCharacter {
            return nil
        }
        return end
    }

    // MARK: - Scanning helpers

    /// The first index at or after `index` where `matches` fails.
    private static func run(in text: String, from index: String.Index, while matches: (Character) -> Bool) -> String.Index {
        var end = index
        while end < text.endIndex, matches(text[end]) {
            end = text.index(after: end)
        }
        return end
    }

    /// Skips spaces and tabs. A line break stops the skip.
    private static func skipSpaces(in text: String, from index: String.Index) -> String.Index {
        run(in: text, from: index) { $0.isWhitespace && !$0.isNewline }
    }

    private static func optionalMark(in text: String, at index: String.Index, marks: Set<Character>) -> String.Index {
        guard index < text.endIndex, marks.contains(text[index]) else { return index }
        return text.index(after: index)
    }

    private static func isTokenEnd(in text: String, at index: String.Index) -> Bool {
        index == text.endIndex || text[index].isWhitespace
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isWordCharacter: Bool { isLetter || isNumber }
}
