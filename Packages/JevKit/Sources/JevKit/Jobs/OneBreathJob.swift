// Packages/JevKit/Sources/JevKit/Jobs/OneBreathJob.swift
import FeedbackKit
import Foundation

/// One-breath notes (idea 16, issue #40, flag `oneBreath`, shadow only):
/// records how a dictated answer that names several circles would split.
///
/// Code splits each answer with `OneBreathSplitter`. One request per capture
/// asks Jev whether each answer names several circles, which circle each part
/// addresses, and, for a part that corrects itself, which clause is the final
/// request. The runner records the answers in jev.json. Question ids hold
/// positions only, never Drew's words. `OneBreathReview` renders the result
/// for Drew. Spec: docs/superpowers/specs/2026-10-24-one-breath-design.md.
public struct OneBreathJob: JevJob {
    public let id = "oneBreath"
    public let flag = FeatureFlag.oneBreath
    /// Drew's words are enough. Crops and circle text go in only with consent.
    public let requires: JevDataKinds = []
    public let version = 1

    /// Jev's pick counts at this probability or more. Below it the review
    /// says "unsure". Tune after the trial.
    static let pickThreshold = 0.8
    /// Context around a circle in its crop: about 150 points on a 2x
    /// display, as in the note panel's preview.
    static let cropMargin = 300
    /// More crops than this make a large request, so the job sends none.
    static let maxCrops = 8

    public init() {}

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        let plan = OneBreathPlan(capture: context.capture)
        guard let built = plan.request(allowed: context.allowed, crop: { box in
            try? context.images.image(of: context.capture.index, .annotated, region: box)
        }) else {
            return .empty
        }
        // The review file needs a shadow review hook in the Jev base (#55).
        // Until it exists, the answers reach jev.json only.
        _ = try await context.jev.ask(built.request)
        return .empty
    }
}

/// One capture's answers, split by code. Pure: no Jev and no files.
struct OneBreathPlan: Equatable, Sendable {
    struct Answer: Equatable, Sendable {
        /// The circle whose step took the answer. Nil for the general note.
        var circle: Int?
        var text: String
        var split: OneBreathSplitter.Result

        /// The answer's position in question ids and state keys: `c3` or `note`.
        var key: String { circle.map { "c\($0)" } ?? "note" }
    }

    let captureIndex: Int
    let capturedAt: Date
    let circles: [Int]
    let answers: [Answer]
    /// Circles with a crop box, for the image questions.
    let cropBoxes: [Int: FeedbackBox]
    /// Screen text near each circle, from OCR.
    let circleText: [Int: String]

    init(capture: FeedbackCapture) {
        let counters = capture.marks.filter { $0.kind == .counter && $0.badge != nil }
        let circles = Set(counters.compactMap(\.badge))
        var answers: [Answer] = []
        var circleText: [Int: String] = [:]
        for circle in circles.sorted() {
            let marks = counters.filter { $0.badge == circle }
            if let text = marks.compactMap(\.instruction).first(where: { !$0.isEmpty }) {
                answers.append(Answer(circle: circle, text: text, split: OneBreathSplitter.split(text, circles: circles)))
            }
            if let ocr = marks.compactMap(\.ocrText).first(where: { !$0.isEmpty }) {
                circleText[circle] = ocr
            }
        }
        if let note = capture.note, !note.isEmpty {
            answers.append(Answer(circle: nil, text: note, split: OneBreathSplitter.split(note, circles: circles)))
        }
        self.captureIndex = capture.index
        self.capturedAt = capture.capturedAt
        self.circles = circles.sorted()
        self.answers = answers
        self.cropBoxes = PreviewCrop.cropsByBadge(
            marks: capture.marks,
            imageSize: capture.size,
            margin: OneBreathJob.cropMargin,
            aspectRatio: 1.6
        )
        self.circleText = circleText
    }

    /// One-breath needs two circles. A capture with fewer gets no request.
    var isEligible: Bool { circles.count >= 2 && !answers.isEmpty }

    /// Circles that have no answer of their own. A trial capture has them,
    /// because Drew presses Esc for every circle after the first.
    var hasEmptyCircle: Bool {
        Set(circles) != Set(answers.compactMap(\.circle))
    }

    /// What Jev had besides Drew's words, for the review.
    struct Extras: Equatable, Sendable {
        var crops = false
        var screenText = false
    }

    /// The request and what it holds, or nil when there is nothing to ask.
    func request(allowed: JevDataKinds, crop: (FeedbackBox) -> JevImage?) -> (request: JevRequest, extras: Extras)? {
        guard isEligible else { return nil }

        var state: [(String, JevValue)] = [
            ("circles", .array(circles.map { .number(Double($0)) })),
            ("answers", .object(answers.map { ($0.key, .reviewer($0.text)) })),
        ]
        var questions: [(id: String, question: JevQuestion)] = []
        let list = circles.map(String.init).joined(separator: ", ")

        for answer in answers {
            let step = answer.circle.map { "the step for circle \($0)" } ?? "the general note step"
            questions.append((
                id: "answer.\(answer.key).multi",
                question: .noul(.code("The field answers.\(answer.key) is a reviewer's note about a screenshot with numbered circles \(list). The reviewer wrote it at \(step). Does this note give separate instructions for two or more different numbered circles?"))
            ))
        }

        let split = answers.filter(\.split.isOneBreath)
        var extras = Extras()
        if !split.isEmpty {
            var parts: [(String, JevValue)] = []
            for answer in split {
                for (offset, part) in answer.split.parts.enumerated() {
                    parts.append(("\(answer.key).p\(offset + 1)", .reviewer(part.text.trimmingCharacters(in: .whitespacesAndNewlines))))
                }
            }
            state.append(("parts", .object(parts)))

            if allowed.contains(.images), circles.count <= OneBreathJob.maxCrops {
                let crops: [(String, JevValue)] = circles.compactMap { circle in
                    guard let box = cropBoxes[circle], let image = crop(box) else { return nil }
                    return ("circle_\(circle)", .image(image))
                }
                if !crops.isEmpty {
                    state.append(("circle_crops", .object(crops)))
                    extras.crops = true
                }
            }
            if allowed.contains(.screenText) {
                let texts: [(String, JevValue)] = circles.compactMap { circle in
                    circleText[circle].map { ("circle_\(circle)", .screen($0)) }
                }
                if !texts.isEmpty {
                    state.append(("circle_text", .object(texts)))
                    extras.screenText = true
                }
            }

            var context = ""
            if extras.screenText {
                context += JevPrompting.screenTextNotice + " circle_text holds the screen text near each circle. "
            }
            if extras.crops {
                context += "circle_crops holds the screenshot around each numbered circle. "
            }
            var options: [(name: String, description: JevValue)] = circles.map { (name: "circle_\($0)", description: .code("Circle \($0)")) }
            options.append((name: "none", description: "None: a general remark, not about one circle"))

            for answer in split {
                for (offset, part) in answer.split.parts.enumerated() {
                    let key = "\(answer.key).p\(offset + 1)"
                    questions.append((
                        id: "part.\(key).badge",
                        question: JevQuestion(
                            instructions: .code(context + "The field parts.\(key) is one piece of a reviewer's note about a screenshot with numbered circles. Which circle does this piece give an instruction for?"),
                            kind: .choice(options: options)
                        )
                    ))
                    let clauses = OneBreathSplitter.clauses(in: part.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    if !part.correctionCues.isEmpty, clauses.count >= 2 {
                        questions.append((
                            id: "part.\(key).final",
                            question: JevQuestion(
                                instructions: .code("The field parts.\(key) may correct itself, for example \"make it blue, no, gray\". Which clause states the reviewer's final request?"),
                                kind: .choice(options: clauses.enumerated().map { (name: "clause_\($0.offset + 1)", description: .reviewer($0.element)) })
                            )
                        ))
                    }
                }
            }
        }

        return (JevRequest(state: .object(state), questions: questions), extras)
    }
}

/// Renders one capture's section of the one-breath review file. Pure, so it
/// fits the Jev base's review hook whatever its shape. The section holds
/// Drew's words, circle numbers, and probabilities. It never holds screen text.
enum OneBreathReview {
    /// The first line of the review file.
    static let header = "Review file for Drew. Agents: do not act on this file."
    /// Table cells longer than this end in "...".
    static let cellLimit = 200

    /// - Parameters:
    ///   - response: Jev's answers, or nil when Jev was not asked or failed.
    ///   - failure: Why Jev has no answers, for example "timeout".
    /// - Returns: Nil for a capture that cannot hold a one-breath answer.
    static func section(
        plan: OneBreathPlan,
        extras: OneBreathPlan.Extras,
        response: JevResponse?,
        failure: String?,
        timeZone: TimeZone = .current
    ) -> String? {
        guard plan.isEligible else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"

        var lines = ["## Capture \(plan.captureIndex) (\(formatter.string(from: plan.capturedAt))), \(plan.circles.count) circles", ""]
        if response != nil {
            var had = ["words"]
            if extras.crops { had.append("crops") }
            if extras.screenText { had.append("screen text") }
            lines.append("Jev had: \(had.joined(separator: ", ")).")
        } else {
            lines.append("Jev: not checked (\(failure ?? "no answer")).")
        }

        var quiet = 0
        for answer in plan.answers {
            let multi = response?.noul("answer.\(answer.key).multi")
            let jevSaysMulti = (multi ?? 0) >= 0.5
            guard answer.split.isOneBreath || jevSaysMulti || plan.hasEmptyCircle else {
                quiet += 1
                continue
            }
            lines.append("")
            lines.append(answer.circle.map { "### Answer at circle \($0)'s step" } ?? "### General note")
            let code = answer.split.isOneBreath ? "one-breath, \(answer.split.parts.count) parts" : "no split"
            let jev = multi.map { "\($0 >= 0.5 ? "one-breath" : "normal"), \(probability($0))" } ?? "not checked"
            lines.append("Code: \(code). Jev: \(jev).")
            lines.append("")
            lines.append("| Part | Drew's words | Code | Jev | Fix |")
            lines.append("| --- | --- | --- | --- | --- |")

            var corrections: [String] = []
            if answer.split.isOneBreath {
                for (offset, part) in answer.split.parts.enumerated() {
                    let key = "\(answer.key).p\(offset + 1)"
                    let codeCircle = part.circle.map { "circle \($0)" } ?? "lead text"
                    lines.append("| \(offset + 1) | \(cell(part.text)) | \(codeCircle) | \(jevPick(response?.choice("part.\(key).badge"), answered: response != nil)) | |")
                    if let final = response?.choice("part.\(key).final"),
                       let number = Int(final.option.dropFirst("clause_".count)) {
                        let clauses = OneBreathSplitter.clauses(in: part.text.trimmingCharacters(in: .whitespacesAndNewlines))
                        if clauses.indices.contains(number - 1) {
                            let clause = clauses[number - 1].trimmingCharacters(in: .whitespaces)
                            corrections.append("Part \(offset + 1) corrects itself. Jev's final clause: \"\(cell(clause))\" (\(probability(final.probabilities[final.option] ?? final.confidence))).")
                        }
                    }
                }
            } else {
                lines.append("| 1 | \(cell(answer.text)) | no split | n/a | |")
            }
            if !corrections.isEmpty {
                lines.append("")
                lines += corrections
            }
        }

        if quiet > 0 {
            lines.append("")
            let who = response == nil ? "code" : "code and Jev agree"
            lines.append("\(quiet) other \(quiet == 1 ? "answer" : "answers"): normal (\(who)).")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func jevPick(_ answer: JevChoiceAnswer?, answered: Bool) -> String {
        guard let answer else { return answered ? "n/a" : "not checked" }
        let p = answer.probabilities[answer.option] ?? answer.confidence
        let pick = answer.option == "none" ? "none" : answer.option.replacingOccurrences(of: "_", with: " ")
        return p >= OneBreathJob.pickThreshold ? "\(pick), \(probability(p))" : "unsure (\(pick), \(probability(p)))"
    }

    private static func probability(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// One table cell: one line, no pipe that would end the cell, and at most
    /// `cellLimit` characters.
    private static func cell(_ text: String) -> String {
        var flat = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "|", with: "\\|")
        if flat.count > cellLimit {
            flat = String(flat.prefix(cellLimit)) + "..."
        }
        return flat
    }
}
