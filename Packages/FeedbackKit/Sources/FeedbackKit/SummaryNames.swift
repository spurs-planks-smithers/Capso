// Packages/FeedbackKit/Sources/FeedbackKit/SummaryNames.swift
import Foundation

/// Names that Apple's on-device model wrote for the `<name>` part of the
/// session name line (#200, Drew, 2026-10-31). The model call lives in the app
/// target. This type holds only plain values, so FeedbackKit stays Foundation
/// only: the text the model reads, the key of a finished name, the clean-up of
/// a reply, and the file that keeps the names.
///
/// A name is stored under a key (`basis`) made from the instruction text and the
/// reviewer's words. A
/// prompt asks for the name of its own captures, so the same key serves a
/// round, a capture, and a selection, and a name never goes stale: when a note
/// changes or a capture joins the round, the key changes and the old name is
/// simply not found. Screen text (OCR text, window titles) never feeds the
/// input, so the model reads only what the reviewer wrote.
///
/// The names live in one file beside the rounds, not in `feedback.json`. A
/// round field would miss a selection, which spans rounds, would need a
/// staleness check of its own, and would be dropped without a word whenever
/// an older copy of the app rewrote the round. Decision:
/// `docs/decisions/2026-10-31-session-summary-name.md`.
public struct SummaryNames: Equatable, Sendable {
    /// No names. A prompt built with it is as it was before #200.
    public static let none = SummaryNames()

    /// The instruction for the on-device model. Tuned on 47 local rounds
    /// (2026-10-31). The words "screen" and "app" in an earlier text came back
    /// as generic names ("Screen control"), so this text bans them. A vague
    /// note set gets NONE, which `cleaned` turns into no name, so the prompt
    /// keeps the reviewer's own words.
    public static let instruction = """
    You name a work session from a reviewer's notes. \
    The notes arrive in groups, one group per image. \
    Name the subject of all the work in one noun phrase of two to six words. \
    Keep the specific names the notes use for the page, the control, the label, or the feature, \
    and put the most important one first. \
    Never use the generic words app, screen, screenshot, image, review, feedback, notes, changes, update, or issues. \
    When the groups cover different areas, name the two main areas. \
    When the notes are too short or too vague to name a subject, reply NONE. \
    Reply with the name only. No quotes, no period, no label.
    """

    /// Part of every key: a hash of the instruction. A new instruction gives
    /// new keys, so names written under the old text are not found.
    public static let revision = fnvHex(instruction)

    /// The names that the file keeps, newest last. The oldest go first.
    static let maxEntries = 1000

    /// Longest single answer, and longest input, in characters. The on-device
    /// model reads about 4,000 tokens in all, instruction and reply included.
    static let maxAnswerLength = 400
    static let maxInputLength = 4000

    /// Fewer words than this name nothing ("Bigger"), so no request is made.
    static let minimumWords = 3

    /// The file name, inside the rounds folder. A dot name, like
    /// `.active.json`, so a folder listing never mistakes it for a round.
    public static let fileName = ".summary-names.json"

    /// The longest reply that can pass for a name, in words.
    static let maxReplyWords = 10

    struct Entry: Codable, Equatable, Sendable {
        var basis: String
        var name: String
    }

    private struct FileContents: Codable {
        var version: Int
        var entries: [Entry]
    }

    private static let fileVersion = 1

    private(set) var entries: [Entry]

    public init() {
        entries = []
    }

    public var count: Int { entries.count }

    // MARK: - What the model reads

    /// The reviewer's words, one group per capture that has any: the badge
    /// instructions in badge order, then the capture note. Captures run in
    /// capture-time order, so a round, a zip, and a selection that hold the
    /// same captures give the same groups.
    public static func groups(of captures: [FeedbackCapture]) -> [[String]] {
        let ordered = captures.sorted { lhs, rhs in
            lhs.capturedAt == rhs.capturedAt ? lhs.index < rhs.index : lhs.capturedAt < rhs.capturedAt
        }
        return ordered.compactMap { capture in
            let instructions = FeedbackItems.split(capture).items.compactMap { $0.badge.instruction }
            let answers = (instructions + [capture.note].compactMap { $0 })
                .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
                .filter { !$0.isEmpty }
                .map { RoundTitle.shortened($0, limit: maxAnswerLength) }
            return answers.isEmpty ? nil : answers
        }
    }

    /// The text the model reads: one dash line per answer, a blank line
    /// between captures. Nil when the words add up to fewer than three, so
    /// the caller keeps the cut name. A long round loses its last answers.
    public static func input(of captures: [FeedbackCapture]) -> String? {
        let groups = groups(of: captures)
        let words = groups.joined().reduce(0) { $0 + $1.split(separator: " ").count }
        guard words >= minimumWords else { return nil }
        var text = ""
        for group in groups {
            let block = group.map { "- \($0)" }.joined(separator: "\n")
            let next = text.isEmpty ? block : text + "\n\n" + block
            if next.count > maxInputLength {
                // A first group that is too long by itself still goes in, cut.
                if text.isEmpty { text = String(next.prefix(maxInputLength)) }
                break
            }
            text = next
        }
        return text
    }

    // MARK: - Keys and lookup

    /// The key of an input: 64-bit FNV-1a over the revision and the input, as
    /// 16 hex digits. The hash is stable across launches, which `Hasher` is
    /// not. A clash would show a wrong name on a prompt and nothing worse.
    public static func basis(ofInput input: String) -> String {
        fnvHex("r\(revision)\n\(input)")
    }

    private static func fnvHex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// The key for these captures, or nil when they have too few words.
    public static func basis(of captures: [FeedbackCapture]) -> String? {
        input(of: captures).map(basis(ofInput:))
    }

    /// The stored name for these captures, as the model wrote it. Callers
    /// clean it again before it reaches a prompt (`SessionName`).
    public func name(for captures: [FeedbackCapture]) -> String? {
        guard let basis = Self.basis(of: captures) else { return nil }
        return entries.last { $0.basis == basis }?.name
    }

    /// True when a name is stored under the key.
    public func contains(basis: String) -> Bool {
        entries.contains { $0.basis == basis }
    }

    /// Stores a name under the key of its input, newest last.
    public mutating func set(_ name: String, forInput input: String) {
        let basis = Self.basis(ofInput: input)
        entries.removeAll { $0.basis == basis }
        entries.append(Entry(basis: basis, name: name))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    // MARK: - A model reply as a name

    private static let replyPrefixes = ["session name:", "session:", "name:", "title:"]

    /// The reply that the instruction allows when the notes are too short or
    /// too vague to name (compared in lowercase, after the trim).
    private static let noNameReplies: Set<String> = ["none", "n/a", "no name", "unknown", "untitled"]

    /// Replies that refuse or explain instead of naming.
    private static let refusalStarts = ["i'm sorry", "i am sorry", "sorry,", "sorry.", "sorry!", "i can't", "i cannot", "i can’t", "as an ai", "i'm unable", "i am unable", "unfortunately,"]

    /// The reply as one clean name, or nil when it cannot pass for a name.
    /// A reply may carry quotes, a closing period, a label, or Markdown marks.
    /// The result is one line, 50 characters at most, with no `<`, `>`, or
    /// backtick (`SessionName.safe`).
    public static func cleaned(_ reply: String) -> String? {
        guard var line = reply.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        let lower = line.lowercased()
        if refusalStarts.contains(where: { lower.hasPrefix($0) }) { return nil }
        for prefix in replyPrefixes where lower.hasPrefix(prefix) {
            line = String(line.dropFirst(prefix.count))
            break
        }
        let marks = CharacterSet(charactersIn: " \t\"'`*_#-.,;:!?\u{201C}\u{201D}\u{2018}\u{2019}\u{00AB}\u{00BB}")
        line = line.trimmingCharacters(in: marks)
        line = SessionName.safe(line).trimmingCharacters(in: marks)
        guard let first = line.first, !noNameReplies.contains(line.lowercased()), line.split(separator: " ").count <= maxReplyWords else { return nil }
        line = first.uppercased() + line.dropFirst()
        return RoundTitle.shortened(line)
    }

    // MARK: - The file

    /// The names in the file, or none when it is missing, unreadable, or
    /// written by a newer version of the format. A bad file never blocks a copy.
    public static func load(from url: URL) -> SummaryNames {
        var names = SummaryNames()
        guard let data = try? Data(contentsOf: url),
              let contents = try? JSONDecoder().decode(FileContents.self, from: data),
              contents.version == fileVersion
        else { return names }
        names.entries = Array(contents.entries.suffix(maxEntries))
        return names
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(FileContents(version: Self.fileVersion, entries: entries)).write(to: url, options: .atomic)
    }
}
