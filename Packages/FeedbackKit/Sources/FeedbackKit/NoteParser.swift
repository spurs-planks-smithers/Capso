// Packages/FeedbackKit/Sources/FeedbackKit/NoteParser.swift
import Foundation

/// Splits a capture note into the capture note and per-badge instructions.
///
/// The note is split into lines, and each line into parts at semicolons, so
/// a one-line note can hold several instructions (`1: fix price; 2: bold`).
/// A part that starts with a badge number and a colon becomes that badge's
/// instruction. Every other part stays in the capture note as typed.
public enum NoteParser {
    public struct Result: Equatable, Sendable {
        public var note: String?
        public var instructions: [Int: String]

        public init(note: String?, instructions: [Int: String]) {
            self.note = note
            self.instructions = instructions
        }
    }

    public static func parse(_ text: String, badges: Set<Int>) -> Result {
        var noteLines: [String] = []
        var instructions: [Int: String] = [:]

        for line in text.components(separatedBy: .newlines) {
            var kept: [Substring] = []
            for part in line.split(separator: ";", omittingEmptySubsequences: false) {
                if let (badge, instruction) = instruction(in: part), badges.contains(badge) {
                    instructions[badge] = instructions[badge].map { "\($0); \(instruction)" } ?? instruction
                } else {
                    kept.append(part)
                }
            }
            let remainder = kept.joined(separator: ";").trimmingCharacters(in: .whitespaces)
            if !remainder.isEmpty {
                noteLines.append(remainder)
            }
        }

        let note = noteLines.joined(separator: "\n")
        return Result(note: note.isEmpty ? nil : note, instructions: instructions)
    }

    private static func instruction(in part: Substring) -> (badge: Int, text: String)? {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let number = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty, number.allSatisfy(\.isASCIIDigit), let badge = Int(number) else { return nil }
        let text = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (badge, text)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
