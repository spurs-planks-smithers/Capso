// Packages/JevKit/Sources/JevKit/Jobs/PromptLanesJob.swift
import FeedbackKit
import Foundation

/// What the lanes job decides about one rated item.
public struct PromptLanesRating: Equatable, Sendable {
    /// Lane A: an exact edit, small, and not a blocker. Every other rated
    /// item is lane B.
    public var laneA: Bool
    public var severity: PromptLanes.Severity
    public var size: PromptLanes.Size
    /// The probability that every change in the note is exact.
    public var exact: Double

    public init(laneA: Bool, severity: PromptLanes.Severity, size: PromptLanes.Size, exact: Double) {
        self.laneA = laneA
        self.severity = severity
        self.size = size
        self.exact = exact
    }
}

/// The rule that turns Jev's three answers for one item into a rating. Pure
/// code: the same answers always give the same rating.
///
/// The threshold is a start value. The accuracy test sets the final one, and
/// a change to it or to a question raises the job's `version`.
public enum PromptLanesRule {
    /// Lane A needs `exact` at least this likely.
    public static let exactMinimum = 0.8

    /// The most likely level of a Score. A tie takes the higher level, so a
    /// doubt never lowers severity and never shrinks a size. Nil means not
    /// checked: the answer is missing, it does not have `levels` levels, or a
    /// number is not finite or is outside 0 to 1.
    public static func level(_ answer: JevScoreAnswer?, levels: Int) -> Int? {
        guard let answer, answer.probabilities.count == levels, levels > 0,
              answer.probabilities.allSatisfy({ $0.isFinite && (0...1).contains($0) })
        else { return nil }

        var top = 0
        for (index, probability) in answer.probabilities.enumerated() where probability >= answer.probabilities[top] {
            top = index
        }
        return top
    }

    /// Nil means not rated: an answer is missing or out of range.
    public static func rate(severity: JevScoreAnswer?, size: JevScoreAnswer?, kind: JevChoiceAnswer?) -> PromptLanesRating? {
        guard let severityLevel = level(severity, levels: PromptLanes.Severity.allCases.count),
              let sizeLevel = level(size, levels: PromptLanes.Size.allCases.count),
              let severityValue = PromptLanes.Severity(rawValue: severityLevel),
              let sizeValue = PromptLanes.Size(rawValue: sizeLevel),
              let exact = kind?.probabilities["exact"], exact.isFinite, (0...1).contains(exact)
        else { return nil }

        let small = sizeValue == .oneLine || sizeValue == .oneFile
        let laneA = exact >= exactMinimum && small && severityValue != .blocker
        return PromptLanesRating(laneA: laneA, severity: severityValue, size: sizeValue, exact: exact)
    }
}

/// Lanes and priority (ideas 11 and 12, issue #69, flag `promptLanes`):
/// rates each item's severity and size, and sorts mechanical edits from
/// judgment calls, so the round prompt can order and split its items.
///
/// Code finds an empty note with no model. One request per capture asks Jev
/// three questions about each filled note. The request holds reviewer text
/// only: no window title, OCR text, app name, file name, or image. The job
/// returns no refined lines and no files. Its summary feeds the round plan,
/// which is built from the whole round. The job returns the same output in
/// shadow and on. See docs/superpowers/specs/2026-10-24-prompt-lanes-design.md.
public struct PromptLanesJob: JevJob {
    public let id = "promptLanes"
    public let flag = FeatureFlag.promptLanes
    public let requires: JevDataKinds = []
    /// Version 2 (2026-10-24, accuracy test #73): removal examples in the
    /// `exact` option, and examples that no longer copy test notes.
    public let version = 2

    public init() {}

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        let capture = context.capture
        let items = Self.items(in: capture)
        guard !items.isEmpty else { return .empty }

        let filled = items.filter { Self.isFilled($0.note) }
        var response: JevResponse?
        if !filled.isEmpty {
            response = try await context.jev.ask(Self.request(capture: capture, filled: filled))
        }

        var summary: [JevSummaryField] = []
        // The review writer adds the capture heading.
        var review: [String] = []
        for item in items {
            let id = Self.itemID(capture: capture.index, badge: item.badge)
            var reviewLine = "- \(id.text):"
            let value: JevSummaryValue
            if Self.isFilled(item.note) {
                let severity = response?.score("\(id.text).severity")
                let size = response?.score("\(id.text).size")
                let kind = response?.choice("\(id.text).kind")
                if let severity, let size, let rating = PromptLanesRule.rate(severity: severity, size: size, kind: kind) {
                    let lane: JevSummaryValue = rating.laneA ? "A" : "B"
                    value = .fields(["lane": lane, "severity": .number(Double(rating.severity.rawValue)), "size": .number(Double(rating.size.rawValue))])
                    reviewLine += " lane \(rating.laneA ? "A" : "B")."
                    reviewLine += " \(rating.severity.name) \(Self.twoDecimals(severity.probabilities[rating.severity.rawValue])),"
                    reviewLine += " \(rating.size.name) \(Self.twoDecimals(size.probabilities[rating.size.rawValue])),"
                    reviewLine += " exact \(Self.twoDecimals(rating.exact))."
                } else {
                    value = .fields(["lane": "notRated"])
                    reviewLine += " not rated."
                }
            } else {
                value = .fields(["lane": "askFirst"])
                reviewLine += " ask first."
            }
            reviewLine += " Note: \"\(item.note.split(whereSeparator: \.isNewline).joined(separator: " "))\""
            review.append(reviewLine)
            summary.append(JevSummaryField(key: id, value: value))
        }
        return JevJobOutput(summary: summary, review: review.joined(separator: "\n"))
    }

    /// Each distinct badge, in ascending order. A badge with several marks
    /// takes the first mark that has an instruction. `note` is the badge's
    /// instruction as stored, or empty when the badge has none.
    static func items(in capture: FeedbackCapture) -> [(badge: Int, note: String)] {
        capture.badgeNumbers.sorted().map { badge in
            let instruction = capture.marks.first { $0.badge == badge && $0.instruction != nil }?.instruction
            return (badge: badge, note: instruction ?? "")
        }
    }

    private static func isFilled(_ note: String) -> Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func itemID(capture: Int, badge: Int) -> JevCodeText {
        "\(capture).\(badge)"
    }

    /// The whole capture in one request: three questions for each filled
    /// item. Each question names its item's place in the state, `items[i]`.
    private static func request(capture: FeedbackCapture, filled: [(badge: Int, note: String)]) -> JevRequest {
        var entries: [JevValue] = []
        var questions: [(id: JevCodeText, question: JevQuestion)] = []
        for (index, item) in filled.enumerated() {
            let id = itemID(capture: capture.index, badge: item.badge)
            entries.append(.fields(["item": .code(id), "note": .reviewer(item.note)]))
            questions.append((
                id: "\(id).severity",
                question: .score(
                    "How serious is the problem that `items[\(index)].note` describes? `general_note` is context from the same reviewer. Words like \"this\" or \"here\" refer to the marked item.",
                    levels: [
                        "A small taste preference. The screen works and reads well without it. Example: \"maybe a slightly warmer gray\".",
                        "The change improves the look, the wording, or the layout. Nothing is broken. Example: \"add more space above this heading\".",
                        "Something is broken, inconsistent, or cut off, but the screen still works. Example: \"the last word of this button label is cut off\".",
                        "The feature fails, shows wrong data, or stops the user from finishing a task. Example: \"saving this form loses what I typed\".",
                    ]
                )
            ))
            questions.append((
                id: "\(id).size",
                question: .score(
                    "How much code will a developer likely change to do what `items[\(index)].note` asks?",
                    levels: [
                        "One value, word, or sentence in one place. Example: \"rename this button to Save\".",
                        "A few related edits in one place, such as one component or one page. Example: \"line up the labels in this form\".",
                        "Edits in a few files or places. Example: \"show this setting in the menu and remember it after a restart\".",
                        "A change across the app, the repository, or every page. Example: \"use the new brand color on every screen\".",
                    ]
                )
            ))
            questions.append((
                id: "\(id).kind",
                question: .choice(
                    "Can a developer do every change in `items[\(index)].note` with no design or product choice?",
                    options: [
                        "exact": "Every change is exact: new text given in full, a named color, a size or spacing number, or one named thing to remove. The note may also say why. Examples: \"drop the subtitle, it repeats the title\", \"rename this button to Save\", \"make this 20% wider\".",
                        "judgment": "At least one change needs a choice: make something clearer, better, or consistent, pick a layout, research, explain, or answer a question. A note that names no concrete change, such as \"fix this\", is judgment too.",
                    ]
                )
            ))
        }
        let state: JevValue = .fields([
            "general_note": .reviewer(capture.note ?? ""),
            "items": .array(entries),
        ])
        return JevRequest(state: state, questions: questions)
    }

    private static func twoDecimals(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
