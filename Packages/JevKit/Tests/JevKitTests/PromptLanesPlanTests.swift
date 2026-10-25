import FeedbackKit
import Foundation
import Testing
@testable import JevKit

// Made-up notes only: the repository is public.

// MARK: - Fixtures

/// A capture with one counter mark per entry. A nil note is an item with no
/// instruction.
private func makeCapture(_ index: Int, _ notes: [(badge: Int, note: String?)]) -> FeedbackCapture {
    FeedbackCapture(
        index: index,
        imageFile: "0900-window-\(index).png",
        cleanImageFile: "0900-window-\(index)-clean.png",
        size: PixelSize(width: 800, height: 600),
        capturedAt: Date(timeIntervalSince1970: 1_792_000_000 + Double(index * 60)),
        marks: notes.map { entry in
            FeedbackMark(kind: .counter, badge: entry.badge, box: FeedbackBox(x1: 10, y1: 10, x2: 40, y2: 40), instruction: entry.note)
        }
    )
}

private func makeRound(_ captures: [FeedbackCapture]) -> FeedbackRound {
    FeedbackRound(name: "lanes", slug: "lanes", folderName: "2026-10-24-0900-lanes", startedAt: Date(timeIntervalSince1970: 1_792_000_000), captures: captures)
}

/// The summary the job writes for a rated item.
private func rated(_ lane: JevCodeText, _ severity: PromptLanes.Severity, _ size: PromptLanes.Size) -> JevSummaryValue {
    .fields(["lane": .code(lane), "severity": .number(Double(severity.rawValue)), "size": .number(Double(size.rawValue))])
}

private let askFirstValue: JevSummaryValue = .fields(["lane": "askFirst"])
private let notRatedValue: JevSummaryValue = .fields(["lane": "notRated"])

/// One promptLanes record for one capture. The defaults make a good record.
private func record(
    job: String = PromptLanesJob().id,
    version: Int = PromptLanesJob().version,
    mode: String = "shadow",
    status: JevJobRecord.Status = .done,
    summary: JevSummaryValue?
) -> JevJobRecord {
    JevJobRecord(
        job: job, jobVersion: version, mode: mode, status: status, reason: status == .done ? nil : .timeout, model: JevEndpoint.model,
        startedAt: Date(timeIntervalSince1970: 0), durationMs: 1, requests: 1, retries: 0, inputTokens: 1,
        requestIDs: [], answers: [], lines: [], files: [], summary: summary
    )
}

private func makeFile(_ records: [Int: JevJobRecord]) -> JevRecordFile {
    JevRecordFile(captures: records.keys.sorted().map { JevCaptureRecord(capture: $0, jobs: [records[$0]!]) })
}

private func ids(_ entries: [PromptLanes.Entry]) -> [String] {
    entries.map(\.item)
}

/// Every id of every filled and empty item in the round.
private func allItemIDs(_ round: FeedbackRound) -> [String] {
    round.captures.flatMap { capture in capture.badgeNumbers.sorted().map { "\(capture.index).\($0)" } }
}

// MARK: - The plan

@Suite("Prompt lanes plan: lanes and order")
struct PromptLanesPlanTests {
    @Test("Every item appears exactly once, in a lane or on the Ask first line")
    func everyItemOnce() throws {
        let round = makeRound([
            makeCapture(1, [(1, "note one"), (2, nil), (3, "note three")]),
            makeCapture(2, [(1, "note four"), (2, "  \n "), (4, "note five")]),
            makeCapture(3, [(1, "note six")]),
        ])
        let file = makeFile([
            1: record(summary: .fields(["1.1": rated("A", .nit, .oneLine), "1.2": askFirstValue, "1.3": rated("B", .bug, .severalFiles)])),
            2: record(summary: .fields(["2.1": rated("B", .blocker, .manyFiles), "2.2": askFirstValue, "2.4": notRatedValue])),
            // Capture 3 has no record.
        ])
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        let placed = ids(plan.laneA) + ids(plan.laneB) + plan.askFirst
        #expect(placed.sorted() == allItemIDs(round).sorted())
        #expect(Set(placed).count == placed.count, "an item appears twice")
        #expect(plan.askFirst == ["1.2", "2.2"])
    }

    @Test("Order is severity, then capture, then badge")
    func orderRule() throws {
        let round = makeRound([
            makeCapture(1, [(1, "note"), (2, "note")]),
            makeCapture(2, [(1, "note")]),
            makeCapture(3, [(1, "note")]),
        ])
        let file = makeFile([
            1: record(summary: .fields(["1.1": rated("B", .polish, .severalFiles), "1.2": rated("B", .bug, .severalFiles)])),
            2: record(summary: .fields(["2.1": rated("B", .polish, .manyFiles)])),
            3: record(summary: .fields(["3.1": rated("B", .blocker, .manyFiles)])),
        ])
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(ids(plan.laneB) == ["3.1", "1.2", "1.1", "2.1"])
        #expect(plan.laneA.isEmpty)
    }

    @Test("Badges of one capture and one severity stay in badge order")
    func badgeOrder() throws {
        let round = makeRound([makeCapture(1, [(3, "note"), (1, "note"), (2, "note")])])
        let file = makeFile([1: record(summary: .fields(["1.1": rated("B", .bug, .oneFile), "1.2": rated("B", .bug, .oneFile), "1.3": rated("B", .bug, .oneFile)]))])
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(ids(plan.laneB) == ["1.1", "1.2", "1.3"])
    }

    @Test("Lane A and lane B are sorted by the same rule, and each rated entry keeps its levels")
    func lanesAndLevels() throws {
        let round = makeRound([makeCapture(1, [(1, "note"), (2, "note"), (3, "note"), (4, "note")])])
        let file = makeFile([1: record(summary: .fields([
            "1.1": rated("A", .nit, .oneLine),
            "1.2": rated("A", .polish, .oneFile),
            "1.3": rated("B", .bug, .severalFiles),
            "1.4": rated("B", .blocker, .manyFiles),
        ]))])
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(plan.laneA == [
            PromptLanes.Entry(item: "1.2", severity: .polish, size: .oneFile),
            PromptLanes.Entry(item: "1.1", severity: .nit, size: .oneLine),
        ])
        #expect(plan.laneB == [
            PromptLanes.Entry(item: "1.4", severity: .blocker, size: .manyFiles),
            PromptLanes.Entry(item: "1.3", severity: .bug, size: .severalFiles),
        ])
    }

    @Test("Not rated items come last in lane B, in capture order")
    func notRatedLast() throws {
        let round = makeRound([
            makeCapture(1, [(1, "note")]),
            makeCapture(2, [(1, "note"), (2, "note")]),
            makeCapture(3, [(1, "note")]),
            makeCapture(4, [(1, "note")]),
        ])
        let file = makeFile([
            // A not rated item in capture 1 still sorts after the rated ones.
            1: record(summary: .fields(["1.1": notRatedValue])),
            2: record(summary: .fields(["2.1": notRatedValue, "2.2": rated("B", .nit, .manyFiles)])),
            3: record(summary: .fields(["3.1": rated("B", .bug, .severalFiles)])),
            4: record(summary: .fields(["4.1": notRatedValue])),
        ])
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(ids(plan.laneB) == ["3.1", "2.2", "1.1", "2.1", "4.1"])
        for entry in plan.laneB.suffix(3) {
            #expect(entry.severity == nil && entry.size == nil, "\(entry.item) is rated")
        }
    }

    @Test("A failed record, a missing record, and another job version make not rated items")
    func unusableRecords() throws {
        let round = makeRound([
            makeCapture(1, [(1, "note"), (2, nil)]),
            makeCapture(2, [(1, "note"), (2, nil)]),
            makeCapture(3, [(1, "note"), (2, nil)]),
            makeCapture(4, [(1, "note"), (2, nil)]),
            makeCapture(5, [(1, "note")]),
        ])
        let good = rated("B", .bug, .oneFile)
        let file = makeFile([
            1: record(status: .notRefined, summary: .fields(["1.1": good])),
            // Capture 2 has no record.
            3: record(version: PromptLanesJob().version + 1, summary: .fields(["3.1": good])),
            4: record(job: "noteCoach", summary: .fields(["4.1": good])),
            5: record(summary: .fields(["5.1": good])),
        ])
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(plan.laneB == [
            PromptLanes.Entry(item: "5.1", severity: .bug, size: .oneFile),
            PromptLanes.Entry(item: "1.1"),
            PromptLanes.Entry(item: "2.1"),
            PromptLanes.Entry(item: "3.1"),
            PromptLanes.Entry(item: "4.1"),
        ])
        // An empty note goes to Ask first, whatever the capture's record says.
        #expect(plan.askFirst == ["1.2", "2.2", "3.2", "4.2"])
    }

    @Test("A skipped record counts as unusable too")
    func skippedRecord() throws {
        let round = makeRound([makeCapture(1, [(1, "note")]), makeCapture(2, [(1, "note")])])
        let file = makeFile([
            1: record(status: .skipped, summary: .fields(["1.1": rated("A", .nit, .oneLine)])),
            2: record(summary: .fields(["2.1": rated("B", .bug, .oneFile)])),
        ])
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(plan.laneA.isEmpty)
        #expect(ids(plan.laneB) == ["2.1", "1.1"])
    }

    @Test("Shadow and on records both count")
    func shadowAndOn() throws {
        let round = makeRound([makeCapture(1, [(1, "note")]), makeCapture(2, [(1, "note")])])
        let file = makeFile([
            1: record(mode: "shadow", summary: .fields(["1.1": rated("A", .polish, .oneLine)])),
            2: record(mode: "on", summary: .fields(["2.1": rated("B", .bug, .oneFile)])),
        ])
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(ids(plan.laneA) == ["1.1"])
        #expect(ids(plan.laneB) == ["2.1"])
    }

    @Test("A rated item needs a valid lane and valid levels, else it is not rated")
    func invalidSummaries() throws {
        let round = makeRound([makeCapture(1, [(1, "n"), (2, "n"), (3, "n"), (4, "n"), (5, "n"), (6, "n"), (7, "n")])])
        let good = rated("B", .bug, .oneFile)
        let file = makeFile([1: record(summary: .fields([
            "1.1": good,
            "1.2": .fields(["lane": "C", "severity": 1, "size": 1]),
            "1.3": .fields(["lane": "A", "severity": 4, "size": 1]),
            "1.4": .fields(["lane": "A", "severity": 1, "size": -1]),
            "1.5": .fields(["lane": "A", "severity": 1.5, "size": 1]),
            "1.6": .fields(["lane": "A", "severity": 1]),
            // The note is filled now, so the stale askFirst label does not apply.
            "1.7": askFirstValue,
        ]))])
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(plan.laneA.isEmpty)
        #expect(plan.laneB == [PromptLanes.Entry(item: "1.1", severity: .bug, size: .oneFile)]
            + ["1.2", "1.3", "1.4", "1.5", "1.6", "1.7"].map { PromptLanes.Entry(item: $0) })
        #expect(plan.askFirst.isEmpty)
    }

    @Test("A summary that is not an object, or has no field for the item, gives not rated")
    func oddSummaries() throws {
        let round = makeRound([makeCapture(1, [(1, "n")]), makeCapture(2, [(1, "n")]), makeCapture(3, [(1, "n")]), makeCapture(4, [(1, "n")])])
        let file = makeFile([
            1: record(summary: nil),
            2: record(summary: .number(3)),
            3: record(summary: .fields(["3.9": rated("A", .nit, .oneLine)])),
            4: record(summary: .fields(["4.1": rated("A", .bug, .oneFile)])),
        ])
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(ids(plan.laneA) == ["4.1"])
        #expect(ids(plan.laneB) == ["1.1", "2.1", "3.1"])
    }

    @Test("No rated item gives nil")
    func noRatedItem() {
        // Every note is empty.
        let empty = makeRound([makeCapture(1, [(1, nil), (2, "   ")])])
        #expect(PromptLanesPlan.plan(round: empty, file: makeFile([1: record(summary: .fields(["1.1": askFirstValue, "1.2": askFirstValue]))])) == nil)
        #expect(PromptLanesPlan.plan(round: empty, file: JevRecordFile()) == nil)

        // Every record failed, or none exists.
        let filled = makeRound([makeCapture(1, [(1, "note")]), makeCapture(2, [(1, "note")])])
        let failed = makeFile([1: record(status: .notRefined, summary: nil), 2: record(status: .notRefined, summary: nil)])
        #expect(PromptLanesPlan.plan(round: filled, file: failed) == nil)
        #expect(PromptLanesPlan.plan(round: filled, file: JevRecordFile()) == nil)

        // Every rated label is not rated.
        let unrated = makeFile([1: record(summary: .fields(["1.1": notRatedValue])), 2: record(summary: .fields(["2.1": notRatedValue]))])
        #expect(PromptLanesPlan.plan(round: filled, file: unrated) == nil)

        // A round with no captures.
        #expect(PromptLanesPlan.plan(round: makeRound([]), file: JevRecordFile()) == nil)
    }

    @Test("One rated item among empty notes gives a plan with an Ask first line")
    func oneRatedItem() throws {
        let round = makeRound([makeCapture(1, [(1, "note"), (2, nil)])])
        let file = makeFile([1: record(summary: .fields(["1.1": rated("A", .polish, .oneLine), "1.2": askFirstValue]))])
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(plan == PromptLanes(laneA: [PromptLanes.Entry(item: "1.1", severity: .polish, size: .oneLine)], laneB: [], askFirst: ["1.2"]))
    }

    @Test("The plan follows capture index, not the order of the file")
    func fileOrderDoesNotMatter() throws {
        let round = makeRound([makeCapture(1, [(1, "n")]), makeCapture(2, [(1, "n")])])
        let one = JevCaptureRecord(capture: 1, jobs: [record(summary: .fields(["1.1": rated("B", .bug, .oneFile)]))])
        let two = JevCaptureRecord(capture: 2, jobs: [record(summary: .fields(["2.1": rated("B", .bug, .oneFile)]))])
        var forward = JevRecordFile()
        forward.captures = [one, two]
        var backward = JevRecordFile()
        backward.captures = [two, one]
        #expect(PromptLanesPlan.plan(round: round, file: forward) == PromptLanesPlan.plan(round: round, file: backward))
    }

    @Test("The plan reads the record of the job, even when the capture holds other jobs first")
    func otherJobsInTheCapture() throws {
        let round = makeRound([makeCapture(1, [(1, "n")])])
        var file = JevRecordFile()
        file.captures = [JevCaptureRecord(capture: 1, jobs: [
            record(job: "noteCoach", summary: .fields(["1.1": rated("A", .nit, .oneLine)])),
            record(summary: .fields(["1.1": rated("B", .blocker, .manyFiles)])),
        ])]
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(plan.laneA.isEmpty)
        #expect(plan.laneB == [PromptLanes.Entry(item: "1.1", severity: .blocker, size: .manyFiles)])
    }
}

// MARK: - The gate

@Suite("Prompt lanes plan: the flag gate")
struct PromptLanesPlanGateTests {
    private let round = makeRound([makeCapture(1, [(1, "note")])])
    private var file: JevRecordFile {
        makeFile([1: record(summary: .fields(["1.1": rated("A", .polish, .oneLine)]))])
    }

    @Test("Both flags on gives the plan")
    func bothOn() {
        let plan = PromptLanesPlan.forPrompt(round: round, file: file, flags: flagSet([.jevBase: .on, .promptLanes: .on]))
        #expect(plan == PromptLanesPlan.plan(round: round, file: file))
        #expect(plan != nil)
    }

    @Test("forPrompt is nil when promptLanes is off or shadow, or jevBase is off")
    func gated() {
        let cases: [[FeatureFlag: FlagState]] = [
            [.jevBase: .on, .promptLanes: .off],
            [.jevBase: .on, .promptLanes: .shadow],
            [.jevBase: .on],
            [.jevBase: .off, .promptLanes: .on],
            [.promptLanes: .on],
            [:],
        ]
        for states in cases {
            #expect(PromptLanesPlan.forPrompt(round: round, file: file, flags: flagSet(states)) == nil, "\(states) gave a plan")
        }
    }

    @Test("forPrompt is nil when there is no jev.json, and when no item is rated")
    func noFileOrNoRatedItem() {
        let on = flagSet([.jevBase: .on, .promptLanes: .on])
        #expect(PromptLanesPlan.forPrompt(round: round, file: nil, flags: on) == nil)
        #expect(PromptLanesPlan.forPrompt(round: round, file: JevRecordFile(), flags: on) == nil)
    }

    @Test("Other features' flags do not matter")
    func otherFlags() {
        let states: [FeatureFlag: FlagState] = [.jevBase: .on, .promptLanes: .on, .noteCoach: .on, .cropsAnchors: .shadow]
        #expect(PromptLanesPlan.forPrompt(round: round, file: file, flags: flagSet(states)) != nil)
    }
}

// MARK: - jev.json on disk

/// One probability list with its weight on `level`.
private func scoreAnswer(_ id: String, level: Int, levels: Int = 4) -> String {
    let scale = (0..<levels).map { #""\#($0)":\#($0 == level ? 0.7 : 0.1)"# }.joined(separator: ",")
    return #""\#(id)":{"type":"score","score":\#(level),"confidence":0.9,"legend":{},"probabilities":{\#(scale)}}"#
}

/// A 200 body that answers the three questions of one item.
private func answerBody(item: String, severity: Int, size: Int, exact: Double) -> String {
    let kind = #""\#(item).kind":{"type":"choice","choice":"exact","confidence":0.9,"probabilities":{"exact":\#(exact),"judgment":\#(1 - exact)}}"#
    let answers = [scoreAnswer("\(item).severity", level: severity), scoreAnswer("\(item).size", level: size), kind].joined(separator: ",")
    return #"{"model":"\#(JevEndpoint.model)","answers":{\#(answers)},"usage":{"input_tokens":60,"output_tokens":4}}"#
}

@Suite("Prompt lanes plan: jev.json on disk")
struct PromptLanesPlanDiskTests {
    @Test("loadRecords reads a jev.json written by the runner")
    func roundTrip() async throws {
        // Four captures, one item each. The severity and size levels 0 and 1
        // are in there on purpose: a stored 0 or 1 must read back as a level.
        let bundle = try await Bundle.make(captures: 4)
        let transport = StubTransport([
            jsonResponse(answerBody(item: "1.1", severity: 0, size: 0, exact: 0.9)),
            jsonResponse(answerBody(item: "2.1", severity: 1, size: 1, exact: 0.9)),
            jsonResponse(answerBody(item: "3.1", severity: 2, size: 2, exact: 0.2)),
            jsonResponse(answerBody(item: "4.1", severity: 3, size: 3, exact: 0.9)),
        ])
        let runner = makeRunner(bundle, jobs: [PromptLanesJob()], flags: [.jevBase: .on, .promptLanes: .shadow], transport: transport)
        for index in 1...4 {
            await runCapture(runner, bundle, capture: index)
        }
        #expect(await transport.count == 4)

        let file = try #require(PromptLanesPlan.loadRecords(folderURL: bundle.folder))
        #expect(file.schemaVersion == JevRecordFile.currentSchemaVersion)
        #expect(file.captures.map(\.capture) == [1, 2, 3, 4])
        // The levels read back as numbers, not booleans, on this Foundation.
        let stored = file.captures.compactMap { $0.jobs.first?.summary }
        #expect(stored.count == 4)
        for summary in stored {
            guard case .object(let items) = summary, case .object(let fields)? = items.first?.value else {
                Issue.record("a summary is not an object of items")
                continue
            }
            for field in fields where field.key.text == "severity" || field.key.text == "size" {
                if case .number = field.value { continue }
                Issue.record("\(field.key.text) did not read back as a number: \(field.value)")
            }
        }

        let round = try #require(FeedbackLibrary.round(named: bundle.folderName, in: bundle.root))
        let plan = try #require(PromptLanesPlan.plan(round: round, file: file))
        #expect(plan.laneA == [
            PromptLanes.Entry(item: "2.1", severity: .polish, size: .oneFile),
            PromptLanes.Entry(item: "1.1", severity: .nit, size: .oneLine),
        ])
        #expect(plan.laneB == [
            PromptLanes.Entry(item: "4.1", severity: .blocker, size: .manyFiles),
            PromptLanes.Entry(item: "3.1", severity: .bug, size: .severalFiles),
        ])
        #expect(plan.askFirst.isEmpty)

        // The same plan comes from the flag gate with the app's call shape.
        let gated = PromptLanesPlan.forPrompt(round: round, file: PromptLanesPlan.loadRecords(folderURL: bundle.folder), flags: flagSet([.jevBase: .on, .promptLanes: .on]))
        #expect(gated == plan)
    }

    @Test("A failed request leaves its capture not rated, and a later capture of the round still gets a plan")
    func failedCaptureThroughTheRunner() async throws {
        let bundle = try await Bundle.make(captures: 2)
        // HTTP 400 is final: the base never retries it. A retried 500 would count
        // three slow failures and pause requests, which would stop capture 2 too.
        let transport = StubTransport([
            status(400),
            jsonResponse(answerBody(item: "2.1", severity: 2, size: 2, exact: 0.2)),
        ])
        let runner = makeRunner(bundle, jobs: [PromptLanesJob()], flags: [.jevBase: .on, .promptLanes: .on], transport: transport)
        let round = try #require(FeedbackLibrary.round(named: bundle.folderName, in: bundle.root))

        await runCapture(runner, bundle, capture: 1)
        #expect(await transport.count == 1)
        let failed = try #require(try bundle.record(1))
        #expect(failed.status == .notRefined && failed.reason == .badRequest)
        let afterFirst = try #require(PromptLanesPlan.loadRecords(folderURL: bundle.folder))
        // No item is rated, so the prompt would stay plain.
        #expect(PromptLanesPlan.plan(round: round, file: afterFirst) == nil)
        #expect(PromptLanesPlan.forPrompt(round: round, file: afterFirst, flags: flagSet([.jevBase: .on, .promptLanes: .on])) == nil)

        await runCapture(runner, bundle, capture: 2)
        #expect(await transport.count == 2)
        let afterSecond = try #require(PromptLanesPlan.loadRecords(folderURL: bundle.folder))
        let plan = try #require(PromptLanesPlan.plan(round: round, file: afterSecond))
        #expect(plan.laneA.isEmpty)
        #expect(plan.laneB == [
            PromptLanes.Entry(item: "2.1", severity: .bug, size: .severalFiles),
            PromptLanes.Entry(item: "1.1"),
        ])
        #expect(plan.askFirst.isEmpty)
    }

    @Test("loadRecords gives nil for a missing file, an unreadable file, and another schema version")
    func unreadableFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lanes-plan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(JevRecordFile.fileName)

        #expect(PromptLanesPlan.loadRecords(folderURL: folder) == nil)

        try Data("not json".utf8).write(to: url)
        #expect(PromptLanesPlan.loadRecords(folderURL: folder) == nil)

        try Data(#"{"schemaVersion":1}"#.utf8).write(to: url)
        #expect(PromptLanesPlan.loadRecords(folderURL: folder) == nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var other = JevRecordFile()
        other.schemaVersion = JevRecordFile.currentSchemaVersion + 1
        try encoder.encode(other).write(to: url)
        #expect(PromptLanesPlan.loadRecords(folderURL: folder) == nil)

        // The same file with the current version loads.
        try encoder.encode(JevRecordFile()).write(to: url)
        #expect(PromptLanesPlan.loadRecords(folderURL: folder) == JevRecordFile())
    }
}
