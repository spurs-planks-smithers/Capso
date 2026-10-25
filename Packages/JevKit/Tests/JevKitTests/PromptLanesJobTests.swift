import FeedbackKit
import Foundation
import Testing
@testable import JevKit

// Made-up notes only: the repository is public.

// MARK: - Fixtures

/// A capture with one counter mark per entry, plus a mark with no badge. The
/// window title, app name, file names, and OCR text all hold the word
/// "secret", so a test can prove none of them reach a request.
private func makeLanesCapture(index: Int = 1, notes: [(badge: Int, note: String?)], general: String? = "context words") -> FeedbackCapture {
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

/// The answers for one item, as the client returns them. Each shape is a
/// probability list, and `exact` is the probability of the `exact` option.
private typealias LanesShape = (severity: [Double], size: [Double], exact: Double)

/// Bug, one file, exact at 0.90: lane A.
private let mechanical: LanesShape = ([0.05, 0.15, 0.7, 0.1], [0.1, 0.7, 0.15, 0.05], 0.9)
/// Blocker, many files, exact at 0.20: lane B.
private let judgment: LanesShape = ([0.0, 0.1, 0.2, 0.7], [0.05, 0.1, 0.15, 0.7], 0.2)

private func expectedLevel(_ probabilities: [Double]) -> Double {
    probabilities.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element }
}

private func answers(_ item: String, _ shape: LanesShape) -> [String: JevAnswer] {
    [
        "\(item).severity": .score(JevScoreAnswer(score: expectedLevel(shape.severity), confidence: 0.8, probabilities: shape.severity)),
        "\(item).size": .score(JevScoreAnswer(score: expectedLevel(shape.size), confidence: 0.8, probabilities: shape.size)),
        "\(item).kind": .choice(JevChoiceAnswer(option: shape.exact >= 0.5 ? "exact" : "judgment", confidence: 0.8, probabilities: ["exact": shape.exact, "judgment": 1 - shape.exact])),
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

private func scoreJSON(_ id: String, _ levels: [Double]) -> String {
    let scale = levels.enumerated().map { #""\#($0.offset)":\#($0.element)"# }.joined(separator: ",")
    return #""\#(id)":{"type":"score","score":\#(expectedLevel(levels)),"confidence":0.9,"legend":{},"probabilities":{\#(scale)}}"#
}

/// A 200 body that answers one item's three questions, in the client's format.
private func lanesBody(item: String, _ shape: LanesShape) -> String {
    let kind = #""\#(item).kind":{"type":"choice","choice":"exact","confidence":0.9,"probabilities":{"exact":\#(shape.exact),"judgment":\#(1 - shape.exact)}}"#
    let answers = [scoreJSON("\(item).severity", shape.severity), scoreJSON("\(item).size", shape.size), kind].joined(separator: ",")
    return #"{"model":"\#(JevEndpoint.model)","answers":{\#(answers)},"usage":{"input_tokens":60,"output_tokens":4}}"#
}

private func score(_ probabilities: [Double]) -> JevScoreAnswer {
    JevScoreAnswer(score: 1, confidence: 0.9, probabilities: probabilities)
}

private func choice(exact: Double?) -> JevChoiceAnswer {
    var probabilities = ["judgment": 0.1]
    if let exact { probabilities["exact"] = exact }
    return JevChoiceAnswer(option: "exact", confidence: 0.9, probabilities: probabilities)
}

// MARK: - The job

@Suite("Prompt lanes: the job")
struct PromptLanesJobTests {
    @Test("One request holds each filled note and the general note, and nothing from the screen")
    func requestShape() async throws {
        let capture = makeLanesCapture(notes: [(3, "make the cards line up"), (1, "rename this to Invoice Detail"), (2, nil)])
        let sent = RequestLog()
        _ = try await PromptLanesJob().run(makeContext(capture: capture, sent: sent))

        let requests = await sent.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.kinds == .reviewerText)
        #expect(request.images.isEmpty)
        #expect(!request.needsImagesHeader)
        #expect(request.questions.map(\.id.text) == ["1.1.severity", "1.1.size", "1.1.kind", "1.3.severity", "1.3.size", "1.3.kind"])

        // Each question names its own item's path in the state.
        for entry in request.questions {
            let path = entry.id.text.hasPrefix("1.1.") ? "`items[0].note`" : "`items[1].note`"
            #expect(codeText(entry.question.instructions).contains(path), "\(entry.id.text) names the wrong item")
        }

        // The state is exact: general note first, then the filled items in
        // badge order. Item 2 has no note, so it is not there.
        let body = String(decoding: try JevRequestEncoder.encode(request).body, as: UTF8.self)
        #expect(body.contains(#""state":{"general_note":"context words","items":[{"item":"1.1","note":"rename this to Invoice Detail"},{"item":"1.3","note":"make the cards line up"}]},"questions""#))
        #expect(!body.lowercased().contains("secret"))
        #expect(!body.contains("unbadged"))
        for fromScreen in [capture.windowTitle, capture.sourceApp, capture.ocrText, capture.imageFile, capture.cleanImageFile].compactMap({ $0 }) {
            #expect(!body.contains(fromScreen), "the request holds \(fromScreen)")
        }
    }

    @Test("Consent for screen text and images changes nothing in the request")
    func consentChangesNothing() async throws {
        let capture = makeLanesCapture(notes: [(1, "rename this to Invoice Detail"), (2, nil), (3, "make the cards line up")])
        var bodies: [Data] = []
        for allowed: JevDataKinds in [.reviewerText, [.reviewerText, .screenText, .images]] {
            let sent = RequestLog()
            _ = try await PromptLanesJob().run(makeContext(capture: capture, allowed: allowed, sent: sent))
            let request = try #require(await sent.requests.first)
            #expect(request.kinds == .reviewerText)
            #expect(!request.needsImagesHeader)
            bodies.append(try JevRequestEncoder.encode(request).body)
        }
        #expect(bodies[0] == bodies[1])
    }

    @Test("The questions use the agreed wording")
    func questionWording() async throws {
        let capture = makeLanesCapture(notes: [(1, "rename this to Invoice Detail")])
        let sent = RequestLog()
        _ = try await PromptLanesJob().run(makeContext(capture: capture, sent: sent))
        let request = try #require(await sent.requests.first)
        #expect(request.questions.count == 3)

        let severity = request.questions[0].question
        #expect(codeText(severity.instructions) == #"How serious is the problem that `items[0].note` describes? `general_note` is context from the same reviewer. Words like "this" or "here" refer to the marked item."#)
        guard case .score(let severityLevels) = severity.kind else {
            Issue.record("severity is not a Score")
            return
        }
        #expect(severityLevels.map(codeText) == [
            #"A small taste preference. The screen works and reads well without it. Example: "maybe a slightly warmer gray"."#,
            #"The change improves the look, the wording, or the layout. Nothing is broken. Example: "make this title bigger"."#,
            #"Something is broken, inconsistent, or cut off, but the screen still works. Example: "the tags are cut off on the right"."#,
            #"The feature fails, shows wrong data, or stops the user from finishing a task. Example: "this total does not match the total on page 2"."#,
        ])

        let size = request.questions[1].question
        #expect(codeText(size.instructions) == "How much code will a developer likely change to do what `items[0].note` asks?")
        guard case .score(let sizeLevels) = size.kind else {
            Issue.record("size is not a Score")
            return
        }
        #expect(sizeLevels.map(codeText) == [
            #"One value, word, or sentence in one place. Example: "rename this column to Voice Minutes"."#,
            #"A few related edits in one place, such as one component or one page. Example: "make these four cards the same width"."#,
            #"Edits in a few files or places. Example: "use the same footnote on page 2 and page 3"."#,
            #"A change across the app, the repository, or every page. Example: "rename this everywhere in the app"."#,
        ])

        let kind = request.questions[2].question
        #expect(codeText(kind.instructions) == "Can a developer do every change in `items[0].note` with no design or product choice?")
        guard case .choice(let options) = kind.kind else {
            Issue.record("kind is not a Choice")
            return
        }
        #expect(options.map(\.name.text) == ["exact", "judgment"])
        #expect(options.map { codeText($0.description) } == [
            #"Every change is exact: new text given in full, a named color, a size or spacing number, or one named element to remove. Example: "remove the sentence about sources"."#,
            #"At least one change needs a choice: make something clearer, better, or consistent, pick a layout, research, explain, or answer a question. A note that names no concrete change, such as "fix this", is judgment too."#,
        ])
    }

    @Test("A badge with several marks uses the first note, and a missing general note is sent as empty")
    func sharedBadge() async throws {
        let capture = makeLanesCapture(notes: [(1, nil), (1, "first words"), (1, "second words")], general: nil)
        #expect(PromptLanesJob.items(in: capture).map(\.badge) == [1])
        #expect(PromptLanesJob.items(in: capture).map(\.note) == ["first words"])

        let sent = RequestLog()
        _ = try await PromptLanesJob().run(makeContext(capture: capture, sent: sent))
        let request = try #require(await sent.requests.first)
        #expect(request.questions.count == 3)
        let body = String(decoding: try JevRequestEncoder.encode(request).body, as: UTF8.self)
        #expect(body.contains(#""state":{"general_note":"","items":[{"item":"1.1","note":"first words"}]}"#))
    }

    @Test("When every note is empty, no request is sent, and each item is askFirst")
    func allEmpty() async throws {
        let capture = makeLanesCapture(notes: [(1, nil), (2, "   "), (3, "\n")])
        let sent = RequestLog()
        let output = try await PromptLanesJob().run(makeContext(capture: capture, sent: sent))

        #expect(await sent.count == 0)
        #expect(output.summary == [1, 2, 3].map { JevSummaryField(key: "1.\($0)", value: .fields(["lane": "askFirst"])) })
        #expect(output.lines.isEmpty)
        #expect(output.files.isEmpty)
        #expect(output.failure == nil)
        // The review shows each note as stored, so item 2 keeps its spaces.
        #expect(output.review == """
        - 1.1: ask first. Note: ""
        - 1.2: ask first. Note: "   "
        - 1.3: ask first. Note: ""
        """)
    }

    @Test("A capture with no badges sends nothing and returns nothing")
    func noItems() async throws {
        let sent = RequestLog()
        let output = try await PromptLanesJob().run(makeContext(capture: makeLanesCapture(notes: []), sent: sent))
        #expect(output == .empty)
        #expect(await sent.count == 0)
    }

    @Test("The output has no refined lines and no files, a summary per item, and a review")
    func outputShape() async throws {
        let capture = makeLanesCapture(notes: [(1, "rename this to Invoice\nDetail"), (2, nil), (3, "make the cards line up")])
        let reply = response(answers("1.1", mechanical), answers("1.3", judgment))
        let output = try await PromptLanesJob().run(makeContext(capture: capture, response: reply))

        #expect(output.lines.isEmpty)
        #expect(output.files.isEmpty)
        #expect(output.failure == nil)
        #expect(output.summary == [
            JevSummaryField(key: "1.1", value: .fields(["lane": "A", "severity": 2, "size": 1])),
            JevSummaryField(key: "1.2", value: .fields(["lane": "askFirst"])),
            JevSummaryField(key: "1.3", value: .fields(["lane": "B", "severity": 3, "size": 3])),
        ])
        // The review holds each note on one line, and no screen text.
        #expect(output.review == """
        - 1.1: lane A. bug 0.70, one file 0.70, exact 0.90. Note: "rename this to Invoice Detail"
        - 1.2: ask first. Note: ""
        - 1.3: lane B. blocker 0.70, many files 0.70, exact 0.20. Note: "make the cards line up"
        """)
        #expect(output.review?.lowercased().contains("secret") == false)
    }

    @Test("A missing or bad answer makes only its item notRated")
    func missingOrBadAnswer() async throws {
        let capture = makeLanesCapture(notes: [(1, "rename this to Invoice Detail"), (2, "make the cards line up"), (3, "use the same footnote on page 2 and page 3"), (4, "remove the sentence about sources")])
        var threeLevels = answers("1.2", mechanical)
        threeLevels["1.2.severity"] = .score(JevScoreAnswer(score: 1, confidence: 0.8, probabilities: [0.2, 0.6, 0.2]))
        var wrongType = answers("1.3", mechanical)
        wrongType["1.3.kind"] = .noul(0.9)
        // Item 4 has no answers at all.
        let output = try await PromptLanesJob().run(makeContext(capture: capture, response: response(answers("1.1", mechanical), threeLevels, wrongType)))

        #expect(output.summary == [
            JevSummaryField(key: "1.1", value: .fields(["lane": "A", "severity": 2, "size": 1])),
            JevSummaryField(key: "1.2", value: .fields(["lane": "notRated"])),
            JevSummaryField(key: "1.3", value: .fields(["lane": "notRated"])),
            JevSummaryField(key: "1.4", value: .fields(["lane": "notRated"])),
        ])
        let review = try #require(output.review)
        #expect(review.contains(#"- 1.2: not rated. Note: "make the cards line up""#))
        #expect(review.contains(#"- 1.4: not rated. Note: "remove the sentence about sources""#))
    }

    @Test("An error from the asker ends the job")
    func errorPropagates() async {
        var context = makeContext(capture: makeLanesCapture(notes: [(1, "rename this to Invoice Detail")]))
        context = JevJobContext(
            round: context.round, capture: context.capture, folderURL: context.folderURL, allowed: context.allowed,
            deadline: context.deadline, jev: JevAsker { _ in throw JevError(.timeout) }, images: context.images
        )
        await #expect(throws: JevError(.timeout)) {
            _ = try await PromptLanesJob().run(context)
        }
    }

    @Test("The job is registered at version 1, with no consent beyond reviewer text")
    func identity() {
        let job = PromptLanesJob()
        #expect(job.id == "promptLanes" && job.flag == .promptLanes)
        #expect(job.version == 1)
        #expect(job.requires.isEmpty)
        #expect(JevJobRegistry.all.contains { $0.id == "promptLanes" && $0.version == 1 })
    }
}

// MARK: - The rule

@Suite("Prompt lanes: the rule")
struct PromptLanesRuleTests {
    @Test("The most likely level wins, and a tie takes the higher level")
    func level() {
        #expect(PromptLanesRule.level(score([0, 0, 0.1, 0.9]), levels: 4) == 3)
        #expect(PromptLanesRule.level(score([0.7, 0.1, 0.1, 0.1]), levels: 4) == 0)
        #expect(PromptLanesRule.level(score([0.1, 0.1, 0.7, 0.1]), levels: 4) == 2)
        #expect(PromptLanesRule.level(score([0.5, 0.5, 0, 0]), levels: 4) == 1)
        #expect(PromptLanesRule.level(score([0, 0.5, 0.5, 0]), levels: 4) == 2)
        #expect(PromptLanesRule.level(score([0.25, 0.25, 0.25, 0.25]), levels: 4) == 3)
    }

    @Test("Severity and size take the top level, and a tie takes the higher level")
    func ratingLevels() throws {
        let kind = choice(exact: 0.9)
        let blocker = try #require(PromptLanesRule.rate(severity: score([0, 0, 0.1, 0.9]), size: score([0.9, 0.1, 0, 0]), kind: kind))
        #expect(blocker.severity == .blocker && blocker.size == .oneLine)

        let severityTie = try #require(PromptLanesRule.rate(severity: score([0.5, 0.5, 0, 0]), size: score([0.9, 0.1, 0, 0]), kind: kind))
        #expect(severityTie.severity == .polish)

        let sizeTie = try #require(PromptLanesRule.rate(severity: score([0, 0, 1, 0]), size: score([0, 0.5, 0.5, 0]), kind: kind))
        #expect(sizeTie.size == .severalFiles)
        #expect(sizeTie.exact == 0.9)
    }

    @Test("Lane A needs exact at 0.8, a small size, and no blocker")
    func laneA() throws {
        let size = score([0, 1, 0, 0])
        let severity = score([0, 0, 1, 0])
        let atThreshold = try #require(PromptLanesRule.rate(severity: severity, size: size, kind: choice(exact: 0.8)))
        #expect(atThreshold.laneA)
        #expect(atThreshold.severity == .bug && atThreshold.size == .oneFile && atThreshold.exact == 0.8)

        #expect(try #require(PromptLanesRule.rate(severity: severity, size: size, kind: choice(exact: 0.79))).laneA == false)
        #expect(try #require(PromptLanesRule.rate(severity: severity, size: score([0, 0, 1, 0]), kind: choice(exact: 0.9))).laneA == false)
        #expect(try #require(PromptLanesRule.rate(severity: severity, size: score([0, 0, 0, 1]), kind: choice(exact: 0.9))).laneA == false)
        #expect(try #require(PromptLanesRule.rate(severity: score([0, 0, 0, 1]), size: size, kind: choice(exact: 0.9))).laneA == false)

        // One line is as small as one file. Nit and polish pass.
        #expect(try #require(PromptLanesRule.rate(severity: score([1, 0, 0, 0]), size: score([1, 0, 0, 0]), kind: choice(exact: 1))).laneA)
        #expect(try #require(PromptLanesRule.rate(severity: score([0, 1, 0, 0]), size: score([1, 0, 0, 0]), kind: choice(exact: 1))).laneA)
    }

    @Test("A missing answer, the wrong level count, or a bad number means not rated")
    func notRated() {
        let good = score([0.1, 0.2, 0.6, 0.1])
        let kind = choice(exact: 0.9)
        #expect(PromptLanesRule.rate(severity: good, size: good, kind: kind) != nil)

        #expect(PromptLanesRule.rate(severity: nil, size: good, kind: kind) == nil)
        #expect(PromptLanesRule.rate(severity: good, size: nil, kind: kind) == nil)
        #expect(PromptLanesRule.rate(severity: good, size: good, kind: nil) == nil)
        #expect(PromptLanesRule.rate(severity: score([0.2, 0.6, 0.2]), size: good, kind: kind) == nil)
        #expect(PromptLanesRule.rate(severity: good, size: score([0.2, 0.2, 0.2, 0.2, 0.2]), kind: kind) == nil)
        #expect(PromptLanesRule.rate(severity: score([]), size: good, kind: kind) == nil)
        #expect(PromptLanesRule.rate(severity: score([.nan, 0.5, 0.25, 0.25]), size: good, kind: kind) == nil)
        #expect(PromptLanesRule.rate(severity: score([1.2, 0, 0, 0]), size: good, kind: kind) == nil)
        #expect(PromptLanesRule.rate(severity: score([-0.1, 0.5, 0.3, 0.3]), size: good, kind: kind) == nil)
        #expect(PromptLanesRule.rate(severity: good, size: score([.infinity, 0, 0, 0]), kind: kind) == nil)
        #expect(PromptLanesRule.rate(severity: good, size: score([0, 0, 0, 1.2]), kind: kind) == nil)
        #expect(PromptLanesRule.rate(severity: good, size: good, kind: choice(exact: nil)) == nil)
        #expect(PromptLanesRule.rate(severity: good, size: good, kind: choice(exact: .nan)) == nil)
        #expect(PromptLanesRule.rate(severity: good, size: good, kind: choice(exact: 1.2)) == nil)
        #expect(PromptLanesRule.rate(severity: good, size: good, kind: choice(exact: -0.1)) == nil)
    }

    @Test("A level needs the right count and numbers from 0 to 1")
    func levelChecks() {
        #expect(PromptLanesRule.level(nil, levels: 4) == nil)
        #expect(PromptLanesRule.level(score([0.5, 0.5]), levels: 4) == nil)
        #expect(PromptLanesRule.level(score([0.5, 0.5]), levels: 2) == 1)
        #expect(PromptLanesRule.level(score([.nan, 0.5, 0.25, 0.25]), levels: 4) == nil)
        #expect(PromptLanesRule.level(score([1.2, 0, 0, 0]), levels: 4) == nil)
    }

    @Test("The exact minimum is 0.8")
    func thresholds() {
        #expect(PromptLanesRule.exactMinimum == 0.8)
    }
}

// MARK: - The runner

@Suite("Prompt lanes: with the runner")
struct PromptLanesRunnerTests {
    private static func transport() -> StubTransport {
        StubTransport(fallback: jsonResponse(lanesBody(item: "1.1", mechanical)))
    }

    @Test("With promptLanes off, or with jevBase off, nothing is sent or written")
    func off() async throws {
        for flags: [FeatureFlag: FlagState] in [[.jevBase: .on], [.promptLanes: .on]] {
            let bundle = try await Bundle.make()
            let transport = Self.transport()
            let runner = makeRunner(bundle, jobs: [PromptLanesJob()], flags: flags, transport: transport)
            await runCapture(runner, bundle)
            await runner.settle(folderName: bundle.folderName, timeout: .milliseconds(50))

            #expect(await transport.count == 0, "\(flags) sent a request")
            #expect(!bundle.exists("jev.json"), "\(flags) wrote jev.json")
            #expect(!bundle.exists("jev-review/promptLanes.md"), "\(flags) wrote a review")
            #expect(!bundle.exists(JevRefinedRenderer.captureFileName(for: bundle.capture)), "\(flags) wrote a refined file")
        }
    }

    @Test("Shadow records the answers and the summary, and writes no refined file")
    func shadow() async throws {
        let bundle = try await Bundle.make()
        let transport = Self.transport()
        let runner = makeRunner(bundle, jobs: [PromptLanesJob()], flags: [.jevBase: .on, .promptLanes: .shadow], transport: transport)
        await runCapture(runner, bundle)

        #expect(await transport.count == 1)
        let record = try #require(try bundle.record(1))
        #expect(record.job == "promptLanes" && record.jobVersion == 1 && record.mode == "shadow" && record.status == .done)
        #expect(record.answers.map(\.id) == ["1.1.severity", "1.1.size", "1.1.kind"])
        #expect(record.lines.isEmpty)
        #expect(record.summary == .object([JevSummaryField(key: "1.1", value: .fields(["lane": "A", "severity": 2, "size": 1]))]))
        #expect(!bundle.exists(JevRefinedRenderer.captureFileName(for: bundle.capture)))
        #expect(!bundle.exists("refined.md"))

        let review = try bundle.text("jev-review/promptLanes.md")
        #expect(review.contains("## Capture 1") && !review.contains("### Capture"))
        #expect(review.contains(#"- 1.1: lane A. bug 0.70, one file 0.70, exact 0.90. Note: "make it brighter""#))
    }

    @Test("On writes the same summary and still no refined line")
    func on() async throws {
        let bundle = try await Bundle.make()
        let runner = makeRunner(bundle, jobs: [PromptLanesJob()], flags: [.jevBase: .on, .promptLanes: .on], transport: Self.transport())
        await runCapture(runner, bundle)

        let record = try #require(try bundle.record(1))
        #expect(record.mode == "on" && record.status == .done)
        #expect(record.lines.isEmpty)
        #expect(record.summary == .object([JevSummaryField(key: "1.1", value: .fields(["lane": "A", "severity": 2, "size": 1]))]))
        let name = JevRefinedRenderer.captureFileName(for: bundle.capture)
        let refined = try bundle.exists(name) ? bundle.text(name) : ""
        #expect(!refined.contains("Item 1.1:"))
    }
}
