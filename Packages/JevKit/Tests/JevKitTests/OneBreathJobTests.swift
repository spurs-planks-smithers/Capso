import FeedbackKit
import Foundation
import Testing
@testable import JevKit

/// Wispr Flow's text for "One, make the title brighter. Two, remove the line
/// under it. Three, move the button left." (Drew's test, 2026-10-24).
private let wispr = "1. Make the title brighter.\n2. Remove the line under it.\n3. Move the button left."

/// A capture with circles 1 to `circles`. Circle 1 holds `first`. Later
/// circles hold `others`, or nothing, as on a trial capture.
private func capture(circles: Int = 3, first: String? = wispr, others: [Int: String] = [:], note: String? = nil, ocr: Bool = false) -> FeedbackCapture {
    FeedbackCapture(
        index: 3,
        imageFile: "1042-safari.png",
        cleanImageFile: "1042-safari-clean.png",
        size: PixelSize(width: 1600, height: 1000),
        capturedAt: Date(timeIntervalSince1970: 1_792_000_000),
        sourceApp: "Safari",
        windowTitle: "Pricing",
        note: note,
        ocrText: "Pricing",
        marks: (1...circles).map { badge in
            FeedbackMark(
                kind: .counter,
                badge: badge,
                box: FeedbackBox(x1: badge * 300, y1: 200, x2: badge * 300 + 40, y2: 240),
                ocrText: ocr ? "Label \(badge)" : nil,
                instruction: badge == 1 ? first : others[badge]
            )
        }
    )
}

private func ids(_ request: JevRequest) -> [String] {
    request.questions.map(\.id.text)
}

private func instructions(_ question: JevQuestion) -> String {
    if case .code(let text) = question.instructions { return text.text }
    return ""
}

private func pick(_ option: String, _ probability: Double) -> JevAnswer {
    .choice(JevChoiceAnswer(option: option, confidence: probability, probabilities: [option: probability]))
}

private func response(_ answers: [String: JevAnswer]) -> JevResponse {
    JevResponse(model: JevEndpoint.model, answers: answers, inputTokens: 0, outputTokens: 0)
}

@Suite("One-breath job: the request")
struct OneBreathRequestTests {
    @Test("A trial answer gets one Noul for the answer and one Choice per part, with Drew's words only")
    func trialRequest() throws {
        let built = try #require(OneBreathPlan(capture: capture()).request(allowed: .reviewerText) { _ in nil })
        #expect(ids(built.request) == ["answer.c1.multi", "part.c1.p1.badge", "part.c1.p2.badge", "part.c1.p3.badge"])
        #expect(built.request.kinds == .reviewerText)
        #expect(built.request.images.isEmpty)
        #expect(built.extras == OneBreathPlan.Extras())
    }

    @Test("Question ids hold positions only, never Drew's words")
    func idsHoldPositions() throws {
        let captures = [
            capture(),
            capture(first: "1. Make it blue, no, gray.\n2. Remove the line.", note: "Overall fine. 1. Bold. 2. Italic."),
            capture(circles: 2, first: "Brighter please", others: [2: "Remove it"]),
        ]
        let pattern = /^(answer\.(c\d+|note)\.multi|part\.(c\d+|note)\.p\d+\.(badge|final))$/
        for capture in captures {
            let built = try #require(OneBreathPlan(capture: capture).request(allowed: .reviewerText) { _ in nil })
            #expect(!built.request.questions.isEmpty)
            for id in ids(built.request) {
                #expect(id.wholeMatch(of: pattern) != nil, "\(id)")
            }
        }
    }

    @Test("A normal answer on each circle gets only the per-answer questions")
    func normalAnswers() throws {
        let built = try #require(OneBreathPlan(capture: capture(circles: 2, first: "Brighter please", others: [2: "Remove it"])).request(allowed: .reviewerText) { _ in nil })
        #expect(ids(built.request) == ["answer.c1.multi", "answer.c2.multi"])
    }

    @Test("Crops go out only with image consent")
    func cropsNeedConsent() throws {
        let image = try preparedImage()
        let plan = OneBreathPlan(capture: capture())
        let without = try #require(plan.request(allowed: .reviewerText) { _ in image })
        #expect(without.request.images.isEmpty && !without.extras.crops)

        let with = try #require(plan.request(allowed: [.reviewerText, .images]) { _ in image })
        #expect(with.request.kinds == [.reviewerText, .images])
        #expect(with.extras.crops)
        #expect(with.request.needsImagesHeader)
    }

    @Test("Circle screen text goes out only with consent, and its questions start with the screen text notice")
    func screenTextNeedsConsent() throws {
        let plan = OneBreathPlan(capture: capture(ocr: true))
        let without = try #require(plan.request(allowed: .reviewerText) { _ in nil })
        #expect(!without.request.kinds.contains(.screenText))

        let with = try #require(plan.request(allowed: [.reviewerText, .screenText]) { _ in nil })
        #expect(with.request.kinds == [.reviewerText, .screenText])
        for entry in with.request.questions where entry.id.text.hasSuffix(".badge") {
            #expect(instructions(entry.question).hasPrefix(JevPrompting.screenTextNotice.text))
        }
    }

    @Test("A part that corrects itself gets a Choice over its clauses, in Drew's words")
    func selfCorrection() throws {
        let built = try #require(OneBreathPlan(capture: capture(first: "1. Make it blue, no, gray.\n2. Remove the line.")).request(allowed: .reviewerText) { _ in nil })
        #expect(ids(built.request).contains("part.c1.p1.final"))
        #expect(!ids(built.request).contains("part.c1.p2.final"))
        let question = try #require(built.request.questions.first { $0.id == "part.c1.p1.final" }?.question)
        guard case .choice(let options) = question.kind else {
            Issue.record("not a choice")
            return
        }
        #expect(options.map(\.name) == ["clause_1", "clause_2", "clause_3"])
        #expect(question.kinds == .reviewerText)
    }

    @Test("A capture with one circle, or with no answer, gets no request")
    func nothingToAsk() async throws {
        #expect(OneBreathPlan(capture: capture(circles: 1)).request(allowed: .reviewerText) { _ in nil } == nil)
        #expect(OneBreathPlan(capture: capture(first: "")).request(allowed: .reviewerText) { _ in nil } == nil)

        let sent = RequestLog()
        let output = try await OneBreathJob().run(makeContext(sent: sent))
        #expect(output == .empty)
        #expect(await sent.count == 0)
    }

    @Test("The job sends its one request through the asker and returns a summary and a review section")
    func jobAsks() async throws {
        let sent = RequestLog()
        let output = try await OneBreathJob().run(makeContext(capture: capture(), sent: sent))
        #expect(await sent.count == 1)
        #expect(await ids(sent.requests[0]).first == "answer.c1.multi")
        #expect(output.lines.isEmpty && output.files.isEmpty && output.failure == nil)
        #expect(output.summary.map(\.key) == ["circles", "emptyCircle", "answers"])
        #expect(output.review?.contains("Code: one-breath, 3 parts.") == true)
    }

    @Test("When Jev fails, the job reports the failure and still returns the code split for review")
    func jobFailure() async throws {
        let base = makeContext(capture: capture())
        let context = JevJobContext(
            round: base.round,
            capture: base.capture,
            folderURL: base.folderURL,
            allowed: base.allowed,
            deadline: base.deadline,
            jev: JevAsker { _ in throw JevError(.timeout) },
            images: base.images
        )
        let output = try await OneBreathJob().run(context)
        #expect(output.failure == JevError(.timeout))
        #expect(output.review?.contains("Jev: not checked (timeout).") == true)
        #expect(output.review?.contains("| 3 | 3. Move the button left. | circle 3 | not checked | |") == true)
    }

    @Test("The summary holds code facts only: numbers, booleans, and code text")
    func summaryFacts() {
        let summary = OneBreathPlan(capture: capture()).summary
        #expect(summary == [
            JevSummaryField(key: "circles", value: .numbers([1, 2, 3])),
            JevSummaryField(key: "emptyCircle", value: true),
            JevSummaryField(key: "answers", value: .object([
                JevSummaryField(key: "c1", value: .fields([
                    "split": true,
                    "parts": 3,
                    "strongMentions": 3,
                    "mediumMentions": 0,
                    "startsAtOne": true,
                    "coversAllCircles": true,
                    "partsWithCues": 0,
                ])),
            ])),
        ])
    }
}

@Suite("One-breath job: the review section")
struct OneBreathReviewTests {
    private let utc = TimeZone(identifier: "UTC")!

    @Test("A trial answer shows each part with code's circle and Jev's pick")
    func trialSection() throws {
        let plan = OneBreathPlan(capture: capture())
        let answers: [String: JevAnswer] = [
            "answer.c1.multi": .noul(0.97),
            "part.c1.p1.badge": pick("circle_1", 0.98),
            "part.c1.p2.badge": pick("circle_2", 0.95),
            "part.c1.p3.badge": pick("circle_1", 0.55),
        ]
        let section = OneBreathReview.section(plan: plan, extras: .init(), response: response(answers), failure: nil, timeZone: utc)
        #expect(section == """
        Captured 17:46, 3 circles.
        Jev had: words.

        ### Answer at circle 1's step
        Code: one-breath, 3 parts. Jev: one-breath, 0.97.

        | Part | Drew's words | Code | Jev | Fix |
        | --- | --- | --- | --- | --- |
        | 1 | 1. Make the title brighter. | circle 1 | circle 1, 0.98 | |
        | 2 | 2. Remove the line under it. | circle 2 | circle 2, 0.95 | |
        | 3 | 3. Move the button left. | circle 3 | unsure (circle 1, 0.55) | |

        """)
    }

    @Test("When Jev fails, the section still shows the code split")
    func failureSection() throws {
        let section = try #require(OneBreathReview.section(plan: OneBreathPlan(capture: capture()), extras: .init(), response: nil, failure: "timeout", timeZone: utc))
        #expect(section.contains("Jev: not checked (timeout)."))
        #expect(section.contains("| 2 | 2. Remove the line under it. | circle 2 | not checked | |"))
    }

    @Test("A trial answer that code and Jev both miss still shows in full")
    func missedTrialAnswer() throws {
        let plan = OneBreathPlan(capture: capture(first: "Brighter title, remove the line, move the button"))
        let section = try #require(OneBreathReview.section(plan: plan, extras: .init(), response: response(["answer.c1.multi": .noul(0.2)]), failure: nil, timeZone: utc))
        #expect(section.contains("Code: no split. Jev: normal, 0.20."))
        #expect(section.contains("| 1 | Brighter title, remove the line, move the button | no split | n/a | |"))
    }

    @Test("Normal answers on a fully answered capture appear only as a count")
    func quietAnswers() throws {
        let plan = OneBreathPlan(capture: capture(circles: 2, first: "Brighter please", others: [2: "Remove it"]))
        let section = try #require(OneBreathReview.section(plan: plan, extras: .init(), response: response(["answer.c1.multi": .noul(0.1), "answer.c2.multi": .noul(0.05)]), failure: nil, timeZone: utc))
        #expect(!section.contains("|"))
        #expect(section.hasSuffix("2 other answers: normal (code and Jev agree).\n"))
    }

    @Test("A self-correction shows Jev's final clause in Drew's words")
    func correctionLine() throws {
        let plan = OneBreathPlan(capture: capture(first: "1. Make it blue, no, gray.\n2. Remove the line."))
        let answers: [String: JevAnswer] = [
            "answer.c1.multi": .noul(0.9),
            "part.c1.p1.badge": pick("circle_1", 0.9),
            "part.c1.p2.badge": pick("circle_2", 0.9),
            "part.c1.p1.final": pick("clause_3", 0.91),
        ]
        let section = try #require(OneBreathReview.section(plan: plan, extras: .init(crops: true), response: response(answers), failure: nil, timeZone: utc))
        #expect(section.contains("Jev had: words, crops."))
        #expect(section.contains("Part 1 corrects itself. Jev's final clause: \"gray.\" (0.91)."))
    }

    @Test("A cell stays on one line, escapes pipes, and stops at the limit")
    func cells() throws {
        let long = String(repeating: "a", count: 300)
        let plan = OneBreathPlan(capture: capture(first: "Use a | b\nthen \(long)"))
        let section = try #require(OneBreathReview.section(plan: plan, extras: .init(), response: nil, failure: "offline", timeZone: utc))
        let row = try #require(section.split(separator: "\n").first { $0.hasPrefix("| 1 |") })
        #expect(row.contains("Use a \\| b then aaa"))
        #expect(row.contains("a... |"))
    }

    @Test("A capture with one circle has no section")
    func noSection() {
        #expect(OneBreathReview.section(plan: OneBreathPlan(capture: capture(circles: 1)), extras: .init(), response: nil, failure: nil) == nil)
    }
}

/// A round on disk with one trial capture: three circles, Wispr's list on
/// circle 1, and the other circles empty.
private func trialBundle() async throws -> Bundle {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jev-one-breath-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = FeedbackRoundStore(rootURL: root)
    let round = try await store.start(name: "test")
    let png = JevImagePreparation.pngData(blankImage(width: 800, height: 600))!
    let stored = try await store.addCapture(FeedbackCaptureInput(
        annotatedPNG: png,
        cleanPNG: png,
        size: PixelSize(width: 800, height: 600),
        capturedAt: Date(timeIntervalSince1970: 1_792_000_000),
        sourceApp: "Claude",
        windowTitle: "Claude",
        ocrText: "Copy Last Capture Prompt",
        marks: (1...3).map { FeedbackMark(kind: .counter, badge: $0, box: FeedbackBox(x1: $0 * 200, y1: 100, x2: $0 * 200 + 30, y2: 130)) }
    ))
    try await store.setInstruction(capture: stored.index, badge: 1, text: wispr)
    let capture = try #require(await store.activeRound?.captures.first)
    return Bundle(root: root, folderName: round.folderName, capture: capture)
}

/// Every file in the round folder and its subfolders, by relative path.
private func snapshot(_ bundle: Bundle) throws -> [String: Data] {
    let paths = FileManager.default.subpaths(atPath: bundle.folder.path) ?? []
    var files: [String: Data] = [:]
    for path in paths {
        var isFolder: ObjCBool = false
        let url = bundle.folder.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue {
            files[path] = try Data(contentsOf: url)
        }
    }
    return files
}

private let trialBody = """
{"model":"\(JevEndpoint.model)","answers":{\
"answer.c1.multi":{"type":"noul","noul":0.97},\
"part.c1.p1.badge":{"type":"choice","choice":"circle_1","confidence":0.97,"probabilities":{"circle_1":0.97,"circle_2":0.01,"circle_3":0.01,"none":0.01}},\
"part.c1.p2.badge":{"type":"choice","choice":"circle_2","confidence":0.96,"probabilities":{"circle_1":0.02,"circle_2":0.96,"circle_3":0.01,"none":0.01}},\
"part.c1.p3.badge":{"type":"choice","choice":"circle_3","confidence":0.95,"probabilities":{"circle_1":0.02,"circle_2":0.02,"circle_3":0.95,"none":0.01}}},\
"usage":{"input_tokens":120,"output_tokens":4}}
"""

@Suite("One-breath job: the flag")
struct OneBreathFlagTests {
    @Test("With oneBreath off, nothing is sent or read, and every bundle file stays byte-identical")
    func offMeansOff() async throws {
        let cases: [[FeatureFlag: FlagState]] = [
            [:],
            [.jevBase: .on],
            [.jevBase: .on, .jevSendImages: .on, .jevSendScreenText: .on],
            [.oneBreath: .shadow],
        ]
        for flags in cases {
            let bundle = try await trialBundle()
            let before = try snapshot(bundle)
            let transport = StubTransport(fallback: jsonResponse(trialBody))
            let key = StubKeyProvider()
            let runner = makeRunner(bundle, jobs: [OneBreathJob()], flags: flags, transport: transport, key: key)
            await runCapture(runner, bundle)
            await runner.settle(folderName: bundle.folderName, timeout: .milliseconds(50))

            #expect(await transport.count == 0, "\(flags) sent a request")
            #expect(await key.reads == 0, "\(flags) read the key")
            #expect(try snapshot(bundle) == before, "\(flags) changed a file")
        }
    }

    @Test("In shadow, one request goes out, jev.json and the review file are written, and no other file changes")
    func shadow() async throws {
        let bundle = try await trialBundle()
        let before = try snapshot(bundle)
        let transport = StubTransport(fallback: jsonResponse(trialBody))
        let runner = makeRunner(bundle, jobs: [OneBreathJob()], flags: [.jevBase: .on, .oneBreath: .shadow], transport: transport)
        await runCapture(runner, bundle)

        #expect(await transport.count == 1)
        let record = try #require(try bundle.record(bundle.capture.index))
        #expect(record.job == "oneBreath" && record.mode == "shadow" && record.status == .done)
        #expect(record.jobVersion == 1 && record.requests == 1)
        #expect(record.answers.map(\.id) == ["answer.c1.multi", "part.c1.p1.badge", "part.c1.p2.badge", "part.c1.p3.badge"])
        #expect(record.lines.isEmpty && record.files.isEmpty)

        let review = try bundle.text("jev-review/oneBreath.md")
        #expect(review.contains("Agents: do not act on this file."))
        #expect(review.contains("## Capture 1"))
        #expect(review.contains("| 2 | 2. Remove the line under it. | circle 2 | circle 2, 0.96 | |"))
        #expect(!review.contains("Copy Last Capture Prompt"), "screen text in the review file")

        var after = try snapshot(bundle)
        after["jev.json"] = nil
        after["jev-review/oneBreath.md"] = nil
        #expect(after == before)
    }

    @Test("When Jev is offline in shadow, jev.json says not refined and the review still shows the code split")
    func shadowOffline() async throws {
        let bundle = try await trialBundle()
        let runner = makeRunner(bundle, jobs: [OneBreathJob()], flags: [.jevBase: .on, .oneBreath: .shadow], transport: StubTransport())
        await runCapture(runner, bundle)

        let record = try #require(try bundle.record(bundle.capture.index))
        #expect(record.status == .notRefined && record.reason == .offline)
        let review = try bundle.text("jev-review/oneBreath.md")
        #expect(review.contains("Jev: not checked (offline)."))
        #expect(review.contains("| 1 | 1. Make the title brighter. | circle 1 | not checked | |"))
    }

    @Test("A local override cannot turn oneBreath on")
    func neverOn() {
        for channel in [BuildChannel.dev, .release] {
            #expect(FlagResolver.state(of: .oneBreath, channel: channel) { _ in "on" } == .off)
        }
    }
}
