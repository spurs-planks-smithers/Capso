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
            guard let parsed = DupesConflicts.parse(questionID: id) else { continue }
            let pair = table["\(parsed.new).vs.\(parsed.earlier)"] ?? PairScore(sameAsk: 0, opposite: 0)
            switch parsed.kind {
            case .sameAsk:
                answers[id] = .score(JevScoreAnswer(score: pair.sameAsk, confidence: 1, probabilities: [0, 0, 0]))
            case .opposite:
                answers[id] = .noul(pair.opposite)
            }
        }
        return JevResponse(model: JevEndpoint.model, answers: answers, inputTokens: 0, outputTokens: 0)
    }
}

/// Throws for a request whose first question belongs to a listed new entry.
private func failing(_ errors: [String: any Error & Sendable], otherwise ask: @escaping Ask) -> Ask {
    { request in
        if let first = request.questions.first,
           let parsed = DupesConflicts.parse(questionID: first.id),
           let error = errors[parsed.new] {
            throw error
        }
        return try await ask(request)
    }
}

// MARK: Reading requests

private func field(_ name: String, in value: JevValue?) -> JevValue? {
    guard case .object(let fields)? = value else { return nil }
    return fields.first { $0.0 == name }?.1
}

private func names(of value: JevValue?) -> [String] {
    guard case .object(let fields)? = value else { return [] }
    return fields.map(\.0)
}

private func newObjects(of request: JevRequest) -> [JevValue] {
    guard case .array(let items)? = field("new", in: request.state) else { return [] }
    return items
}

private func newIDs(of request: JevRequest) -> [String] {
    newObjects(of: request).compactMap { object in
        guard case .code(let id)? = field("id", in: object) else { return nil }
        return id
    }
}

private func questionText(_ question: JevQuestion) -> String? {
    guard case .code(let text)? = field("question", in: question.instructions) else { return nil }
    return text
}

private func requestHolding(_ newID: String, in requests: [JevRequest]) -> JevRequest? {
    requests.first { newIDs(of: $0) == [newID] }
}

private func itemLine(_ badge: Int, _ label: String) -> JevRefinedLine {
    JevRefinedLine(scope: .item(badge: badge), label: label)
}

private func scopedLine(_ scope: JevRefinedLine.Scope, _ label: String) -> JevRefinedLine {
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

        let ids = requests.flatMap { $0.questions.map(\.id) }
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
                #expect(!text.contains(JevPrompting.screenTextNotice))
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
                #expect(text.hasPrefix(JevPrompting.screenTextNotice + " "))
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
                #expect(!text.contains(JevPrompting.screenTextNotice))
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
            let parsed = try #require(DupesConflicts.parse(questionID: entry.id))
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
        let samples: [(String, String, String, DupesConflicts.QuestionKind)] = [
            ("4.2.vs.3.2.sameAsk", "4.2", "3.2", .sameAsk),
            ("4.note.vs.3.2.opposite", "4.note", "3.2", .opposite),
            ("4.2.vs.3.note.sameAsk", "4.2", "3.note", .sameAsk),
            ("12.10.vs.11.3.opposite", "12.10", "11.3", .opposite),
        ]
        for (id, new, earlier, kind) in samples {
            let parsed = DupesConflicts.parse(questionID: id)
            #expect(parsed?.new == new, "\(id)")
            #expect(parsed?.earlier == earlier, "\(id)")
            #expect(parsed?.kind == kind, "\(id)")
            #expect(DupesConflicts.questionID(new: new, earlier: earlier, kind: kind) == id)
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
            let ids = request.questions.map(\.id)
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

    @Test("Chunks keep the order and the count: one each up to 16, then exactly 16")
    func chunkSizes() {
        func entries(_ count: Int) -> [DupesConflicts.Entry] {
            (1...count).map {
                DupesConflicts.Entry(id: "9.\($0)", captureIndex: 9, badge: $0, note: "n", screenText: nil, app: nil, windowTitle: nil, cropRegion: nil)
            }
        }
        #expect(DupesConflicts.chunks(entries(5)).map(\.count) == [1, 1, 1, 1, 1])
        #expect(DupesConflicts.chunks(entries(16)).map(\.count) == Array(repeating: 1, count: 16))
        #expect(DupesConflicts.chunks(entries(17)).map(\.count) == [2] + Array(repeating: 1, count: 15))
        #expect(DupesConflicts.chunks(entries(40)).map(\.count) == Array(repeating: 3, count: 8) + Array(repeating: 2, count: 8))
        #expect(DupesConflicts.chunks(entries(40)).flatMap { $0 }.map(\.id) == entries(40).map(\.id))
    }

    @Test("17 new entries make 16 requests, and every pair's two questions appear once")
    func seventeenEntries() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger"), dupesItem(2, "remove the border")]),
            dupesCapture(2, note: "general ask", marks: (1...16).map { dupesItem($0, "ask number \($0)") }),
        ]
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: canned(log: log)))
        let requests = await log.requests
        #expect(requests.count == 16)

        let counts = requests.map { newIDs(of: $0).count }.sorted()
        #expect(counts == Array(repeating: 1, count: 15) + [2])

        let shared = try #require(requests.first { newIDs(of: $0).count == 2 })
        #expect(newIDs(of: shared) == ["2.1", "2.2"])
        let texts = shared.questions.compactMap { questionText($0.question) }
        #expect(texts.contains { $0.contains("`new[0]`") })
        #expect(texts.contains { $0.contains("`new[1]`") })
        for entry in shared.questions {
            // The position in the text matches the new entry in the id.
            let parsed = try #require(DupesConflicts.parse(questionID: entry.id))
            let position = parsed.new == "2.1" ? 0 : 1
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
        let sent = requests.flatMap { $0.questions.map(\.id) }
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
        let output = try await DupesConflictsJob().run(dupesContext(captures, current: 2) { _ in
            JevResponse(model: JevEndpoint.model, answers: [:], inputTokens: 0, outputTokens: 0)
        })
        #expect(output == .empty)
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

    @Test("A duplicate of two earlier entries gives an item line and a round line")
    func duplicateLines() async throws {
        let lines = try await runLines(
            ["3.1.vs.1.1": PairScore(sameAsk: 1.8, opposite: 0), "3.1.vs.2.2": PairScore(sameAsk: 1.6, opposite: 0.3)],
            marks: [dupesItem(1, "make the heading larger")]
        )
        #expect(lines == [
            itemLine(1, "3.1 repeats 1.1 and 2.2 (captures 1 and 2). An earlier paste may have made this change. Check the code, and make the change once."),
            scopedLine(.round, "Same ask: 3.1 repeats 1.1 and 2.2 (captures 1, 2, and 3). Make the change once. Each note is in manifest.md."),
        ])
    }

    @Test("Earlier entries of one capture name that capture once")
    func duplicateLinesOneCapture() async throws {
        let lines = try await runLines(
            ["3.2.vs.1.1": PairScore(sameAsk: 1.5, opposite: 0), "3.2.vs.1.2": PairScore(sameAsk: 1.5, opposite: 0), "3.2.vs.1.note": PairScore(sameAsk: 1.5, opposite: 0)],
            marks: [dupesItem(2, "make the heading larger")]
        )
        #expect(lines == [
            itemLine(2, "3.2 repeats 1.1, 1.2, and the general note of capture 1 (capture 1). An earlier paste may have made this change. Check the code, and make the change once."),
            scopedLine(.round, "Same ask: 3.2 repeats 1.1, 1.2, and the general note of capture 1 (captures 1 and 3). Make the change once. Each note is in manifest.md."),
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

    @Test("A conflict gives a round line and an item line, and it wins over a duplicate")
    func conflictLines() async throws {
        let lines = try await runLines(
            ["3.2.vs.2.1": PairScore(sameAsk: 1.9, opposite: 0.8)],
            marks: [dupesItem(1, "make the heading larger"), dupesItem(2, "make the heading smaller")]
        )
        #expect(lines == [
            scopedLine(.round, "Ask first: 3.2 and 2.1 ask for opposite changes to the same element. Ask the user which one wins before you edit either. 3.2 is newer."),
            itemLine(2, "Ask the user first: 3.2 and 2.1 ask for opposite changes to the same element. Read 2.1 in manifest.md. 3.2 is newer."),
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
            scopedLine(.capture, "The general note of capture 3 repeats 1.1 (capture 1). An earlier paste may have made this change. Check the code, and make the change once."),
            scopedLine(.round, "Same ask: the general note of capture 3 repeats 1.1 (captures 1 and 3). Make the change once. Each note is in manifest.md."),
            scopedLine(.capture, "The general note of capture 3 may overlap with the general note of capture 1. Read the general note of capture 1 in manifest.md. An earlier paste may have done part of it. Check the code before you edit twice."),
            scopedLine(.round, "Ask first: the general note of capture 3 and the general note of capture 2 ask for opposite changes to the same element. Ask the user which one wins before you edit either. The general note of capture 3 is newer."),
            scopedLine(.capture, "Ask the user first: the general note of capture 3 and the general note of capture 2 ask for opposite changes to the same element. Read the general note of capture 2 in manifest.md. The general note of capture 3 is newer."),
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
        #expect(lines.map(\.scope) == [
            .round, .item(badge: 1),
            .item(badge: 2), .round,
            .capture,
        ])
        let prefixes = [
            "Ask first: 3.1 and 2.1",
            "Ask the user first: 3.1 and 2.1",
            "3.2 repeats 1.2",
            "Same ask: 3.2 repeats 1.2",
            "The general note of capture 3 may overlap with 1.1",
        ]
        #expect(lines.count == prefixes.count)
        for (line, prefix) in zip(lines, prefixes) {
            #expect(line.label.hasPrefix(prefix), "\(line.label)")
        }
        #expect(lines.allSatisfy { $0.screenText == nil && $0.file == nil })
        #expect(!lines.contains { $0.label.contains("Heading") })
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
            itemLine(2, "2.2 repeats 1.1 (capture 1). An earlier paste may have made this change. Check the code, and make the change once."),
            scopedLine(.round, "Same ask: 2.2 repeats 1.1 (captures 1 and 2). Make the change once. Each note is in manifest.md."),
            scopedLine(.capture, "Not checked for repeats (timeout): 2.1."),
        ])
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
}
