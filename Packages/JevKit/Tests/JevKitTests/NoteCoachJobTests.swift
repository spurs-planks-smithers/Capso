import FeedbackKit
import Foundation
import Testing
@testable import JevKit

// Made-up notes only: the repository is public.

// MARK: - Fixtures

/// A capture with one counter mark per entry, plus a mark with no badge. The
/// window title, app name, file names, and OCR text all hold the word
/// "secret", so a test can prove none of them reach a request.
private func makeNoteCapture(index: Int = 3, notes: [(badge: Int, note: String?)], general: String? = "context words") -> FeedbackCapture {
    var marks = notes.map { entry in
        FeedbackMark(kind: .counter, badge: entry.badge, box: FeedbackBox(x1: 10, y1: 10, x2: 40, y2: 40), textOnImage: "Secret text", ocrText: "Secret mark OCR", instruction: entry.note)
    }
    marks.append(FeedbackMark(kind: .rectangle, box: FeedbackBox(x1: 5, y1: 5, x2: 90, y2: 90), instruction: "an unbadged mark has no item"))
    return FeedbackCapture(
        index: index,
        imageFile: "0900-secret-window.png",
        cleanImageFile: "0900-secret-window-clean.png",
        size: PixelSize(width: 800, height: 600),
        capturedAt: Date(timeIntervalSince1970: 1_792_000_000),
        sourceApp: "Secret App",
        windowTitle: "Secret Window",
        note: general,
        ocrText: "Secret OCR",
        marks: marks
    )
}

private let vague: (levels: [Double], change: Double, answer: Double) = ([0.9, 0.05, 0.05], 0.1, 0.1)
private let question: (levels: [Double], change: Double, answer: Double) = ([0.1, 0.2, 0.7], 0.1, 0.9)

/// The four answers for one item, as the client returns them. `reports_problem` is a no.
private func answers(_ item: String, _ shape: (levels: [Double], change: Double, answer: Double)) -> [String: JevAnswer] {
    let expected = shape.levels.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element }
    return [
        "\(item).clarity": .score(JevScoreAnswer(score: expected, confidence: 0.8, probabilities: shape.levels)),
        "\(item).names_change": .noul(shape.change),
        "\(item).asks_answer": .noul(shape.answer),
        "\(item).reports_problem": .noul(0.05),
    ]
}

private func response(_ parts: [String: JevAnswer]...) -> JevResponse {
    JevResponse(model: JevEndpoint.model, answers: parts.reduce(into: [:]) { $0.merge($1) { _, new in new } }, inputTokens: 0, outputTokens: 0)
}

/// The text of a code value. Other values give an empty string.
private func codeText(_ value: JevValue) -> String {
    if case .code(let code) = value { return code.text }
    return ""
}

/// A 200 body that answers one item's four questions, in the client's format.
private func noteCoachBody(item: String, levels: [Double], change: Double, answer: Double) -> String {
    let expected = levels.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element }
    let scale = levels.enumerated().map { #""\#($0.offset)":\#($0.element)"# }.joined(separator: ",")
    let clarityJSON = #""\#(item).clarity":{"type":"score","score":\#(expected),"confidence":0.9,"legend":{},"probabilities":{\#(scale)}}"#
    let changeJSON = #""\#(item).names_change":{"type":"noul","noul":\#(change)}"#
    let answerJSON = #""\#(item).asks_answer":{"type":"noul","noul":\#(answer)}"#
    let problemJSON = #""\#(item).reports_problem":{"type":"noul","noul":0.05}"#
    return #"{"model":"\#(JevEndpoint.model)","answers":{\#(clarityJSON),\#(changeJSON),\#(answerJSON),\#(problemJSON)},"usage":{"input_tokens":40,"output_tokens":3}}"#
}

// MARK: - The job

@Suite("Note coach: the job")
struct NoteCoachJobTests {
    @Test("One request holds each filled note and the general note, and nothing from the screen")
    func requestShape() async throws {
        let capture = makeNoteCapture(notes: [(3, "  what does this do?  "), (1, "make this bigger"), (2, nil)])
        let sent = RequestLog()
        _ = try await NoteCoachJob().run(makeContext(capture: capture, sent: sent))

        let requests = await sent.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.kinds == .reviewerText)
        #expect(request.images.isEmpty)
        #expect(!request.needsImagesHeader)
        #expect(request.questions.map(\.id.text) == ["3.1.clarity", "3.1.names_change", "3.1.asks_answer", "3.1.reports_problem", "3.3.clarity", "3.3.names_change", "3.3.asks_answer", "3.3.reports_problem"])

        // Each question names its own item's path in the state.
        for entry in request.questions {
            let path = entry.id.text.hasPrefix("3.1.") ? "`items[0].note`" : "`items[1].note`"
            #expect(codeText(entry.question.instructions).contains(path), "\(entry.id.text) names the wrong item")
        }

        // The state is exact: general note first, then the filled items in
        // badge order, with item 3's spaces kept.
        let body = String(decoding: try JevRequestEncoder.encode(request).body, as: UTF8.self)
        #expect(body.contains(#""state":{"general_note":"context words","items":[{"item":"3.1","note":"make this bigger"},{"item":"3.3","note":"  what does this do?  "}]},"questions""#))
        #expect(!body.lowercased().contains("secret"))
        #expect(!body.contains("unbadged"))
    }

    @Test("The questions use the agreed wording")
    func questionWording() async throws {
        let capture = makeNoteCapture(index: 1, notes: [(1, "make this bigger")])
        let sent = RequestLog()
        _ = try await NoteCoachJob().run(makeContext(capture: capture, sent: sent))
        let request = try #require(await sent.requests.first)
        #expect(request.questions.count == 4)

        let clarity = request.questions[0].question
        #expect(codeText(clarity.instructions) == #"How clearly does `items[0].note` tell a developer what to do about the marked item? `general_note` is context from the same reviewer. Words like "this" or "here" refer to the marked item."#)
        guard case .score(let levels) = clarity.kind else {
            Issue.record("clarity is not a Score")
            return
        }
        #expect(levels.map(codeText) == [
            #"The note names no problem, names no change, and asks no question. Examples: "fix this", "hmm", "look at this", "asdf"."#,
            #"The note names a problem with the item but not the change to make. Examples: "this is cut off", "this number is wrong"."#,
            #"The note names the change to make, or asks a clear question. Examples: "make this 50% wider", "rename this to Invoice Detail", "what does this setting do?"."#,
        ])

        let names = request.questions[1].question
        #expect(codeText(names.instructions) == "Does `items[0].note` ask for a change to the marked item?")
        guard case .noul(let namesYes, let namesNo) = names.kind else {
            Issue.record("names_change is not a Noul")
            return
        }
        #expect(namesYes.map(codeText) == "The note names something to add, remove, move, resize, rename, recolor, reword, or fix.")
        #expect(namesNo.map(codeText) == "The note only describes, praises, or asks a question.")

        let asks = request.questions[2].question
        #expect(codeText(asks.instructions) == "Does `items[0].note` ask for information, an explanation, advice, or text to write?")
        guard case .noul(let asksYes, let asksNo) = asks.kind else {
            Issue.record("asks_answer is not a Noul")
            return
        }
        #expect(asksYes.map(codeText) == "The reviewer wants an answer or a draft.")
        #expect(asksNo.map(codeText) == "The reviewer wants only a change, or nothing.")

        let problem = request.questions[3].question
        #expect(codeText(problem.instructions) == "Does `items[0].note` report that something is broken, wrong, or not available?")
        guard case .noul(let problemYes, let problemNo) = problem.kind else {
            Issue.record("reports_problem is not a Noul")
            return
        }
        #expect(problemYes.map(codeText) == "The note says something does not work, shows a wrong value, or is missing when it should be there.")
        #expect(problemNo.map(codeText) == "The note only asks about something, or asks for a change, and says nothing is broken.")
    }

    @Test("A badge with several marks uses the first note, and the general note is sent as stored")
    func sharedBadge() async throws {
        let capture = makeNoteCapture(notes: [(1, nil), (1, "first words"), (1, "second words")], general: nil)
        let sent = RequestLog()
        _ = try await NoteCoachJob().run(makeContext(capture: capture, sent: sent))
        let request = try #require(await sent.requests.first)
        #expect(request.questions.count == 4)
        let body = String(decoding: try JevRequestEncoder.encode(request).body, as: UTF8.self)
        #expect(body.contains(#""state":{"general_note":"","items":[{"item":"3.1","note":"first words"}]}"#))
    }

    @Test("When every note is empty, no request is sent, and each item gets the empty line")
    func allEmpty() async throws {
        let capture = makeNoteCapture(notes: [(1, nil), (2, "   "), (3, "\n")])
        let sent = RequestLog()
        let output = try await NoteCoachJob().run(makeContext(capture: capture, sent: sent))

        #expect(await sent.count == 0)
        #expect(output.lines == [1, 2, 3].map { JevRefinedLine(scope: .item(badge: $0), label: "Ask the reviewer first: the item has no note.") })
        #expect(output.summary == [1, 2, 3].map { JevSummaryField(key: "3.\($0)", value: "empty") })
        #expect(output.files.isEmpty)
        #expect(output.failure == nil)
        let review = try #require(output.review)
        #expect(review.hasPrefix("### Capture 3\n- 3.1: empty."))
    }

    @Test("A capture with no badges sends nothing and returns nothing")
    func noItems() async throws {
        let sent = RequestLog()
        let output = try await NoteCoachJob().run(makeContext(capture: makeNoteCapture(notes: []), sent: sent))
        #expect(output == .empty)
        #expect(await sent.count == 0)
    }

    @Test("Vague and question items get a line, empty items get the empty line, in badge order")
    func lines() async throws {
        let capture = makeNoteCapture(notes: [(1, "make this bigger"), (2, nil), (3, "what does this do?")])
        let reply = response(answers("3.1", vague), answers("3.3", question))
        let output = try await NoteCoachJob().run(makeContext(capture: capture, response: reply))

        #expect(output.lines == [
            JevRefinedLine(scope: .item(badge: 1), label: "Ask the reviewer first: the note names no change."),
            JevRefinedLine(scope: .item(badge: 2), label: "Ask the reviewer first: the item has no note."),
            JevRefinedLine(scope: .item(badge: 3), label: "Answer this item. Change no code."),
        ])
        #expect(output.summary == [
            JevSummaryField(key: "3.1", value: "vague"),
            JevSummaryField(key: "3.2", value: "empty"),
            JevSummaryField(key: "3.3", value: "question"),
        ])
        #expect(output.failure == nil)
    }

    @Test("Partial and clear items get no line")
    func partialAndClearGetNoLine() async throws {
        let capture = makeNoteCapture(notes: [(1, "this is cut off"), (2, "make this wider")])
        let partial = (levels: [0.1, 0.8, 0.1], change: 0.4, answer: 0.1)
        let clear = (levels: [0.05, 0.15, 0.8], change: 0.9, answer: 0.05)
        let output = try await NoteCoachJob().run(makeContext(capture: capture, response: response(answers("3.1", partial), answers("3.2", clear))))

        #expect(output.lines.isEmpty)
        #expect(output.summary == [JevSummaryField(key: "3.1", value: "partial"), JevSummaryField(key: "3.2", value: "clear")])
    }

    @Test("A missing answer gives that item no line and not_checked, and the other items keep theirs")
    func missingAnswer() async throws {
        let capture = makeNoteCapture(notes: [(1, "make this bigger"), (2, nil), (3, "what does this do?")])
        let output = try await NoteCoachJob().run(makeContext(capture: capture, response: response(answers("3.1", vague))))

        #expect(output.lines == [
            JevRefinedLine(scope: .item(badge: 1), label: "Ask the reviewer first: the note names no change."),
            JevRefinedLine(scope: .item(badge: 2), label: "Ask the reviewer first: the item has no note."),
        ])
        #expect(output.summary == [
            JevSummaryField(key: "3.1", value: "vague"),
            JevSummaryField(key: "3.2", value: "empty"),
            JevSummaryField(key: "3.3", value: "not_checked"),
        ])
        let review = try #require(output.review)
        #expect(review.contains(#"- 3.3: not checked. Level 0 n/a, change n/a, answer n/a, problem n/a. Note: "what does this do?""#))
    }

    @Test("An answer outside 0 to 1, or of the wrong type, makes only its item not checked")
    func badAnswer() async throws {
        let capture = makeNoteCapture(notes: [(1, "make this bigger"), (2, "what does this do?")])
        var outOfRange = answers("3.1", vague)
        outOfRange["3.1.asks_answer"] = .noul(1.2)
        var wrongType = answers("3.2", question)
        wrongType["3.2.clarity"] = .noul(0.5)
        let output = try await NoteCoachJob().run(makeContext(capture: capture, response: response(outOfRange, wrongType)))

        #expect(output.lines.isEmpty)
        #expect(output.summary == [JevSummaryField(key: "3.1", value: "not_checked"), JevSummaryField(key: "3.2", value: "not_checked")])
    }

    @Test("The review holds each note on one line, the label, and the numbers, and no screen text")
    func review() async throws {
        let capture = makeNoteCapture(notes: [(1, "fix this\nnow"), (2, nil), (3, "what does this do?")])
        let reply = response(answers("3.1", vague), answers("3.3", question))
        let output = try await NoteCoachJob().run(makeContext(capture: capture, response: reply))

        #expect(output.review == """
        ### Capture 3
        - 3.1: vague. Level 0 0.90, change 0.10, answer 0.10, problem 0.05. Note: "fix this now"
        - 3.2: empty. Note: ""
        - 3.3: question. Level 0 0.10, change 0.10, answer 0.90, problem 0.05. Note: "what does this do?"
        """)
        #expect(output.review?.lowercased().contains("secret") == false)
    }

    @Test("An error from the asker ends the job")
    func errorPropagates() async {
        var context = makeContext(capture: makeNoteCapture(notes: [(1, "make this bigger")]))
        context = JevJobContext(
            round: context.round, capture: context.capture, folderURL: context.folderURL, allowed: context.allowed,
            deadline: context.deadline, jev: JevAsker { _ in throw JevError(.timeout) }, images: context.images
        )
        await #expect(throws: JevError(.timeout)) {
            _ = try await NoteCoachJob().run(context)
        }
    }

    @Test("The job is registered at version 2, with no consent beyond reviewer text")
    func identity() {
        let job = NoteCoachJob()
        #expect(job.id == "noteCoach" && job.flag == .noteCoach)
        #expect(job.version == 2)
        #expect(job.requires.isEmpty)
    }
}

// MARK: - The rule

struct RuleCase: Sendable, CustomTestStringConvertible {
    var name: String
    var levels: [Double]
    var change: Double
    var answer: Double
    var problem = 0.05
    var expected: NoteCoachLabel

    var testDescription: String { name }
}

@Suite("Note coach: the rule")
struct NoteCoachRuleTests {
    static let cases: [RuleCase] = [
        RuleCase(name: "a clear vague note", levels: [0.9, 0.05, 0.05], change: 0.1, answer: 0.1, expected: .vague),
        RuleCase(name: "level 0 exactly 0.7 is vague", levels: [0.7, 0.2, 0.1], change: 0.0, answer: 0.0, expected: .vague),
        RuleCase(name: "level 0 just under 0.7 is unsure", levels: [0.69, 0.21, 0.1], change: 0.1, answer: 0.1, expected: .unsure),
        RuleCase(name: "fix this is vague even when names_change is high", levels: [0.95, 0.03, 0.02], change: 0.97, answer: 0.1, expected: .vague),
        RuleCase(name: "asks_answer exactly 0.5 is unsure, not vague", levels: [0.9, 0.05, 0.05], change: 0.1, answer: 0.5, expected: .unsure),
        RuleCase(name: "asks_answer just under 0.5 is vague", levels: [0.9, 0.05, 0.05], change: 0.1, answer: 0.49, expected: .vague),
        RuleCase(name: "level 0 on top with a high asks_answer is unsure", levels: [0.8, 0.1, 0.1], change: 0.1, answer: 0.6, expected: .unsure),
        RuleCase(name: "a clear question", levels: [0.1, 0.2, 0.7], change: 0.1, answer: 0.9, expected: .question),
        RuleCase(name: "asks_answer exactly 0.7 with names_change 0.79 is a question", levels: [0.2, 0.3, 0.5], change: 0.79, answer: 0.7, expected: .question),
        RuleCase(name: "a request for text to write is a question", levels: [0.01, 0.01, 0.98], change: 0.74, answer: 0.98, expected: .question),
        RuleCase(name: "asks_answer just under 0.7 is not a question", levels: [0.2, 0.3, 0.5], change: 0.1, answer: 0.69, expected: .clear),
        RuleCase(name: "names_change exactly 0.8 is not a question", levels: [0.1, 0.2, 0.7], change: 0.8, answer: 0.9, expected: .clear),
        RuleCase(name: "a bug report that asks why is not a question", levels: [0.0, 0.11, 0.89], change: 0.12, answer: 0.96, problem: 0.9, expected: .clear),
        RuleCase(name: "reports_problem exactly 0.5 is not a question", levels: [0.1, 0.2, 0.7], change: 0.1, answer: 0.9, problem: 0.5, expected: .clear),
        RuleCase(name: "reports_problem just under 0.5 is a question", levels: [0.1, 0.2, 0.7], change: 0.1, answer: 0.9, problem: 0.49, expected: .question),
        RuleCase(name: "a question that also names a change is clear", levels: [0.05, 0.15, 0.8], change: 0.95, answer: 0.9, expected: .clear),
        RuleCase(name: "level 1 on top is partial", levels: [0.2, 0.6, 0.2], change: 0.4, answer: 0.1, expected: .partial),
        RuleCase(name: "level 2 on top is clear", levels: [0.05, 0.15, 0.8], change: 0.9, answer: 0.05, expected: .clear),
        RuleCase(name: "level 0 tied with level 2 is clear", levels: [0.45, 0.1, 0.45], change: 0.5, answer: 0.1, expected: .clear),
    ]

    private static func score(_ levels: [Double]) -> JevScoreAnswer {
        JevScoreAnswer(score: 1, confidence: 0.9, probabilities: levels)
    }

    @Test("Each answer set maps to its label", arguments: NoteCoachRuleTests.cases)
    func label(_ test: RuleCase) {
        #expect(NoteCoachRule.label(clarity: Self.score(test.levels), namesChange: test.change, asksAnswer: test.answer, reportsProblem: test.problem) == test.expected)
    }

    @Test("A missing input means not checked")
    func missingInput() {
        let good = Self.score([0.9, 0.05, 0.05])
        #expect(NoteCoachRule.label(clarity: nil, namesChange: 0.1, asksAnswer: 0.1, reportsProblem: 0.1) == nil)
        #expect(NoteCoachRule.label(clarity: good, namesChange: nil, asksAnswer: 0.1, reportsProblem: 0.1) == nil)
        #expect(NoteCoachRule.label(clarity: good, namesChange: 0.1, asksAnswer: nil, reportsProblem: 0.1) == nil)
        #expect(NoteCoachRule.label(clarity: good, namesChange: 0.1, asksAnswer: 0.1, reportsProblem: nil) == nil)
    }

    @Test("A bad probability list or value means not checked")
    func badInput() {
        let bad: [(String, JevScoreAnswer, Double, Double)] = [
            ("two levels", Self.score([0.9, 0.1]), 0.1, 0.1),
            ("four levels", Self.score([0.7, 0.1, 0.1, 0.1]), 0.1, 0.1),
            ("no levels", Self.score([]), 0.1, 0.1),
            ("a level above 1", Self.score([1.2, 0.05, 0.05]), 0.1, 0.1),
            ("a level below 0", Self.score([-0.1, 0.5, 0.6]), 0.1, 0.1),
            ("a NaN level", Self.score([.nan, 0.5, 0.5]), 0.1, 0.1),
            ("an infinite level", Self.score([.infinity, 0, 0]), 0.1, 0.1),
            ("names_change above 1", Self.score([0.9, 0.05, 0.05]), 1.2, 0.1),
            ("names_change below 0", Self.score([0.9, 0.05, 0.05]), -0.1, 0.1),
            ("a NaN names_change", Self.score([0.9, 0.05, 0.05]), .nan, 0.1),
            ("asks_answer above 1", Self.score([0.9, 0.05, 0.05]), 0.1, 1.2),
            ("a NaN asks_answer", Self.score([0.9, 0.05, 0.05]), 0.1, .nan),
            ("an infinite asks_answer", Self.score([0.9, 0.05, 0.05]), 0.1, .infinity),
        ]
        for (name, clarity, change, answer) in bad {
            #expect(NoteCoachRule.label(clarity: clarity, namesChange: change, asksAnswer: answer, reportsProblem: 0.1) == nil, "\(name)")
        }
        let good = Self.score([0.9, 0.05, 0.05])
        for problem in [1.2, -0.1, Double.nan, Double.infinity] {
            #expect(NoteCoachRule.label(clarity: good, namesChange: 0.1, asksAnswer: 0.1, reportsProblem: problem) == nil, "reports_problem \(problem)")
        }
    }

    @Test("The thresholds are the values the accuracy test set")
    func thresholds() {
        #expect(NoteCoachRule.vagueLevelMinimum == 0.7)
        #expect(NoteCoachRule.vagueAnswerMaximum == 0.5)
        #expect(NoteCoachRule.questionAnswerMinimum == 0.7)
        #expect(NoteCoachRule.questionChangeMaximum == 0.8)
        #expect(NoteCoachRule.questionProblemMaximum == 0.5)
    }

    @Test("Only vague, question, and empty have a line")
    func lineText() {
        #expect(NoteCoachRule.line(for: .vague) == "Ask the reviewer first: the note names no change.")
        #expect(NoteCoachRule.line(for: .question) == "Answer this item. Change no code.")
        #expect(NoteCoachRule.line(for: .empty) == "Ask the reviewer first: the item has no note.")
        #expect(NoteCoachRule.line(for: .unsure) == nil)
        #expect(NoteCoachRule.line(for: .partial) == nil)
        #expect(NoteCoachRule.line(for: .clear) == nil)
    }

    @Test("A label's code text is its name")
    func labelCodes() {
        #expect(NoteCoachLabel.allCases.map(\.code.text) == NoteCoachLabel.allCases.map(\.rawValue))
        #expect(NoteCoachLabel.allCases.map(\.rawValue) == ["empty", "vague", "unsure", "partial", "question", "clear"])
    }
}

// MARK: - The runner

@Suite("Note coach: with the runner")
struct NoteCoachRunnerTests {
    private static func transport(levels: [Double] = [0.9, 0.05, 0.05], change: Double = 0.1, answer: Double = 0.1) -> StubTransport {
        StubTransport(fallback: jsonResponse(noteCoachBody(item: "1.1", levels: levels, change: change, answer: answer)))
    }

    @Test("With noteCoach off, or with jevBase off, nothing is sent or written")
    func off() async throws {
        for flags: [FeatureFlag: FlagState] in [[.jevBase: .on], [.noteCoach: .on]] {
            let bundle = try await Bundle.make()
            let transport = Self.transport()
            let runner = makeRunner(bundle, jobs: [NoteCoachJob()], flags: flags, transport: transport)
            await runCapture(runner, bundle)
            await runner.settle(folderName: bundle.folderName, timeout: .milliseconds(50))

            #expect(await transport.count == 0, "\(flags) sent a request")
            #expect(!bundle.exists("jev.json"), "\(flags) wrote jev.json")
            #expect(!bundle.exists("jev-review/noteCoach.md"), "\(flags) wrote a review")
            #expect(!bundle.exists(JevRefinedRenderer.captureFileName(for: bundle.capture)), "\(flags) wrote a refined file")
        }
    }

    @Test("Shadow records the answers, the label, and the review, and writes no refined line")
    func shadow() async throws {
        let bundle = try await Bundle.make()
        let transport = Self.transport()
        let runner = makeRunner(bundle, jobs: [NoteCoachJob()], flags: [.jevBase: .on, .noteCoach: .shadow], transport: transport)
        await runCapture(runner, bundle)

        #expect(await transport.count == 1)
        let record = try #require(try bundle.record(1))
        #expect(record.job == "noteCoach" && record.jobVersion == 2 && record.mode == "shadow" && record.status == .done)
        #expect(record.answers.map(\.id) == ["1.1.clarity", "1.1.names_change", "1.1.asks_answer", "1.1.reports_problem"])
        #expect(record.lines.isEmpty)
        #expect(record.summary == .object([JevSummaryField(key: "1.1", value: "vague")]))
        #expect(!bundle.exists(JevRefinedRenderer.captureFileName(for: bundle.capture)))
        #expect(!bundle.exists("refined.md"))

        let review = try bundle.text("jev-review/noteCoach.md")
        #expect(review.contains("### Capture 1"))
        #expect(review.contains(#"- 1.1: vague. Level 0 0.90, change 0.10, answer 0.10, problem 0.05. Note: "make it brighter""#))
    }

    @Test("On writes the vague line under the item in the capture's refined file")
    func on() async throws {
        let bundle = try await Bundle.make()
        let runner = makeRunner(bundle, jobs: [NoteCoachJob()], flags: [.jevBase: .on, .noteCoach: .on], transport: Self.transport())
        await runCapture(runner, bundle)

        let record = try #require(try bundle.record(1))
        #expect(record.mode == "on" && record.status == .done)
        #expect(record.lines.map(\.label) == ["Ask the reviewer first: the note names no change."])

        let refined = try bundle.text(JevRefinedRenderer.captureFileName(for: bundle.capture))
        #expect(refined.contains("Item 1.1:\n- Ask the reviewer first: the note names no change.\n"))
    }

    @Test("On with a question writes the answer line")
    func onQuestion() async throws {
        let bundle = try await Bundle.make()
        let transport = Self.transport(levels: [0.1, 0.2, 0.7], change: 0.1, answer: 0.9)
        let runner = makeRunner(bundle, jobs: [NoteCoachJob()], flags: [.jevBase: .on, .noteCoach: .on], transport: transport)
        await runCapture(runner, bundle)

        let refined = try bundle.text(JevRefinedRenderer.captureFileName(for: bundle.capture))
        #expect(refined.contains("Item 1.1:\n- Answer this item. Change no code.\n"))
    }

    @Test("When Jev fails, the job is not refined and no note coach line appears")
    func failure() async throws {
        let bundle = try await Bundle.make()
        let runner = makeRunner(bundle, jobs: [NoteCoachJob()], flags: [.jevBase: .on, .noteCoach: .on], transport: StubTransport())
        await runCapture(runner, bundle)

        let record = try #require(try bundle.record(1))
        #expect(record.status == .notRefined)
        #expect(record.lines.isEmpty)
        let name = JevRefinedRenderer.captureFileName(for: bundle.capture)
        let refined = try bundle.exists(name) ? bundle.text(name) : ""
        #expect(!refined.contains("Ask the reviewer first"))
        #expect(!refined.contains("Answer this item"))
        #expect(!refined.contains("Item 1.1:"))
    }
}
