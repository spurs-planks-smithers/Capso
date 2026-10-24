// Packages/JevKit/Sources/JevKit/Jobs/NoteCoachJob.swift
import FeedbackKit
import Foundation

/// What the note coach says about one item's note.
public enum NoteCoachLabel: String, Sendable, CaseIterable {
    /// The note is missing or holds only white space. Code decides this.
    case empty
    /// The note names no problem, no change, and no question.
    case vague
    /// Jev leans vague (level 0 is the most likely level), but the answers do
    /// not pass the vague rule. It gets no line. Shadow review shows these
    /// borderline notes so the thresholds can be tuned.
    case unsure
    /// The note names a problem with the item, but not the change.
    case partial
    /// The note asks for information, advice, or text, and names no change.
    case question
    /// The note names the change.
    case clear

    /// The label as code text, for the summary in jev.json.
    public var code: JevCodeText {
        switch self {
        case .empty: "empty"
        case .vague: "vague"
        case .unsure: "unsure"
        case .partial: "partial"
        case .question: "question"
        case .clear: "clear"
        }
    }
}

/// The rule that turns Jev's four answers for one item into a label. Pure
/// code: the same answers always give the same label.
///
/// The accuracy test (issue #62) set the thresholds on 2026-10-24 for the
/// pinned model `JevEndpoint.model`. A new model needs a new test run.
/// - Vague uses `clarity` and `asks_answer` only. Jev reads "fix this" as
///   naming a change, so `names_change` would let a vague note through.
/// - A question may score high on `names_change` when it asks for text to
///   write ("tell me what to put here"). Real change requests scored 0.94
///   or more, so the cut sits at 0.8.
/// - `reports_problem` keeps a bug report ("why is this not available?")
///   from getting the question line, so the agent can fix it.
public enum NoteCoachRule {
    /// Vague needs level 0 of `clarity` at least this likely...
    public static let vagueLevelMinimum = 0.7
    /// ...and `asks_answer` below this.
    public static let vagueAnswerMaximum = 0.5
    /// A question needs `asks_answer` at least this...
    public static let questionAnswerMinimum = 0.7
    /// ...`names_change` below this...
    public static let questionChangeMaximum = 0.8
    /// ...and `reports_problem` below this.
    public static let questionProblemMaximum = 0.5

    /// Nil means not checked: an answer is missing, `clarity` does not have
    /// three levels, or a number is not finite or is outside 0 to 1.
    public static func label(clarity: JevScoreAnswer?, namesChange: Double?, asksAnswer: Double?, reportsProblem: Double?) -> NoteCoachLabel? {
        guard let clarity, let namesChange, let asksAnswer, let reportsProblem, clarity.probabilities.count == 3,
              (clarity.probabilities + [namesChange, asksAnswer, reportsProblem]).allSatisfy({ $0.isFinite && (0...1).contains($0) })
        else { return nil }

        let levels = clarity.probabilities
        if levels[0] >= vagueLevelMinimum, asksAnswer < vagueAnswerMaximum {
            return .vague
        }
        if asksAnswer >= questionAnswerMinimum, namesChange < questionChangeMaximum, reportsProblem < questionProblemMaximum {
            return .question
        }
        if levels[0] > levels[1], levels[0] > levels[2] {
            return .unsure
        }
        return levels[1] > levels[0] && levels[1] > levels[2] ? .partial : .clear
    }

    /// The refined-file line for a label. Unsure, partial, and clear notes
    /// get none.
    public static func line(for label: NoteCoachLabel) -> JevCodeText? {
        switch label {
        case .vague: "Ask the reviewer first: the note names no change."
        case .question: "Answer this item. Change no code."
        case .empty: "Ask the reviewer first: the item has no note."
        case .unsure, .partial, .clear: nil
        }
    }
}

/// Note coach (idea 1, issue #37, flag `noteCoach`): labels each item's note
/// as empty, vague, partial, question, or clear.
///
/// Code finds an empty note with no model. One request per capture asks Jev
/// four questions about each filled note. The request holds reviewer text
/// only: no window title, OCR text, app name, file name, or image. The job
/// returns the same output in shadow and on. The runner writes the lines in
/// on only. See docs/superpowers/specs/2026-10-24-note-coach-design.md.
public struct NoteCoachJob: JevJob {
    public let id = "noteCoach"
    public let flag = FeatureFlag.noteCoach
    public let requires: JevDataKinds = []
    public let version = 2

    public init() {}

    /// One numbered badge. `note` is the badge's instruction as stored, or
    /// empty when the badge has none.
    private struct Item {
        var badge: Int
        var note: String

        var isFilled: Bool {
            !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        let capture = context.capture
        let items = Self.items(in: capture)
        guard !items.isEmpty else { return .empty }

        let filled = items.filter(\.isFilled)
        var response: JevResponse?
        if !filled.isEmpty {
            response = try await context.jev.ask(Self.request(capture: capture, filled: filled))
        }

        var lines: [JevRefinedLine] = []
        var summary: [JevSummaryField] = []
        var review = ["### Capture \(capture.index)"]
        for item in items {
            let id = Self.itemID(capture: capture.index, badge: item.badge)
            let label: NoteCoachLabel?
            var reviewLine = "- \(id.text):"
            if item.isFilled {
                let clarity = response?.score("\(id.text).clarity")
                let namesChange = response?.noul("\(id.text).names_change")
                let asksAnswer = response?.noul("\(id.text).asks_answer")
                let reportsProblem = response?.noul("\(id.text).reports_problem")
                label = NoteCoachRule.label(clarity: clarity, namesChange: namesChange, asksAnswer: asksAnswer, reportsProblem: reportsProblem)
                reviewLine += " \(label?.rawValue ?? "not checked")."
                reviewLine += " Level 0 \(Self.twoDecimals(clarity?.probabilities.first)), change \(Self.twoDecimals(namesChange)), answer \(Self.twoDecimals(asksAnswer)), problem \(Self.twoDecimals(reportsProblem))."
            } else {
                label = .empty
                reviewLine += " empty."
            }
            reviewLine += " Note: \"\(item.note.split(whereSeparator: \.isNewline).joined(separator: " "))\""
            review.append(reviewLine)

            if let line = label.flatMap({ NoteCoachRule.line(for: $0) }) {
                lines.append(JevRefinedLine(scope: .item(badge: item.badge), label: line))
            }
            summary.append(JevSummaryField(key: id, value: label.map { JevSummaryValue.code($0.code) } ?? "not_checked"))
        }
        return JevJobOutput(lines: lines, summary: summary, review: review.joined(separator: "\n"))
    }

    /// Each distinct badge, in ascending order. A badge with several marks
    /// takes the first mark that has an instruction.
    private static func items(in capture: FeedbackCapture) -> [Item] {
        capture.badgeNumbers.sorted().map { badge in
            let instruction = capture.marks.first { $0.badge == badge && $0.instruction != nil }?.instruction
            return Item(badge: badge, note: instruction ?? "")
        }
    }

    private static func itemID(capture: Int, badge: Int) -> JevCodeText {
        "\(capture).\(badge)"
    }

    /// The whole capture in one request: four questions for each filled
    /// item. Each question names its item's place in the state, `items[i]`.
    private static func request(capture: FeedbackCapture, filled: [Item]) -> JevRequest {
        var entries: [JevValue] = []
        var questions: [(id: JevCodeText, question: JevQuestion)] = []
        for (index, item) in filled.enumerated() {
            let id = itemID(capture: capture.index, badge: item.badge)
            entries.append(.fields(["item": .code(id), "note": .reviewer(item.note)]))
            questions.append((
                id: "\(id).clarity",
                question: .score(
                    "How clearly does `items[\(index)].note` tell a developer what to do about the marked item? `general_note` is context from the same reviewer. Words like \"this\" or \"here\" refer to the marked item.",
                    levels: [
                        "The note names no problem, names no change, and asks no question. Examples: \"fix this\", \"hmm\", \"look at this\", \"asdf\".",
                        "The note names a problem with the item but not the change to make. Examples: \"this is cut off\", \"this number is wrong\".",
                        "The note names the change to make, or asks a clear question. Examples: \"make this 50% wider\", \"rename this to Invoice Detail\", \"what does this setting do?\".",
                    ]
                )
            ))
            questions.append((
                id: "\(id).names_change",
                question: .noul(
                    "Does `items[\(index)].note` ask for a change to the marked item?",
                    yes: "The note names something to add, remove, move, resize, rename, recolor, reword, or fix.",
                    no: "The note only describes, praises, or asks a question."
                )
            ))
            questions.append((
                id: "\(id).asks_answer",
                question: .noul(
                    "Does `items[\(index)].note` ask for information, an explanation, advice, or text to write?",
                    yes: "The reviewer wants an answer or a draft.",
                    no: "The reviewer wants only a change, or nothing."
                )
            ))
            questions.append((
                id: "\(id).reports_problem",
                question: .noul(
                    "Does `items[\(index)].note` report that something is broken, wrong, or not available?",
                    yes: "The note says something does not work, shows a wrong value, or is missing when it should be there.",
                    no: "The note only asks about something, or asks for a change, and says nothing is broken."
                )
            ))
        }
        let state: JevValue = .fields([
            "general_note": .reviewer(capture.note ?? ""),
            "items": .array(entries),
        ])
        return JevRequest(state: state, questions: questions)
    }

    private static func twoDecimals(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }
}
