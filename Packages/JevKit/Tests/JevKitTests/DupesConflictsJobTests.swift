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

/// Both sub-flags on, as a trial with `feature dupesConflicts on` runs the job.
private let dupesBothOn: [FeatureFlag: FlagState] = [.dupesMerge: .on, .dupesConflict: .on]

/// A context for the capture with index `current` of a round that holds
/// `captures`, with the job's sub-flags in `optionModes` (both on by default).
private func dupesContext(
    _ captures: [FeedbackCapture],
    current: Int,
    allowed: JevDataKinds = .reviewerText,
    images: JevImageLoader = dupesImages(),
    optionModes: [FeatureFlag: FlagState] = dupesBothOn,
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
        images: images,
        optionModes: optionModes
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

/// The batches for the capture with index `current`, built as `run` builds
/// them but with `allowed` exactly as given. `run` itself removes `.images`
/// from `allowed` (Drew, 2026-10-24), so the image tests call this instead.
private func dupesBatches(
    _ captures: [FeedbackCapture],
    current: Int,
    allowed: JevDataKinds,
    images: JevImageLoader = dupesImages()
) -> [DupesConflicts.Batch] {
    let newEntries = DupesConflicts.entries(of: captures.first { $0.index == current }!)
    let earlierEntries = captures
        .filter { $0.index < current }
        .sorted { $0.index < $1.index }
        .flatMap { DupesConflicts.entries(of: $0) }
    let candidates = DupesConflicts.candidates(earlierCaptures: earlierEntries, new: newEntries)
    return DupesConflicts.batches(
        new: newEntries.filter { !candidates($0).isEmpty },
        candidates: candidates,
        allowed: allowed,
        images: images
    )
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

    @Test("The job keeps its id and flag, needs screen text, sits at version 3, and its options are its sub-flags")
    func identity() {
        let job = DupesConflictsJob()
        #expect(job.id == "dupesConflicts")
        #expect(job.flag == .dupesConflicts)
        #expect(job.requires == [.screenText])
        #expect(job.version == 3)
        #expect(job.options == [.dupesMerge, .dupesConflict])
        #expect(job.options == FeatureFlag.subFlags(of: job.flag))
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

    @Test("The first capture of a round with one entry sends no request and returns empty")
    func firstCaptureSendsNothing() async throws {
        // One entry on purpose: with two or more, the later entries pair with
        // the earlier ones of their own capture (see the same-capture tests).
        let captures = [dupesCapture(1, marks: [dupesItem(1, "make it bigger")])]
        let log = RequestLog()
        let output = try await DupesConflictsJob().run(dupesContext(captures, current: 1, ask: canned(log: log)))
        #expect(output == .empty)
        #expect(await log.count == 0)
    }

    @Test("A capture with no new entry, or with one new entry and no earlier entry, sends nothing")
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

    @Test("A new entry never pairs with a later capture")
    func neverPairsWithLaterCapture() async throws {
        // Capture 2 holds one entry on purpose, so its only pair is with
        // capture 1. Pairs inside a capture have their own tests.
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "use a darker blue")]),
            dupesCapture(3, marks: [dupesItem(1, "rename the menu")]),
        ]
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: canned(log: log)))
        let requests = await log.requests
        #expect(requests.count == 1)

        let ids = requests.flatMap { $0.questions.map { $0.id.text } }
        #expect(ids.count == 2)
        for id in ids {
            let parsed = DupesConflicts.parse(questionID: id)
            #expect(parsed?.new == "2.1", "\(id)")
            #expect(parsed?.earlier == "1.1", "\(id)")
        }
    }

    @Test("Inside the first capture, items 1.2 and 1.3 and the note pair with the entries before them")
    func pairsInsideOneCapture() async throws {
        let captures = [
            dupesCapture(1, note: "keep the old wording", marks: [
                dupesItem(1, "make the title bigger"),
                dupesItem(2, "remove the border"),
                dupesItem(3, "use a darker blue"),
            ]),
        ]
        let log = RequestLog()
        let output = try await DupesConflictsJob().run(dupesContext(captures, current: 1, ask: canned(log: log)))
        let requests = await log.requests

        // 1.1 has no entry before it, so it sends nothing. The others send one request each.
        #expect(requests.count == 3)
        #expect(Set(requests.flatMap { newIDs(of: $0) }) == ["1.2", "1.3", "1.note"])
        #expect(requests.allSatisfy { newIDs(of: $0).count == 1 })

        var expected = Set<String>()
        let pairs = [
            ("1.2", ["1.1"]),
            ("1.3", ["1.1", "1.2"]),
            ("1.note", ["1.1", "1.2", "1.3"]),
        ]
        for (new, earlier) in pairs {
            for id in earlier {
                expected.insert("\(new).vs.\(id).sameAsk")
                expected.insert("\(new).vs.\(id).opposite")
            }
        }
        let sent = requests.flatMap { $0.questions.map { $0.id.text } }
        #expect(sent.count == 12)
        #expect(Set(sent) == expected)
        #expect(output.lines.isEmpty)
    }

    @Test("A later capture pairs with the earlier capture, then with its own earlier entries, never 2.1 with 2.2")
    func pairsInALaterCapture() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "use a darker blue"), dupesItem(2, "remove the border")]),
        ]
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 2, ask: canned(log: log)))
        let requests = await log.requests
        #expect(requests.count == 2)

        let first = try #require(requestHolding("2.1", in: requests))
        let second = try #require(requestHolding("2.2", in: requests))
        #expect(first.questions.map { $0.id.text } == [
            "2.1.vs.1.1.sameAsk", "2.1.vs.1.1.opposite",
        ])
        #expect(second.questions.map { $0.id.text } == [
            "2.2.vs.1.1.sameAsk", "2.2.vs.1.1.opposite",
            "2.2.vs.2.1.sameAsk", "2.2.vs.2.1.opposite",
        ])
        let sent = requests.flatMap { $0.questions.map { $0.id.text } }
        #expect(!sent.contains { $0.hasPrefix("2.1.vs.2.2") })
    }

    // MARK: Consent

    /// Capture 2 holds one entry (an item by default), so these tests keep
    /// checking pairs across captures. Entries of one capture always share a
    /// source and pair with each other: the same-capture tests cover that.
    private func consentCaptures(
        earlier: (app: String?, window: String?),
        current: (app: String?, window: String?),
        currentMarks: [FeedbackMark],
        currentNote: String?
    ) -> [FeedbackCapture] {
        [
            dupesCapture(1, app: earlier.app, window: earlier.window, marks: [dupesItem(1, "make the title bigger", ocr: "Save")]),
            dupesCapture(2, app: current.app, window: current.window, note: currentNote, marks: currentMarks),
        ]
    }

    /// The requests the job sends through `run`. `run` never sends an image,
    /// even with `.images` allowed.
    private func consentRequests(
        earlier: (app: String?, window: String?) = ("Claude", "Main"),
        current: (app: String?, window: String?) = ("Claude", "Main"),
        allowed: JevDataKinds,
        currentMarks: [FeedbackMark] = [dupesItem(1, "make the title smaller", ocr: "Save changes")],
        currentNote: String? = nil
    ) async throws -> [JevRequest] {
        let captures = consentCaptures(earlier: earlier, current: current, currentMarks: currentMarks, currentNote: currentNote)
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 2, allowed: allowed, ask: canned(log: log)))
        return await log.requests
    }

    /// The requests `DupesConflicts.batches` builds, with `allowed` as given.
    /// The job removes `.images` before it calls `batches`, so the tests of
    /// the image code call `batches` directly.
    private func consentBatchRequests(
        earlier: (app: String?, window: String?) = ("Claude", "Main"),
        current: (app: String?, window: String?) = ("Claude", "Main"),
        allowed: JevDataKinds,
        currentMarks: [FeedbackMark] = [dupesItem(1, "make the title smaller", ocr: "Save changes")],
        currentNote: String? = nil
    ) -> [JevRequest] {
        let captures = consentCaptures(earlier: earlier, current: current, currentMarks: currentMarks, currentNote: currentNote)
        return dupesBatches(captures, current: 2, allowed: allowed).map(\.request)
    }

    @Test("With reviewer text only, a request holds no screen text, app, or crop")
    func reviewerTextOnly() async throws {
        let requests = try await consentRequests(allowed: .reviewerText)
        #expect(requests.count == 1)
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
        #expect(requests.count == 1)
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
    }

    @Test("A general note sends no screen text of its own, but its app name goes")
    func noteSendsAppNameOnly() async throws {
        // Capture 2 is a lone note, so the note's only pair is with capture 1.
        let requests = try await consentRequests(allowed: [.reviewerText, .screenText], currentMarks: [], currentNote: "general ask")
        let note = try #require(requestHolding("2.note", in: requests))
        #expect(requests.count == 1)
        #expect(names(of: newObjects(of: note).first) == ["id", "note", "app"])
    }

    @Test("With all three kinds allowed, run sends no image and no new entry carries a crop")
    func runNeverSendsImages() async throws {
        // Same app and window in both captures, so `batches` would send crops
        // here. The job removes `.images` first (Drew, 2026-10-24).
        let captures = consentCaptures(
            earlier: ("Claude", "Main"),
            current: ("Claude", "Main"),
            currentMarks: [dupesItem(1, "make the title smaller", ocr: "Save changes")],
            currentNote: nil
        )
        let allKinds: JevDataKinds = [.reviewerText, .screenText, .images]

        // The control: the same round, with `.images` left in, does send crops.
        let control = dupesBatches(captures, current: 2, allowed: allKinds).map(\.request)
        #expect(control.count == 1)
        #expect(control.allSatisfy { $0.images.count == 2 })

        // The job must not even load an image.
        let loader = JevImageLoader { _, _, _ in
            Issue.record("The job asked the loader for an image")
            throw ImageFailure()
        }
        let log = RequestLog()
        _ = try await DupesConflictsJob().run(dupesContext(captures, current: 2, allowed: allKinds, images: loader, ask: canned(log: log)))
        let requests = await log.requests
        #expect(requests.count == 1)
        for request in requests {
            #expect(request.images.isEmpty)
            #expect(!request.kinds.contains(.images))
            #expect(request.kinds.contains(.screenText))
            #expect(names(of: request.state) == ["new", "earlier_screen_text"])
            let objects = newObjects(of: request)
            #expect(objects.count == 1)
            for object in objects {
                #expect(!names(of: object).contains("crop"))
            }
        }
    }

    @Test("With images allowed and the same app, crops go for new and earlier entries")
    func imagesSameApp() {
        let requests = consentBatchRequests(earlier: ("Claude", "Inbox"), current: ("Claude", "Main"), allowed: [.reviewerText, .images])
        #expect(requests.count == 1)
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
    func imagesSameWindowTitle() {
        let requests = consentBatchRequests(earlier: ("Mail", "Main"), current: ("Claude", "Main"), allowed: [.reviewerText, .images])
        #expect(requests.count == 1)
        #expect(requests.allSatisfy { $0.images.count == 2 })
    }

    @Test("With different apps and window titles, no image goes")
    func noImagesForDifferentSources() {
        let requests = consentBatchRequests(earlier: ("Mail", "Inbox"), current: ("Claude", "Main"), allowed: [.reviewerText, .screenText, .images])
        #expect(requests.count == 1)
        for request in requests {
            #expect(request.images.isEmpty)
            #expect(!request.kinds.contains(.images))
            #expect(names(of: request.state) == ["new", "earlier_screen_text"])
            #expect(!names(of: newObjects(of: request).first).contains("crop"))
        }
    }

    @Test("A missing name on both sides is not the same source")
    func missingNamesNeverMatch() {
        let allKinds: JevDataKinds = [.reviewerText, .screenText, .images]
        let noNames = consentBatchRequests(earlier: (nil, nil), current: (nil, nil), allowed: allKinds)
        #expect(noNames.count == 1)
        #expect(noNames.allSatisfy { $0.images.isEmpty })

        let differentTitles = consentBatchRequests(earlier: (nil, "Inbox"), current: (nil, "Main"), allowed: allKinds)
        #expect(differentTitles.count == 1)
        #expect(differentTitles.allSatisfy { $0.images.isEmpty })

        // The same non-empty window title still matches when both apps are missing.
        let sameTitle = consentBatchRequests(earlier: (nil, "Main"), current: (nil, "Main"), allowed: allKinds)
        #expect(sameTitle.count == 1)
        #expect(sameTitle.allSatisfy { $0.images.count == 2 })
    }

    @Test("Two entries of one capture are the same source, whatever the app and window names are")
    func sameCaptureIsSameSource() throws {
        func entry(_ capture: Int, _ badge: Int, app: String?, window: String?) -> DupesConflicts.Entry {
            DupesConflicts.Entry(captureIndex: capture, badge: badge, note: "n", app: app, windowTitle: window)
        }
        #expect(entry(1, 1, app: nil, window: nil).sharesSource(with: entry(1, 2, app: nil, window: nil)))
        #expect(entry(1, 1, app: "Mail", window: "Inbox").sharesSource(with: entry(1, 2, app: "Claude", window: "Main")))
        #expect(!entry(1, 1, app: nil, window: nil).sharesSource(with: entry(2, 1, app: nil, window: nil)))

        // With no names at all, the crops still go for a pair inside one
        // capture, and only with images allowed.
        let captures = [
            dupesCapture(1, app: nil, window: nil, marks: [dupesItem(1, "make the title bigger"), dupesItem(2, "make the title smaller")]),
        ]
        let imageRequests = dupesBatches(captures, current: 1, allowed: [.reviewerText, .images]).map(\.request)
        let request = try #require(imageRequests.first)
        #expect(imageRequests.count == 1)
        #expect(newIDs(of: request) == ["1.2"])
        #expect(names(of: request.state) == ["new", "earlier_crops"])
        #expect(names(of: newObjects(of: request).first) == ["id", "note", "crop"])
        #expect(names(of: field("earlier_crops", in: request.state)) == ["e1_1"])
        #expect(request.images.count == 2)

        let textRequests = dupesBatches(captures, current: 1, allowed: .reviewerText).map(\.request)
        let plain = try #require(textRequests.first)
        #expect(plain.images.isEmpty)
        #expect(names(of: plain.state) == ["new"])
        #expect(names(of: newObjects(of: plain).first) == ["id", "note"])
    }

    @Test("A failed image load leaves that image out and does not fail the job")
    func imageLoadFailure() throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "make the title smaller")]),
        ]

        let firstRequests = dupesBatches(
            captures, current: 2, allowed: [.reviewerText, .images],
            images: dupesImages(failing: [1])
        ).map(\.request)
        let first = try #require(firstRequests.first)
        #expect(names(of: first.state) == ["new"])
        #expect(names(of: newObjects(of: first).first) == ["id", "note", "crop"])
        #expect(first.questions.allSatisfy { !(questionText($0.question) ?? "").contains("Crop for earlier_note") })

        let secondRequests = dupesBatches(
            captures, current: 2, allowed: [.reviewerText, .images],
            images: dupesImages(failing: [2])
        ).map(\.request)
        let second = try #require(secondRequests.first)
        #expect(names(of: newObjects(of: second).first) == ["id", "note"])
        #expect(second.questions.allSatisfy { !(questionText($0.question) ?? "").contains("Crop for the new note") })
    }

    // MARK: Earlier crop cap

    @Test("At most 6 earlier crops go in a request, newest first")
    func earlierCropCap() throws {
        let captures = [
            dupesCapture(1, marks: (1...5).map { dupesItem($0, "first capture ask \($0)") }),
            dupesCapture(2, marks: (1...3).map { dupesItem($0, "second capture ask \($0)") }),
            dupesCapture(3, marks: [dupesItem(1, "make it bigger")]),
        ]
        let requests = dupesBatches(captures, current: 3, allowed: [.reviewerText, .images]).map(\.request)
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
        // 3 new entries and 5 earlier entries make 15 pairs. The 3 pairs inside
        // capture 3 (3.2 vs 3.1, 3.note vs 3.1, 3.note vs 3.2) make 18 pairs
        // and 36 questions.
        #expect(all.count == 36)
        #expect(Set(all).count == 36)
        #expect(all.contains("3.note.vs.2.note.opposite"))
        #expect(all.contains("3.1.vs.1.note.sameAsk"))
        #expect(all.contains("3.2.vs.3.1.sameAsk"))
        #expect(all.contains("3.note.vs.3.2.opposite"))
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

    @Test("17 new entries make 8 requests, and every pair's two questions appear once, also inside the capture")
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

        // Each new entry pairs with the 2 entries of capture 1, then with the
        // new entries before it: 34 pairs across captures and 0 + 1 + ... + 16
        // = 136 pairs inside capture 2.
        let new = (1...16).map { "2.\($0)" } + ["2.note"]
        let earlier = ["1.1", "1.2"]
        var expected = Set<String>()
        for (position, n) in new.enumerated() {
            for e in earlier + new[..<position] {
                expected.insert("\(n).vs.\(e).sameAsk")
                expected.insert("\(n).vs.\(e).opposite")
            }
        }
        let sent = requests.flatMap { $0.questions.map { $0.id.text } }
        #expect(sent.count == 340)
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

    /// Runs the job on the last capture of `captures` and returns its lines.
    private func runRound(_ captures: [FeedbackCapture], _ table: [String: PairScore]) async throws -> [JevRefinedLine] {
        let last = try #require(captures.last)
        return try await DupesConflictsJob().run(dupesContext(captures, current: last.index, ask: canned(table))).lines
    }

    @Test("Inside one capture, a duplicate and an overlap leave out the earlier-paste sentence")
    func lineTextInsideOneCapture() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger"), dupesItem(2, "make the heading larger"), dupesItem(3, "enlarge the title")]),
        ]
        let lines = try await runRound(captures, [
            "1.2.vs.1.1": PairScore(sameAsk: 1.0, opposite: 0),
            "1.3.vs.1.1": PairScore(sameAsk: 1.8, opposite: 0),
        ])
        #expect(lines == [
            itemLine(2, "1.2 may overlap with 1.1. Read 1.1 in manifest.md. Check the code before you edit twice."),
            scopedLine(.round, "Same ask: 1.3 repeats 1.1 (capture 1). Make the change once. Each note is in manifest.md."),
        ])
    }

    @Test("Inside one capture, an overlap with two entries says to read them")
    func overlapOfTwoInsideOneCapture() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger"), dupesItem(2, "make the heading larger"), dupesItem(3, "enlarge the title")]),
        ]
        let lines = try await runRound(captures, [
            "1.3.vs.1.1": PairScore(sameAsk: 1.0, opposite: 0),
            "1.3.vs.1.2": PairScore(sameAsk: 0.5, opposite: 0),
        ])
        #expect(lines == [
            itemLine(3, "1.3 may overlap with 1.1 and 1.2. Read them in manifest.md. Check the code before you edit twice."),
        ])
    }

    @Test("Inside one capture, a conflict gives the normal conflict line")
    func conflictInsideOneCapture() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger"), dupesItem(2, "make the title smaller")]),
        ]
        let lines = try await runRound(captures, ["1.2.vs.1.1": PairScore(sameAsk: 1.9, opposite: 0.8)])
        #expect(lines == [
            scopedLine(.round, "Ask first: 1.2 and 1.1 ask for opposite changes to the same element. Read both in manifest.md. Ask the user which one wins before you edit either. 1.2 is newer."),
        ])
    }

    @Test("A line that names one earlier-capture entry and one same-capture entry keeps the earlier-paste sentence")
    func lineTextMixedCaptures() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "make the heading larger"), dupesItem(2, "enlarge the title")]),
        ]
        let duplicate = try await runRound(captures, [
            "2.2.vs.1.1": PairScore(sameAsk: 1.7, opposite: 0),
            "2.2.vs.2.1": PairScore(sameAsk: 1.6, opposite: 0),
        ])
        #expect(duplicate == [
            scopedLine(.round, "Same ask: 2.2 repeats 1.1 and 2.1 (captures 1 and 2). An earlier paste may have made this change. Check the code, and make the change once. Each note is in manifest.md."),
        ])

        let overlap = try await runRound(captures, [
            "2.2.vs.1.1": PairScore(sameAsk: 1.0, opposite: 0),
            "2.2.vs.2.1": PairScore(sameAsk: 0.8, opposite: 0),
        ])
        #expect(overlap == [
            itemLine(2, "2.2 may overlap with 1.1 and 2.1. Read them in manifest.md. An earlier paste may have done part of it. Check the code before you edit twice."),
        ])
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
    func imageLimit() throws {
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
        let requests = dupesBatches(captures, current: 2, allowed: [.reviewerText, .images], images: images).map(\.request)
        #expect(requests.count == 8)
        for request in requests {
            #expect(request.images.count <= JevRequestEncoder.maxImages)
            _ = try JevRequestEncoder.encode(request)
        }
    }
}

// MARK: Sub-flags

/// The question kinds that the requests in `log` ask, over all their pairs.
private func askedKinds(_ requests: [JevRequest]) -> Set<DupesConflicts.QuestionKind> {
    Set(requests.flatMap(\.questions).compactMap { DupesConflicts.parse(questionID: $0.id.text)?.kind })
}

@Suite("Duplicates and conflicts: sub-flags")
struct DupesConflictsSubFlagTests {
    /// Capture 3 holds a duplicate (3.1 and 1.1), an overlap (3.2 and 1.2),
    /// and a conflict (3.2 and 2.1) with earlier entries.
    private static let captures = [
        dupesCapture(1, marks: [dupesItem(1, "make the title bigger"), dupesItem(2, "remove the border")]),
        dupesCapture(2, marks: [dupesItem(1, "make the title smaller")]),
        dupesCapture(3, marks: [dupesItem(1, "make the heading larger"), dupesItem(2, "make the heading smaller"), dupesItem(3, "drop the frame")]),
    ]
    private static let table = [
        "3.1.vs.1.1": PairScore(sameAsk: 1.8, opposite: 0),
        "3.2.vs.1.2": PairScore(sameAsk: 1.0, opposite: 0),
        // Jev also rates this pair as a repeat. The conflict wins.
        "3.2.vs.2.1": PairScore(sameAsk: 1.9, opposite: 0.8),
    ]

    private static let duplicateLine = scopedLine(.round, "Same ask: 3.1 repeats 1.1 (captures 1 and 3). An earlier paste may have made this change. Check the code, and make the change once. Each note is in manifest.md.")
    private static let overlapLine = itemLine(2, "3.2 may overlap with 1.2. Read 1.2 in manifest.md. An earlier paste may have done part of it. Check the code before you edit twice.")
    private static let conflictLine = scopedLine(.round, "Ask first: 3.2 and 2.1 ask for opposite changes to the same element. Read both in manifest.md. Ask the user which one wins before you edit either. 3.2 is newer.")

    private static let duplicate: JevSummaryValue = .fields(["pair": "3.1.vs.1.1", "outcome": "duplicate"])
    private static let overlap: JevSummaryValue = .fields(["pair": "3.2.vs.1.2", "outcome": "overlap"])
    private static let conflict: JevSummaryValue = .fields(["pair": "3.2.vs.2.1", "outcome": "conflict"])

    private static func summary(_ flagged: [JevSummaryValue]) -> [JevSummaryField] {
        [JevSummaryField(key: "flagged", value: .array(flagged)), JevSummaryField(key: "notChecked", value: .array([]))]
    }

    private static func run(_ modes: [FeatureFlag: FlagState], log: RequestLog = RequestLog()) async throws -> JevJobOutput {
        try await DupesConflictsJob().run(dupesContext(captures, current: 3, optionModes: modes, ask: canned(table, log: log)))
    }

    @Test("Both sub-flags off, or unset: no request and an empty output")
    func bothOff() async throws {
        for modes: [FeatureFlag: FlagState] in [[:], [.dupesMerge: .off, .dupesConflict: .off]] {
            let log = RequestLog()
            let output = try await Self.run(modes, log: log)
            #expect(await log.count == 0, "\(modes)")
            #expect(output == .empty, "\(modes)")
        }
    }

    @Test("Both on: the same lines as before the sub-flags, and every pair in the summary")
    func bothOn() async throws {
        let output = try await Self.run([.dupesMerge: .on, .dupesConflict: .on])
        #expect(output.lines == [Self.duplicateLine, Self.overlapLine, Self.conflictLine])
        #expect(output.summary == Self.summary([Self.duplicate, Self.overlap, Self.conflict]))
    }

    @Test("dupesMerge on alone: the Same ask and overlap lines, both questions asked, and no conflict line")
    func mergeOnly() async throws {
        let log = RequestLog()
        let output = try await Self.run([.dupesMerge: .on], log: log)
        #expect(output.lines == [Self.duplicateLine, Self.overlapLine])
        // The conflict pair 3.2 and 2.1 reads as a conflict, so it adds neither line nor summary entry.
        #expect(output.summary == Self.summary([Self.duplicate, Self.overlap]))
        #expect(askedKinds(await log.requests) == [.sameAsk, .opposite])
    }

    @Test("dupesConflict on alone: the Ask first line, only the opposite question asked, and no merge line")
    func conflictOnly() async throws {
        let log = RequestLog()
        let output = try await Self.run([.dupesConflict: .on], log: log)
        #expect(output.lines == [Self.conflictLine])
        #expect(output.summary == Self.summary([Self.conflict]))
        let requests = await log.requests
        #expect(requests.count == 3)
        #expect(askedKinds(requests) == [.opposite])
    }

    @Test("Guard: with dupesMerge on and dupesConflict off, a pair that is a conflict gets no Same ask line and no Ask first line")
    func conflictNeverMerges() async throws {
        let captures = [
            dupesCapture(1, marks: [dupesItem(1, "make the title bigger")]),
            dupesCapture(2, marks: [dupesItem(1, "make the title smaller")]),
        ]
        // Jev rates the pair as the same ask and as opposite asks.
        let both = ["2.1.vs.1.1": PairScore(sameAsk: 1.9, opposite: 0.9)]
        let ask = { (modes: [FeatureFlag: FlagState], table: [String: PairScore], log: RequestLog) in
            try await DupesConflictsJob().run(dupesContext(captures, current: 2, optionModes: modes, ask: canned(table, log: log)))
        }

        let log = RequestLog()
        let guarded = try await ask([.dupesMerge: .on], both, log)
        // One request, with both questions for the pair: the guard asks `opposite` too.
        let request = try #require(await log.requests.first)
        #expect(await log.count == 1)
        #expect(request.questions.map(\.id.text) == ["2.1.vs.1.1.sameAsk", "2.1.vs.1.1.opposite"])
        #expect(guarded.lines.isEmpty, "a conflict got a merge line")
        #expect(guarded.summary == Self.summary([]))

        // Merge in shadow with conflict off hides it the same way.
        let shadow = try await ask([.dupesMerge: .shadow], both, RequestLog())
        #expect(shadow.lines.isEmpty)
        #expect(shadow.summary == Self.summary([]))

        // With conflict on too, the pair is a conflict and only the Ask first line shows.
        let conflictLine = scopedLine(.round, "Ask first: 2.1 and 1.1 ask for opposite changes to the same element. Read both in manifest.md. Ask the user which one wins before you edit either. 2.1 is newer.")
        let bothOn = try await ask([.dupesMerge: .on, .dupesConflict: .on], both, RequestLog())
        #expect(bothOn.lines == [conflictLine])

        // The same pair with a low opposite is a plain repeat, so the guard changes only conflicts.
        let repeated = try await ask([.dupesMerge: .on], ["2.1.vs.1.1": PairScore(sameAsk: 1.9, opposite: 0.5)], RequestLog())
        #expect(repeated.lines == [scopedLine(.round, "Same ask: 2.1 repeats 1.1 (captures 1 and 2). An earlier paste may have made this change. Check the code, and make the change once. Each note is in manifest.md.")])
    }

    @Test("A part in shadow records its pairs in the summary and writes no line")
    func shadowParts() async throws {
        let mergeShadow = try await Self.run([.dupesMerge: .shadow, .dupesConflict: .on])
        #expect(mergeShadow.lines == [Self.conflictLine])
        #expect(mergeShadow.summary == Self.summary([Self.duplicate, Self.overlap, Self.conflict]))

        let conflictShadow = try await Self.run([.dupesMerge: .on, .dupesConflict: .shadow])
        // The conflict pair stays out of the merge lines, and is recorded as a conflict.
        #expect(conflictShadow.lines == [Self.duplicateLine, Self.overlapLine])
        #expect(conflictShadow.summary == Self.summary([Self.duplicate, Self.overlap, Self.conflict]))

        let bothShadow = try await Self.run([.dupesMerge: .shadow, .dupesConflict: .shadow])
        #expect(bothShadow.lines.isEmpty)
        #expect(bothShadow.summary == Self.summary([Self.duplicate, Self.overlap, Self.conflict]))
    }

    @Test("The Not checked line shows only when a part writes lines, and the summary always names the entry")
    func notCheckedLine() async throws {
        let failing = failing(["3.2": JevError(.timeout)], otherwise: canned(Self.table))
        let notChecked = JevSummaryField(key: "notChecked", value: .array([.fields(["entry": "3.2", "reason": "timeout"])]))
        let line = scopedLine(.capture, "Not checked for repeats (timeout): 3.2.")

        for modes: [FeatureFlag: FlagState] in [[.dupesMerge: .on], [.dupesConflict: .on]] {
            let output = try await DupesConflictsJob().run(dupesContext(Self.captures, current: 3, optionModes: modes, ask: failing))
            #expect(output.lines.contains(line), "\(modes)")
            #expect(output.summary.last == notChecked, "\(modes)")
        }
        let shadow = try await DupesConflictsJob().run(dupesContext(Self.captures, current: 3, optionModes: [.dupesMerge: .shadow, .dupesConflict: .shadow], ask: failing))
        #expect(shadow.lines.isEmpty)
        #expect(shadow.summary.last == notChecked)
    }

    @Test("The questions of a pair do not change with the sub-flags: sameAsk and opposite are the same questions")
    func questionsAreTheSame() async throws {
        let full = RequestLog()
        _ = try await Self.run([.dupesMerge: .on, .dupesConflict: .on], log: full)
        let onlyOpposite = RequestLog()
        _ = try await Self.run([.dupesConflict: .on], log: onlyOpposite)

        let fullRequests = await full.requests
        let oppositeRequests = await onlyOpposite.requests
        #expect(fullRequests.count == oppositeRequests.count)
        for (whole, part) in zip(fullRequests, oppositeRequests) {
            // JevValue is not Equatable, so compare the printed state.
            #expect(String(describing: whole.state) == String(describing: part.state))
            // The conflict-only request is the full request without its sameAsk questions.
            let kept = whole.questions.filter { $0.id.text.hasSuffix(".opposite") }
            #expect(kept.map(\.id.text) == part.questions.map(\.id.text))
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
        // The sub-flags are on, and the runner caps them at the shadow parent.
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .dupesConflicts: .shadow, .dupesMerge: .on, .dupesConflict: .on, .jevSendScreenText: .on]
        let runner = makeRunner(bundle, jobs: [DupesConflictsJob()], flags: flags, transport: transport)
        await runCapture(runner, bundle, capture: 2)

        #expect(await transport.count == 1)
        let record = try #require(try bundle.record(2))
        #expect(record.job == "dupesConflicts" && record.jobVersion == 3 && record.mode == "shadow" && record.status == .done)
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
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .dupesConflicts: .on, .dupesMerge: .on, .dupesConflict: .on, .jevSendScreenText: .on]
        let runner = makeRunner(bundle, jobs: [DupesConflictsJob()], flags: flags, transport: transport)
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

        // Drew's notes go out. The app name may go too, because screen text is
        // allowed. The mark has no screen text of its own, and the capture's
        // OCR text never goes. No image goes: the request is plain JSON.
        let sentRequest = try #require(await transport.requests.first)
        let body = try #require(sentRequest.httpBody)
        let sent = String(decoding: body, as: UTF8.self)
        #expect(sent.contains("make it brighter"))
        #expect(!sent.contains("Copy Last Capture Prompt"))
        let contentType = try #require(sentRequest.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("application/json"), "\(contentType)")
    }

    @Test("In the runner, dupesConflict alone asks only opposite, and dupesMerge alone asks both and hides a conflict")
    func subFlagsInTheRunner() async throws {
        let oppositeOnly = #"{"model":"\#(JevEndpoint.model)","answers":{"2.1.vs.1.1.opposite":{"type":"noul","noul":0.9}},"usage":{"input_tokens":40,"output_tokens":1}}"#
        let conflictBundle = try await Bundle.make(captures: 2)
        let conflictTransport = StubTransport(fallback: jsonResponse(oppositeOnly))
        let conflictFlags: [FeatureFlag: FlagState] = [.jevBase: .on, .dupesConflicts: .on, .dupesConflict: .on, .jevSendScreenText: .on]
        await runCapture(makeRunner(conflictBundle, jobs: [DupesConflictsJob()], flags: conflictFlags, transport: conflictTransport), conflictBundle, capture: 2)

        let conflictBody = String(decoding: try #require(await conflictTransport.requests.first?.httpBody), as: UTF8.self)
        #expect(conflictBody.contains("2.1.vs.1.1.opposite") && !conflictBody.contains("sameAsk"))
        let conflictRecord = try #require(try conflictBundle.record(2))
        #expect(conflictRecord.status == .done && conflictRecord.answers.map(\.id) == ["2.1.vs.1.1.opposite"])
        #expect(conflictRecord.lines.map(\.label).contains { $0.hasPrefix("Ask first: 2.1 and 1.1") })

        // Merge alone: both questions go out, Jev rates the pair as a repeat and as opposite asks.
        let mergeBundle = try await Bundle.make(captures: 2)
        let mergeTransport = StubTransport(fallback: jsonResponse(pairBody(sameAsk: 1.8, opposite: 0.9)))
        let mergeFlags: [FeatureFlag: FlagState] = [.jevBase: .on, .dupesConflicts: .on, .dupesMerge: .on, .jevSendScreenText: .on]
        await runCapture(makeRunner(mergeBundle, jobs: [DupesConflictsJob()], flags: mergeFlags, transport: mergeTransport), mergeBundle, capture: 2)

        let mergeBody = String(decoding: try #require(await mergeTransport.requests.first?.httpBody), as: UTF8.self)
        #expect(mergeBody.contains("2.1.vs.1.1.sameAsk") && mergeBody.contains("2.1.vs.1.1.opposite"))
        let mergeRecord = try #require(try mergeBundle.record(2))
        #expect(mergeRecord.status == .done && mergeRecord.lines.isEmpty, "a conflict got a merge line")
        let refined = try mergeBundle.exists("refined.md") ? mergeBundle.text("refined.md") : ""
        #expect(!refined.contains("Same ask") && !refined.contains("Ask first"))
    }

    @Test("Without screen text consent, the job is skipped with reason consent and sends nothing")
    func skippedWithoutScreenTextConsent() async throws {
        let bundle = try await Bundle.make(captures: 2)
        let transport = StubTransport(fallback: jsonResponse(pairBody(sameAsk: 1.8, opposite: 0.05)))
        let key = StubKeyProvider()
        let runner = makeRunner(bundle, jobs: [DupesConflictsJob()], flags: [.jevBase: .on, .dupesConflicts: .on], transport: transport, key: key)
        await runCapture(runner, bundle, capture: 2)

        #expect(await transport.count == 0)
        #expect(await key.reads == 0)
        let record = try #require(try bundle.record(2))
        #expect(record.job == "dupesConflicts")
        #expect(record.status == .skipped && record.reason == .consent)
    }
}
