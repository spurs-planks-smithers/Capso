import FeedbackKit
import Foundation
import Testing
@testable import JevKit

// MARK: Fixtures

/// What the canned asker answers for one pair: the Score of `sameAsk` and the
/// probability of `opposite`.
private struct PairScore: Sendable {
    var sameAsk: Double
    var opposite: Double
}

private struct ImageFailure: Error {}

/// A counter badge with an instruction. Boxes sit apart, so no badge takes a shape.
private func dupesItem(_ badge: Int, _ text: String?, ocr: String? = nil) -> FeedbackMark {
    FeedbackMark(
        kind: .counter,
        badge: badge,
        box: FeedbackBox(x1: 40 * badge, y1: 100, x2: 40 * badge + 30, y2: 130),
        ocrText: ocr,
        instruction: text
    )
}

private func dupesCapture(
    _ index: Int,
    app: String? = "Claude",
    window: String? = "Main",
    note: String? = nil,
    marks: [FeedbackMark] = []
) -> FeedbackCapture {
    FeedbackCapture(
        index: index,
        imageFile: "10\(index)-claude.png",
        cleanImageFile: "10\(index)-claude-clean.png",
        size: PixelSize(width: 800, height: 600),
        capturedAt: Date(timeIntervalSince1970: 1_792_000_000 + Double(index)),
        sourceApp: app,
        windowTitle: window,
        note: note,
        marks: marks
    )
}

/// Returns a blank image of the size the job asks for. A capture in `failing`
/// throws instead.
private func dupesImages(failing: Set<Int> = []) -> JevImageLoader {
    JevImageLoader { capture, _, region in
        if failing.contains(capture) { throw ImageFailure() }
        let box = region ?? FeedbackBox(x1: 0, y1: 0, x2: 800, y2: 600)
        return JevImage(
            png: Data(),
            size: PixelSize(width: 400, height: 300),
            sourceRegion: box,
            contentRect: FeedbackBox(x1: 0, y1: 0, x2: 400, y2: 300)
        )
    }
}

private typealias Ask = @Sendable (JevRequest) async throws -> JevResponse

/// A context for the capture with index `current` of a round that holds `captures`.
private func dupesContext(
    _ captures: [FeedbackCapture],
    current: Int,
    allowed: JevDataKinds = .reviewerText,
    images: JevImageLoader = dupesImages(),
    ask: @escaping Ask
) -> JevJobContext {
    let round = FeedbackRound(
        name: "feedback",
        slug: "feedback",
        folderName: "2026-10-24-1028-feedback",
        startedAt: Date(timeIntervalSince1970: 1_792_000_000),
        captures: captures
    )
    return JevJobContext(
        round: round,
        capture: captures.first { $0.index == current }!,
        folderURL: URL(fileURLWithPath: "/tmp/nextshot-test/\(round.folderName)", isDirectory: true),
        allowed: allowed,
        deadline: .now + .seconds(2),
        jev: JevAsker(ask),
        images: images
    )
}

/// Answers each question by pair. The table is keyed by "<new id>.vs.<earlier id>".
/// A pair that the table lacks answers 0 for both questions. It records each request.
private func canned(_ table: [String: PairScore] = [:], log: RequestLog = RequestLog()) -> Ask {
    { request in
        await log.append(request)
        var answers: [String: JevAnswer] = [:]
        for (id, _) in request.questions {
            guard let parsed = DupesConflicts.parse(questionID: id.text) else { continue }
            let pair = table["\(parsed.new).vs.\(parsed.earlier)"] ?? PairScore(sameAsk: 0, opposite: 0)
            switch parsed.kind {
            case .sameAsk:
                answers[id.text] = .score(JevScoreAnswer(score: pair.sameAsk, confidence: 1, probabilities: [0, 0, 0]))
            case .opposite:
                answers[id.text] = .noul(pair.opposite)
            }
        }
        return JevResponse(model: JevEndpoint.model, answers: answers, inputTokens: 0, outputTokens: 0)
    }
}

/// Throws for a request whose first question belongs to a listed new entry.
private func failing(_ errors: [String: any Error & Sendable], otherwise ask: @escaping Ask) -> Ask {
    { request in
        if let first = request.questions.first,
           let parsed = DupesConflicts.parse(questionID: first.id.text),
           let error = errors[parsed.new] {
            throw error
        }
        return try await ask(request)
    }
}

// MARK: Reading requests

private func field(_ name: String, in value: JevValue?) -> JevValue? {
    guard case .object(let fields)? = value else { return nil }
    return fields.first { $0.0.text == name }?.1
}

private func names(of value: JevValue?) -> [String] {
    guard case .object(let fields)? = value else { return [] }
    return fields.map { $0.0.text }
}

private func newObjects(of request: JevRequest) -> [JevValue] {
    guard case .array(let items)? = field("new", in: request.state) else { return [] }
    return items
}

private func newIDs(of request: JevRequest) -> [String] {
    newObjects(of: request).compactMap { object in
        guard case .code(let id)? = field("id", in: object) else { return nil }
        return id.text
    }
}

private func questionText(_ question: JevQuestion) -> String? {
    guard case .code(let text)? = field("question", in: question.instructions) else { return nil }
    return text.text
}

private func requestHolding(_ newID: String, in requests: [JevRequest]) -> JevRequest? {
    requests.first { newIDs(of: $0) == [newID] }
}

private func itemLine(_ badge: Int, _ label: JevCodeText) -> JevRefinedLine {
    JevRefinedLine(scope: .item(badge: badge), label: label)
}

private func scopedLine(_ scope: JevRefinedLine.Scope, _ label: JevCodeText) -> JevRefinedLine {
    JevRefinedLine(scope: scope, label: label)
}

// MARK: Tests

@Suite("Duplicates and conflicts job")
struct DupesConflictsJobTests {
    // MARK: Identity

    @Test("The job keeps its id, flag, and no required kinds, and sits at version 1")
    func identity() {
        let job = DupesConflictsJob()
        #expect(job.id == "dupesConflicts")
        #expect(job.flag == .dupesConflicts)
        #expect(job.requires == [])
        #expect(job.version == 1)
    }

    @Test("Every failure reason has a code name equal to its raw value")
    func reasonCodes() {
        for reason in JevFailureReason.allCases {
            #expect(DupesConflicts.code(reason).text == reason.rawValue, "\(reason)")
        }
    }

    // MARK: Entries

    @Test("Entries are the items with an instruction in badge order, then the note")
    func entriesList() {
        let capture = dupesCapture(4, app: "Claude", window: "Main", note: "  keep spaces  ", marks: [
            dupesItem(5, "rename it"),
            dupesItem(1, "make it bigger", ocr: "Save"),
            dupesItem(2, nil),
            dupesItem(3, " \n\t"),
            dupesItem(4, ""),
        ])
        let entries = DupesConflicts.entries(of: capture)
        #expect(entries.map(\.id) == ["4.1", "4.5", "4.note"])

        let crops = PreviewCrop.cropsByBadge(marks: capture.marks, imageSize: capture.size, margin: 120, aspectRatio: 4.0 / 3.0)
        #expect(entries[0].badge == 1)
        #expect(entries[0].captureIndex == 4)
        #expect(entries[0].note == "make it bigger")
        #expect(entries[0].screenText == "Save")
        #expect(entries[0].app == "Claude")
        #expect(entries[0].windowTitle == "Main")
        #expect(entries[0].cropRegion == crops[1])
        #expect(entries[1].cropRegion == crops[5])

        // A note has no badge, no screen text, and no crop: it means the whole image.
        #expect(entries[2].badge == nil)
        #expect(entries[2].note == "  keep spaces  ")
        #expect(entries[2].screenText == nil)
        #expect(entries[2].cropRegion == nil)
        #expect(entries[2].name == "the general note of capture 4")
        #expect(entries[2].sentenceName == "The general note of capture 4")
        #expect(entries[0].name == "4.1")
    }

    @Test("A whitespace-only note is not an entry")
    func whitespaceNoteSkipped() {
        let capture = dupesCapture(2, note: " \n\t ", marks: [dupesItem(1, "make it bigger")])
        #expect(DupesConflicts.entries(of: capture).map(\.id) == ["2.1"])
        #expect(DupesConflicts.entries(of: dupesCapture(2, note: nil)).isEmpty)
    }

    @Test("The request holds a note exactly as stored")
    func noteSentUntrimmed() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, note: "  keep spaces\n", marks: []),
        ]
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: canned(log: log)))
        let requests = await log.requests
        #expect(requests.count == 1)
        guard case .reviewer(let text)? = field("note", in: newObjects(of: requests[0]).first) else {
            Issue.record("The new entry has no reviewer note")
            return
        }
        #expect(text == "  keep spaces\n")
    }

    // MARK: Pairs

    @Test("The first capture of a round sends no request and returns empty")
    func firstCaptureSendsNothing() async throws {
        let captures = [dupesCapture(1, note: "a note", marks: [dupesItem(1, "make it bigger")])]
        let log = RequestLog()
        let output = try await DupesConflictsJob().run(dupesContext(captures, current: 1, ask: canned(log: log)))
        #expect(output == .empty)
        #expect(await log.count == 0)
    }

    @Test("A capture with no new entry, or with no earlier entry, sends nothing")
    func noEntriesSendsNothing() async throws {
        let log = RequestLog()

        let noNew = [dupesCapture(1, marks: [dupesItem(1, "make it bigger")]), dupesCapture(2, marks: [dupesItem(1, nil)])]
        let noNewOutput = try await DupesConflictsJob().run(dupesContext(noNew, current: 2, ask: canned(log: log)))
        #expect(noNewOutput == .empty)

        let noEarlier = [dupesCapture(1, marks: [dupesItem(1, "")]), dupesCapture(2, marks: [dupesItem(1, "make it bigger")])]
        let noEarlierOutput = try await DupesConflictsJob().run(dupesContext(noEarlier, current: 2, ask: canned(log: log)))
        #expect(noEarlierOutput == .empty)

        #expect(await log.count == 0)
    }

    @Test("A new entry pairs only with entries of captures with a lower index")
    func pairsWithLowerIndexOnly() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "use a darker blue"), dupesItem(2, "remove the border")]),
            dupesCapture(3, marks: [dupesItem(1, "rename the menu")]),
        ]
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: canned(log: log)))
        let requests = await log.requests
        #expect(requests.count == 2)

        let ids = requests.flatMap { $0.questions.map { $0.id.text } }
        #expect(ids.count == 4)
        for id in ids {
            let parsed = DupesConflicts.parse(questionID: id)
            #expect(parsed?.new.hasPrefix("2.") == true, "\(id)")
            #expect(parsed?.earlier == "1.1", "\(id)")
        }
    }

    // MARK: Consent

    private func consentRequests(
        earlier: (app: String?, window: String?) = ("Claude", "Main"),
        current: (app: String?, window: String?) = ("Claude", "Main"),
        allowed: JevDataKinds
    ) async throws -> [JevRequest] {
        let captures = [
            dupesCapture(1, app: earlier.app, window: earlier.window, marks: [dupesItem(1, "make the title bigger", ocr: "Save")]),
            dupesCapture(2, app: current.app, window: current.window, note: "general ask", marks: [dupesItem(1, "make the title smaller", ocr: "Save changes")]),
        ]
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 2, allowed: allowed, ask: canned(log: log)))
        return await log.requests
    }

    @Test("With reviewer text only, a request holds no screen text, app, or crop")
    func reviewerTextOnly() async throws {
        let requests = try await consentRequests(allowed: .reviewerText)
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.kinds == .reviewerText)
            #expect(names(of: request.state) == ["new"])
            for object in newObjects(of: request) {
                #expect(names(of: object) == ["id", "note"])
            }
            for entry in request.questions {
                let text = questionText(entry.question) ?? ""
                #expect(!text.contains(JevPrompting.screenTextNotice.text))
                #expect(!text.contains("Screen text for"))
                #expect(!text.contains("Crop for"))
            }
        }
    }

    @Test("With screen text allowed, the state holds screen text and each question starts with the notice")
    func screenTextAllowed() async throws {
        let requests = try await consentRequests(allowed: [.reviewerText, .screenText])
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.kinds.contains(.screenText))
            #expect(!request.kinds.contains(.images))
            #expect(request.images.isEmpty)
            #expect(names(of: field("earlier_screen_text", in: request.state)) == ["e1_1"])
            for entry in request.questions {
                let text = questionText(entry.question) ?? ""
                #expect(text.hasPrefix(JevPrompting.screenTextNotice.text + " "))
                #expect(text.contains(" Screen text for earlier_note: `earlier_screen_text.e1_1`."))
                #expect(!text.contains("Crop for"))
            }
        }
        let item = try #require(requestHolding("2.1", in: requests))
        #expect(names(of: newObjects(of: item).first) == ["id", "note", "screen_text", "app"])
        // A note has no mark, so no screen text. Its app name still goes.
        let note = try #require(requestHolding("2.note", in: requests))
        #expect(names(of: newObjects(of: note).first) == ["id", "note", "app"])
    }

    @Test("With images allowed and the same app, crops go for new and earlier entries")
    func imagesSameApp() async throws {
        let requests = try await consentRequests(earlier: ("Claude", "Inbox"), current: ("Claude", "Main"), allowed: [.reviewerText, .images])
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.kinds.contains(.images))
            #expect(!request.kinds.contains(.screenText))
            #expect(names(of: request.state) == ["new", "earlier_crops"])
            #expect(names(of: newObjects(of: request).first) == ["id", "note", "crop"])
            #expect(names(of: field("earlier_crops", in: request.state)) == ["e1_1"])
            #expect(request.images.count == 2)
            for entry in request.questions {
                let text = questionText(entry.question) ?? ""
                #expect(!text.contains(JevPrompting.screenTextNotice.text))
                #expect(text.hasSuffix(" Crop for earlier_note: `earlier_crops.e1_1`. Crop for the new note: `new[0].crop`."))
            }
        }
    }

    @Test("A shared window title is enough for images, even with different apps")
    func imagesSameWindowTitle() async throws {
        let requests = try await consentRequests(earlier: ("Mail", "Main"), current: ("Claude", "Main"), allowed: [.reviewerText, .images])
        #expect(requests.allSatisfy { $0.images.count == 2 })
    }

    @Test("With different apps and window titles, no image goes")
    func noImagesForDifferentSources() async throws {
        let requests = try await consentRequests(earlier: ("Mail", "Inbox"), current: ("Claude", "Main"), allowed: [.reviewerText, .screenText, .images])
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.images.isEmpty)
            #expect(!request.kinds.contains(.images))
            #expect(names(of: request.state) == ["new", "earlier_screen_text"])
            #expect(!names(of: newObjects(of: request).first).contains("crop"))
        }
    }

    @Test("A missing name on both sides is not the same source")
    func missingNamesNeverMatch() async throws {
        let allKinds: JevDataKinds = [.reviewerText, .screenText, .images]
        let noNames = try await consentRequests(earlier: (nil, nil), current: (nil, nil), allowed: allKinds)
        #expect(noNames.count == 2)
        #expect(noNames.allSatisfy { $0.images.isEmpty })

        let differentTitles = try await consentRequests(earlier: (nil, "Inbox"), current: (nil, "Main"), allowed: allKinds)
        #expect(differentTitles.allSatisfy { $0.images.isEmpty })

        // The same non-empty window title still matches when both apps are missing.
        let sameTitle = try await consentRequests(earlier: (nil, "Main"), current: (nil, "Main"), allowed: allKinds)
        #expect(sameTitle.allSatisfy { $0.images.count == 2 })
    }

    @Test("A failed image load leaves that image out and does not fail the job")
    func imageLoadFailure() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "make the title smaller")]),
        ]

        let earlierFails = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(
            captures, current: 2, allowed: [.reviewerText, .images],
            images: dupesImages(failing: [1]), ask: canned(log: earlierFails)
        ))
        let firstRequests = await earlierFails.requests
        let first = try #require(firstRequests.first)
        #expect(names(of: first.state) == ["new"])
        #expect(names(of: newObjects(of: first).first) == ["id", "note", "crop"])
        #expect(first.questions.allSatisfy { !(questionText($0.question) ?? "").contains("Crop for earlier_note") })

        let newFails = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(
            captures, current: 2, allowed: [.reviewerText, .images],
            images: dupesImages(failing: [2]), ask: canned(log: newFails)
        ))
        let secondRequests = await newFails.requests
        let second = try #require(secondRequests.first)
        #expect(names(of: newObjects(of: second).first) == ["id", "note"])
        #expect(second.questions.allSatisfy { !(questionText($0.question) ?? "").contains("Crop for the new note") })
    }

    // MARK: Earlier crop cap

    @Test("At most 6 earlier crops go in a request, newest first")
    func earlierCropCap() async throws {
        let captures = [
            dupesCapture(1, marks: (1...5).map { dupesItem($0, "first capture ask \($0)") }),
            dupesCapture(2, marks: (1...3).map { dupesItem($0, "second capture ask \($0)") }),
            dupesCapture(3, marks: [dupesItem(1, "make it bigger")]),
        ]
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 3, allowed: [.reviewerText, .images], ask: canned(log: log)))
        let requests = await log.requests
        #expect(requests.count == 1)
        let request = requests[0]

        #expect(names(of: field("earlier_crops", in: request.state)) == ["e2_3", "e2_2", "e2_1", "e1_5", "e1_4", "e1_3"])
        // Six earlier crops and the new entry's crop.
        #expect(request.images.count == 7)

        // The two oldest pairs go text only.
        for entry in request.questions {
            let parsed = try #require(DupesConflicts.parse(questionID: entry.id.text))
            let text = questionText(entry.question) ?? ""
            if parsed.earlier == "1.1" || parsed.earlier == "1.2" {
                #expect(!text.contains("Crop for earlier_note"), "\(entry.id)")
            } else {
                #expect(text.contains("Crop for earlier_note: `earlier_crops.e\(parsed.earlier.replacingOccurrences(of: ".", with: "_"))`."), "\(entry.id)")
            }
        }
    }

    // MARK: Question ids

    @Test("A question id parses back into its pair and kind")
    func questionIDParser() {
        func entry(_ capture: Int, _ badge: Int?) -> DupesConflicts.Entry {
            DupesConflicts.Entry(captureIndex: capture, badge: badge, note: "n")
        }
        let samples: [(String, DupesConflicts.Entry, DupesConflicts.Entry, DupesConflicts.QuestionKind)] = [
            ("4.2.vs.3.2.sameAsk", entry(4, 2), entry(3, 2), .sameAsk),
            ("4.note.vs.3.2.opposite", entry(4, nil), entry(3, 2), .opposite),
            ("4.2.vs.3.note.sameAsk", entry(4, 2), entry(3, nil), .sameAsk),
            ("12.10.vs.11.3.opposite", entry(12, 10), entry(11, 3), .opposite),
        ]
        for (id, new, earlier, kind) in samples {
            let parsed = DupesConflicts.parse(questionID: id)
            #expect(parsed?.new == new.id.text, "\(id)")
            #expect(parsed?.earlier == earlier.id.text, "\(id)")
            #expect(parsed?.kind == kind, "\(id)")
            #expect(DupesConflicts.questionID(new: new, earlier: earlier, kind: kind).text == id)
        }
        #expect(DupesConflicts.parse(questionID: "garbage") == nil)
        #expect(DupesConflicts.parse(questionID: "4.2.vs.3.2.other") == nil)
        #expect(DupesConflicts.parse(questionID: "4.2.sameAsk") == nil)
        #expect(DupesConflicts.parse(questionID: ".vs.3.2.sameAsk") == nil)
    }

    @Test("Every question id in a request is unique, and each pair has a sameAsk and an opposite question")
    func questionIDsUnique() async throws {
        let captures = [
            dupesCapture(1, note: "first note", marks: [dupesItem(1, "make the title bigger"), dupesItem(2, "remove the border")]),
            dupesCapture(2, note: "second note", marks: [dupesItem(1, "use a darker blue")]),
            dupesCapture(3, note: "third note", marks: [dupesItem(1, "rename the menu"), dupesItem(2, "move the button")]),
        ]
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 3, ask: canned(log: log)))
        let requests = await log.requests
        #expect(requests.count == 3)

        var all: [String] = []
        for request in requests {
            let ids = request.questions.map { $0.id.text }
            #expect(Set(ids).count == ids.count)
            all += ids
        }
        // 3 new entries and 5 earlier entries make 15 pairs and 30 questions.
        #expect(all.count == 30)
        #expect(Set(all).count == 30)
        #expect(all.contains("3.note.vs.2.note.opposite"))
        #expect(all.contains("3.1.vs.1.note.sameAsk"))
    }

    // MARK: Chunking

    @Test("Chunks keep the order and the count: one each up to 8, then exactly 8")
    func chunkSizes() {
        func entries(_ count: Int) -> [DupesConflicts.Entry] {
            (1...count).map {
                DupesConflicts.Entry(captureIndex: 9, badge: $0, note: "n")
            }
        }
        #expect(DupesConflicts.chunks(entries(5)).map(\.count) == [1, 1, 1, 1, 1])
        #expect(DupesConflicts.chunks(entries(8)).map(\.count) == Array(repeating: 1, count: 8))
        #expect(DupesConflicts.chunks(entries(9)).map(\.count) == [2] + Array(repeating: 1, count: 7))
        #expect(DupesConflicts.chunks(entries(17)).map(\.count) == [3] + Array(repeating: 2, count: 7))
        #expect(DupesConflicts.chunks(entries(40)).map(\.count) == Array(repeating: 5, count: 8))
        #expect(DupesConflicts.chunks(entries(40)).flatMap { $0 }.map(\.id) == entries(40).map(\.id))
    }

    @Test("17 new entries make 8 requests, and every pair's two questions appear once")
    func seventeenEntries() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger"), dupesItem(2, "remove the border")]),
            dupesCapture(2, note: "general ask", marks: (1...16).map { dupesItem($0, "ask number \($0)") }),
        ]
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: canned(log: log)))
        let requests = await log.requests
        #expect(requests.count == 8)

        let counts = requests.map { newIDs(of: $0).count }.sorted()
        #expect(counts == Array(repeating: 2, count: 7) + [3])

        let shared = try #require(requests.first { newIDs(of: $0).count == 3 })
        let sharedIDs = newIDs(of: shared)
        #expect(sharedIDs == ["2.1", "2.2", "2.3"])
        let texts = shared.questions.compactMap { questionText($0.question) }
        #expect(texts.contains { $0.contains("`new[0]`") })
        #expect(texts.contains { $0.contains("`new[1]`") })
        #expect(texts.contains { $0.contains("`new[2]`") })
        for entry in shared.questions {
            // The position in the text matches the new entry in the id.
            let parsed = try #require(DupesConflicts.parse(questionID: entry.id.text))
            let position = try #require(sharedIDs.firstIndex(of: parsed.new))
            #expect((questionText(entry.question) ?? "").contains("`new[\(position)]`"), "\(entry.id)")
        }

        let new = (1...16).map { "2.\($0)" } + ["2.note"]
        let earlier = ["1.1", "1.2"]
        var expected = Set<String>()
        for n in new {
            for e in earlier {
                expected.insert("\(n).vs.\(e).sameAsk")
                expected.insert("\(n).vs.\(e).opposite")
            }
        }
        let sent = requests.flatMap { $0.questions.map { $0.id.text } }
        #expect(sent.count == 68)
        #expect(Set(sent) == expected)
    }

    // MARK: Decision rules

    @Test("The decision edges: 0.49, 0.5, 1.49, 1.5, and opposite 0.69 and 0.7")
    func decisionEdges() {
        func outcome(_ sameAsk: Double?, _ opposite: Double?) -> DupesConflicts.Outcome {
            DupesConflicts.outcome(sameAsk: sameAsk, opposite: opposite)
        }
        #expect(outcome(0.49, 0) == .different)
        #expect(outcome(0.5, 0) == .overlap)
        #expect(outcome(1.49, 0) == .overlap)
        #expect(outcome(1.5, 0) == .duplicate)
        #expect(outcome(2.0, 0.3) == .duplicate)
        #expect(outcome(0.0, 0.69) == .different)
        #expect(outcome(0.0, 0.7) == .conflict)
        // A conflict wins over a duplicate.
        #expect(outcome(1.9, 0.7) == .conflict)
        // A missing answer counts as different.
        #expect(outcome(nil, nil) == .different)
        #expect(outcome(nil, 0.69) == .different)
        #expect(outcome(1.9, nil) == .duplicate)
        #expect(outcome(nil, 0.7) == .conflict)
    }

    @Test("The thresholds are the design's values")
    func thresholds() {
        #expect(DupesConflicts.conflictAt == 0.7)
        #expect(DupesConflicts.duplicateAt == 1.5)
        #expect(DupesConflicts.overlapAt == 0.5)
    }

    @Test("A response with no answers adds no line")
    func missingAnswers() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "make the title smaller")]),
        ]
        let log = RequestLog()
        let output = try await DupesConflictsJob().run(dupesContext(captures, current: 2) { request in
            await log.append(request)
            return JevResponse(model: JevEndpoint.model, answers: [:], inputTokens: 0, outputTokens: 0)
        })
        #expect(await log.count == 1, "the job must send its request before it reads the answers")
        // The output is no longer `.empty`: it holds a summary with two empty lists.
        #expect(output.lines.isEmpty)
        #expect(output.files.isEmpty)
    }

    // MARK: Lines

    /// Three captures. The first two hold items 1 and 2, and a general note
    /// each. The third is the one the job runs on.
    private func runLines(
        _ table: [String: PairScore],
        marks: [FeedbackMark] = [],
        note: String? = nil
    ) async throws -> [JevRefinedLine] {
        let captures = [
            dupesCapture(1, note: "rename session to round", marks: [dupesItem(1, "make the title bigger"), dupesItem(2, "remove the border")]),
            dupesCapture(2, note: "the view feels crowded", marks: [dupesItem(1, "make the title smaller"), dupesItem(2, "use a darker blue")]),
            dupesCapture(3, note: note, marks: marks),
        ]
        return try await DupesConflictsJob().run(dupesContext(captures, current: 3, ask: canned(table))).lines
    }

    @Test("A duplicate of two earlier entries gives one round line")
    func duplicateLines() async throws {
        let lines = try await runLines(
            ["3.1.vs.1.1": PairScore(sameAsk: 1.8, opposite: 0), "3.1.vs.2.2": PairScore(sameAsk: 1.6, opposite: 0.3)],
            marks: [dupesItem(1, "make the heading larger")]
        )
        #expect(lines == [
            scopedLine(.round, "Same ask: 3.1 repeats 1.1 and 2.2 (captures 1, 2, and 3). An earlier paste may have made this change. Check the code, and make the change once. Each note is in manifest.md."),
        ])
    }

    @Test("Earlier entries of one capture name that capture once")
    func duplicateLinesOneCapture() async throws {
        let lines = try await runLines(
            ["3.2.vs.1.1": PairScore(sameAsk: 1.5, opposite: 0), "3.2.vs.1.2": PairScore(sameAsk: 1.5, opposite: 0), "3.2.vs.1.note": PairScore(sameAsk: 1.5, opposite: 0)],
            marks: [dupesItem(2, "make the heading larger")]
        )
        #expect(lines == [
            scopedLine(.round, "Same ask: 3.2 repeats 1.1, 1.2, and the general note of capture 1 (captures 1 and 3). An earlier paste may have made this change. Check the code, and make the change once. Each note is in manifest.md."),
        ])
    }

    @Test("An overlap gives one item line and no round line")
    func overlapLines() async throws {
        let one = try await runLines(
            ["3.1.vs.1.1": PairScore(sameAsk: 1.0, opposite: 0)],
            marks: [dupesItem(1, "make the heading larger")]
        )
        #expect(one == [
            itemLine(1, "3.1 may overlap with 1.1. Read 1.1 in manifest.md. An earlier paste may have done part of it. Check the code before you edit twice."),
        ])

        let two = try await runLines(
            ["3.1.vs.1.1": PairScore(sameAsk: 0.5, opposite: 0), "3.1.vs.2.1": PairScore(sameAsk: 1.49, opposite: 0)],
            marks: [dupesItem(1, "make the heading larger")]
        )
        #expect(two == [
            itemLine(1, "3.1 may overlap with 1.1 and 2.1. Read them in manifest.md. An earlier paste may have done part of it. Check the code before you edit twice."),
        ])
    }

    @Test("A conflict gives one round line, and it wins over a duplicate")
    func conflictLines() async throws {
        let lines = try await runLines(
            ["3.2.vs.2.1": PairScore(sameAsk: 1.9, opposite: 0.8)],
            marks: [dupesItem(1, "make the heading larger"), dupesItem(2, "make the heading smaller")]
        )
        #expect(lines == [
            scopedLine(.round, "Ask first: 3.2 and 2.1 ask for opposite changes to the same element. Read both in manifest.md. Ask the user which one wins before you edit either. 3.2 is newer."),
        ])
    }

    @Test("A general note gets capture-scope lines and names itself in words")
    func noteLines() async throws {
        let lines = try await runLines(
            [
                "3.note.vs.1.1": PairScore(sameAsk: 1.7, opposite: 0),
                "3.note.vs.1.note": PairScore(sameAsk: 1.0, opposite: 0),
                "3.note.vs.2.note": PairScore(sameAsk: 0, opposite: 0.9),
            ],
            note: "keep the old wording"
        )
        #expect(lines == [
            scopedLine(.round, "Same ask: the general note of capture 3 repeats 1.1 (captures 1 and 3). An earlier paste may have made this change. Check the code, and make the change once. Each note is in manifest.md."),
            scopedLine(.capture, "The general note of capture 3 may overlap with the general note of capture 1. Read the general note of capture 1 in manifest.md. An earlier paste may have done part of it. Check the code before you edit twice."),
            scopedLine(.round, "Ask first: the general note of capture 3 and the general note of capture 2 ask for opposite changes to the same element. Read both in manifest.md. Ask the user which one wins before you edit either. The general note of capture 3 is newer."),
        ])
    }

    @Test("An entry whose pairs are all different adds no line")
    func differentPairsAddNoLine() async throws {
        let lines = try await runLines(
            ["3.1.vs.1.1": PairScore(sameAsk: 0.49, opposite: 0.69), "3.1.vs.2.1": PairScore(sameAsk: 0.2, opposite: 0.1)],
            marks: [dupesItem(1, "make the heading larger")],
            note: "keep the old wording"
        )
        #expect(lines.isEmpty)
    }

    @Test("Lines follow the entry order, and no line holds screen text or a file name")
    func lineOrder() async throws {
        let lines = try await runLines(
            [
                "3.1.vs.2.1": PairScore(sameAsk: 0, opposite: 0.75),
                "3.2.vs.1.2": PairScore(sameAsk: 1.6, opposite: 0),
                "3.note.vs.1.1": PairScore(sameAsk: 0.8, opposite: 0),
            ],
            marks: [dupesItem(1, "make the heading larger", ocr: "Heading"), dupesItem(2, "drop the border")],
            note: "keep the old wording"
        )
        #expect(lines.map(\.scope) == [.round, .round, .capture])
        let prefixes = [
            "Ask first: 3.1 and 2.1",
            "Same ask: 3.2 repeats 1.2",
            "The general note of capture 3 may overlap with 1.1",
        ]
        #expect(lines.count == prefixes.count)
        for (line, prefix) in zip(lines, prefixes) {
            #expect(line.label.text.hasPrefix(prefix), "\(line.label)")
        }
        #expect(lines.allSatisfy { $0.screenText == nil && $0.file == nil })
        #expect(!lines.contains { $0.label.text.contains("Heading") })
    }

    // MARK: Failures

    @Test("A failed request keeps the other answers and adds a Not checked line")
    func oneRequestFails() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "make the heading larger"), dupesItem(2, "make the heading larger")]),
        ]
        let ask = failing(["2.1": JevError(.timeout)], otherwise: canned(["2.2.vs.1.1": PairScore(sameAsk: 1.9, opposite: 0)]))
        let output = try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: ask))
        #expect(output.lines == [
            scopedLine(.round, "Same ask: 2.2 repeats 1.1 (captures 1 and 2). An earlier paste may have made this change. Check the code, and make the change once. Each note is in manifest.md."),
            scopedLine(.capture, "Not checked for repeats (timeout): 2.1."),
        ])
    }

    @Test("A long list splits into labels the writer does not cut, and names every entry")
    func longListsSplit() throws {
        let entry = DupesConflicts.Entry(captureIndex: 9, badge: 1, note: "make it bigger")
        let earlier: [DupesConflicts.Entry] = (1...8).flatMap { capture -> [DupesConflicts.Entry] in
            (1...6).map { (badge: Int) in
                DupesConflicts.Entry(captureIndex: capture, badge: badge, note: "ask")
            }
        }
        for outcome in [DupesConflicts.Outcome.duplicate, .overlap] {
            let lines = DupesConflicts.lines(for: entry, outcomes: earlier.map { ($0, outcome) })
            try #require(lines.count > 1, "48 entries must not fit one label")
            #expect(lines.allSatisfy { $0.label.text.unicodeScalars.count <= DupesConflicts.maxLabelLength })
            let named = earlier.map(\.id).filter { id in
                lines.contains { $0.label.text.contains(" \(id),") || $0.label.text.contains(" \(id) ") || $0.label.text.contains(" \(id).") }
            }
            #expect(named.count == earlier.count, "every earlier entry is named")
        }
    }

    @Test("Failure lines group the entries by reason, in the order the reasons first appear")
    func failureReasons() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, note: "general ask", marks: (1...4).map { dupesItem($0, "ask \($0)") }),
        ]
        let ask = failing(
            ["2.1": JevError(.offline), "2.2": JevError(.timeout), "2.3": JevError(.offline, status: nil)],
            otherwise: canned()
        )
        let output = try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: ask))
        #expect(output.lines == [
            scopedLine(.capture, "Not checked for repeats (offline): 2.1 and 2.3."),
            scopedLine(.capture, "Not checked for repeats (timeout): 2.2."),
        ])
    }

    @Test("A note that fails is named in words")
    func failedNoteNamed() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, note: "general ask", marks: [dupesItem(1, "make it smaller")]),
        ]
        let ask = failing(["2.note": JevError(.server, status: 503)], otherwise: canned())
        let output = try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: ask))
        #expect(output.lines == [scopedLine(.capture, "Not checked for repeats (server): the general note of capture 2.")])
    }

    @Test("When every request fails, the job throws the first JevError")
    func everyRequestFails() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "make it smaller"), dupesItem(2, "make it larger")]),
        ]
        let allTimeout = failing(["2.1": JevError(.timeout), "2.2": JevError(.timeout)], otherwise: canned())
        await #expect(throws: JevError(.timeout)) {
            try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: allTimeout))
        }

        // The first error is the one of the first request, not the first to finish.
        let mixed = failing(["2.1": JevError(.offline), "2.2": JevError(.timeout)], otherwise: canned())
        await #expect(throws: JevError(.offline)) {
            try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: mixed))
        }
    }

    @Test("An error that is not a JevError ends the job")
    func otherErrorsRethrown() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "make it smaller"), dupesItem(2, "make it larger")]),
        ]
        let ask = failing(["2.1": CancellationError()], otherwise: canned())
        await #expect(throws: CancellationError.self) {
            try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: ask))
        }
    }

    @Test("The summary lists the flagged pairs in entry order and the entries that were not checked")
    func summaryOfFlaggedAndNotChecked() async throws {
        let captures = [
            dupesCapture(1, note: "rename session to round", marks: [dupesItem(1, "make the title bigger"), dupesItem(2, "remove the border")]),
            dupesCapture(2, marks: [dupesItem(1, "make the title smaller")]),
            dupesCapture(3, marks: (1...4).map { dupesItem($0, "ask number \($0)") }),
        ]
        let table = [
            "3.1.vs.1.2": PairScore(sameAsk: 1.0, opposite: 0),
            // The different pair: both answers sit just under the thresholds.
            "3.1.vs.2.1": PairScore(sameAsk: 0.49, opposite: 0.69),
            "3.2.vs.2.1": PairScore(sameAsk: 0, opposite: 0.8),
            "3.3.vs.1.1": PairScore(sameAsk: 1.8, opposite: 0),
        ]
        let ask = failing(["3.4": JevError(.timeout)], otherwise: canned(table))
        let output = try await DupesConflictsJob().run(dupesContext(captures, current: 3, ask: ask))
        #expect(output.summary == [
            JevSummaryField(key: "flagged", value: .array([
                .fields(["pair": "3.1.vs.1.2", "outcome": "overlap"]),
                .fields(["pair": "3.2.vs.2.1", "outcome": "conflict"]),
                .fields(["pair": "3.3.vs.1.1", "outcome": "duplicate"]),
            ])),
            JevSummaryField(key: "notChecked", value: .array([
                .fields(["entry": "3.4", "reason": "timeout"]),
            ])),
        ])
    }

    @Test("A fixed round gives a stored copy of the encoded request")
    func storedRequest() async throws {
        let captures = [
            dupesCapture(1, note: "rename session to round", marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "make the heading larger")]),
        ]
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: canned(log: log)))
        let request = try #require(await log.requests.first)
        let json = String(decoding: try JevRequestEncoder.encode(request).body, as: UTF8.self)

        let sameAsk = #""question":"Compare the review note of `new[0]` with earlier_note in this question. Both are a reviewer's change requests for an app's interface. How do the two notes relate as change requests?""#
        let opposite = #""question":"Compare the review note of `new[0]` with earlier_note in this question. Do the two notes ask for changes to the same element that cannot both be done?""#
        let levels = #""criteria":["They ask for different changes, or for changes to different elements. This includes the same kind of change on a different element, page, or screen.","They overlap. Part of one ask is in the other, or they may be about the same element. A person should check.","They ask for the same change to the same element."]"#
        let yesNo = #""criteria":{"true":"For example: larger and smaller, remove it and rename it, or two different values for the same setting.","false":"Different elements, changes that can both be done, or one note adds detail to the other."}"#
        let expected = #"{"model":"jev-1.14.0","state":{"new":[{"id":"2.1","note":"make the heading larger"}]},"questions":{"#
            + #""2.1.vs.1.1.sameAsk":{"type":"score","instructions":{"# + sameAsk + #","earlier_id":"1.1","earlier_note":"make the title bigger"},"# + levels + "},"
            + #""2.1.vs.1.1.opposite":{"type":"noul","instructions":{"# + opposite + #","earlier_id":"1.1","earlier_note":"make the title bigger"},"# + yesNo + "},"
            + #""2.1.vs.1.note.sameAsk":{"type":"score","instructions":{"# + sameAsk + #","earlier_id":"1.note","earlier_note":"rename session to round"},"# + levels + "},"
            + #""2.1.vs.1.note.opposite":{"type":"noul","instructions":{"# + opposite + #","earlier_id":"1.note","earlier_note":"rename session to round"},"# + yesNo + "}"
            + "}}"
        #expect(json == expected)
    }

    @Test("A request never holds more images than the encoder allows")
    func imageLimit() async throws {
        // 40 new entries make 8 requests of 5 entries, each with a crop,
        // plus the earlier crops that still fit.
        let captures = [
            dupesCapture(1, marks: (1...8).map { dupesItem($0, "earlier ask \($0)") }),
            dupesCapture(2, marks: (1...40).map { dupesItem($0, "new ask \($0)") }),
        ]
        // The encoder refuses an empty PNG, so this loader returns one byte.
        let images = JevImageLoader { _, _, region in
            JevImage(
                png: Data([1]),
                size: PixelSize(width: 400, height: 300),
                sourceRegion: region ?? FeedbackBox(x1: 0, y1: 0, x2: 800, y2: 600),
                contentRect: FeedbackBox(x1: 0, y1: 0, x2: 400, y2: 300)
            )
        }
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 2, allowed: [.reviewerText, .images], images: images, ask: canned(log: log)))
        let requests = await log.requests
        #expect(requests.count == 8)
        for request in requests {
            #expect(request.images.count <= JevRequestEncoder.maxImages)
            _ = try JevRequestEncoder.encode(request)
        }
    }
}

/// The job inside the real runner, client, and writer, with a stubbed transport.
@Suite("Duplicates and conflicts in the runner")
struct DupesConflictsRunnerTests {
    /// A 200 body that answers the one pair of a two-capture bundle: 2.1 and 1.1.
    private func pairBody(sameAsk: Double, opposite: Double) -> String {
        #"{"model":"\#(JevEndpoint.model)","answers":{"2.1.vs.1.1.sameAsk":{"type":"score","score":\#(sameAsk),"confidence":0.9,"probabilities":{"0":0.0,"1":0.2,"2":0.8}},"2.1.vs.1.1.opposite":{"type":"noul","noul":\#(opposite)}},"usage":{"input_tokens":40,"output_tokens":2}}"#
    }

    @Test("With dupesConflicts or jevBase off, nothing is sent and no Jev file is written")
    func offSendsNothing() async throws {
        let cases: [[FeatureFlag: FlagState]] = [
            [:],
            [.jevBase: .on],
            [.jevBase: .on, .jevSendImages: .on, .jevSendScreenText: .on],
            [.dupesConflicts: .on, .jevSendImages: .on, .jevSendScreenText: .on],
        ]
        for flags in cases {
            let bundle = try await Bundle.make(captures: 2)
            let transport = StubTransport(fallback: jsonResponse(pairBody(sameAsk: 1.8, opposite: 0.05)))
            let key = StubKeyProvider()
            let runner = makeRunner(bundle, jobs: [DupesConflictsJob()], flags: flags, transport: transport, key: key)
            await runCapture(runner, bundle, capture: 2)
            #expect(await transport.count == 0, "\(flags) sent a request")
            #expect(await key.reads == 0, "\(flags) read the key")
            #expect(!bundle.exists("jev.json"), "\(flags) wrote jev.json")
            #expect(!bundle.exists("refined.md"), "\(flags) wrote refined.md")
        }
    }

    @Test("Shadow records both answers in jev.json and writes no refined file")
    func shadowRecordsAnswers() async throws {
        let bundle = try await Bundle.make(captures: 2)
        let transport = StubTransport(fallback: jsonResponse(pairBody(sameAsk: 1.8, opposite: 0.05)))
        let runner = makeRunner(bundle, jobs: [DupesConflictsJob()], flags: [.jevBase: .on, .dupesConflicts: .shadow], transport: transport)
        await runCapture(runner, bundle, capture: 2)

        #expect(await transport.count == 1)
        let record = try #require(try bundle.record(2))
        #expect(record.job == "dupesConflicts" && record.jobVersion == 1 && record.mode == "shadow" && record.status == .done)
        #expect(Set(record.answers.map(\.id)) == ["2.1.vs.1.1.sameAsk", "2.1.vs.1.1.opposite"])
        #expect(record.lines.isEmpty)
        #expect(!bundle.exists("refined.md"))
        // The record decodes object keys in sorted order.
        #expect(record.summary == .object([
            JevSummaryField(key: "flagged", value: .array([
                .object([
                    JevSummaryField(key: "outcome", value: "duplicate"),
                    JevSummaryField(key: "pair", value: "2.1.vs.1.1"),
                ]),
            ])),
            JevSummaryField(key: "notChecked", value: .array([])),
        ]))
    }

    @Test("On puts a duplicate's round line once in refined.md and once in the capture's file")
    func onWritesRoundLine() async throws {
        let bundle = try await Bundle.make(captures: 2)
        let transport = StubTransport(fallback: jsonResponse(pairBody(sameAsk: 1.8, opposite: 0.05)))
        let runner = makeRunner(bundle, jobs: [DupesConflictsJob()], flags: [.jevBase: .on, .dupesConflicts: .on], transport: transport)
        await runCapture(runner, bundle, capture: 2)

        let line = "- Same ask: 2.1 repeats 1.1 (captures 1 and 2). An earlier paste may have made this change. Check the code, and make the change once. Each note is in manifest.md."
        let round = try bundle.text("refined.md")
        #expect(round.components(separatedBy: line).count == 2, "refined.md shows the line once")
        #expect(round.contains("Round:\n\(line)\n"))

        let refinedFiles = try FileManager.default.contentsOfDirectory(atPath: bundle.folder.path)
            .filter { $0.hasSuffix("-refined.md") }
            .map { try bundle.text($0) }
        let captureText = try #require(refinedFiles.first { $0.hasPrefix(#"<feedback_refined capture="2""#) })
        #expect(captureText.components(separatedBy: line).count == 2, "the capture file shows the line once")

        // Only Drew's notes go out by default: no app name, window title, or screen text.
        let body = try #require(await transport.requests.first?.httpBody)
        let sent = String(decoding: body, as: UTF8.self)
        #expect(sent.contains("make it brighter"))
        #expect(!sent.contains("Claude"))
        #expect(!sent.contains("Copy Last Capture Prompt"))
    }
}
