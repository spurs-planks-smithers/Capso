import FeedbackKit
import Foundation
import Testing
@testable import JevKit

/// Opt-in live evaluation of the duplicates and conflicts job (#39, #58, #60).
/// It runs only with NEXTSHOT_JEV_EVAL=1, a key in TYPESAFE_API_KEY, and an
/// output folder in NEXTSHOT_JEV_EVAL_OUT, through `scripts/jev-eval-dupes.sh`.
/// The plan is docs/superpowers/plans/2026-10-24-dupes-conflicts-test-plan.md,
/// Part A.
///
/// Each labeled pair in `Packages/JevKit/Tests/Fixtures/dupes-eval/cases.json` becomes a real round
/// in a temporary folder. The real `DupesConflictsJob` runs on it through a
/// real `JevClient`, in four arms and three runs each. Two real pairs from
/// Drew's rounds run in arm A1 only, with their notes and never their images.
/// The test reads those rounds and writes nothing there. It writes only
/// `results.json` and `report.md` in the output folder.
@Suite("Duplicates and conflicts live eval", .enabled(if: ProcessInfo.processInfo.environment["NEXTSHOT_JEV_EVAL"] == "1"))
struct DupesConflictsLiveEval {
    /// Fixtures sit in `Packages/JevKit/Tests/Fixtures`, outside the test
    /// target's folder, so SwiftPM does not warn about unhandled files.
    /// `#filePath` finds them.
    static let fixturesFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/dupes-eval", isDirectory: true)

    struct EnvironmentKey: JevKeyProvider {
        func key() async -> String? {
            ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"]
        }
    }

    @Test("Every labeled pair runs through the real job in four arms, three times each")
    func evaluate() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let outPath = environment["NEXTSHOT_JEV_EVAL_OUT"], !outPath.isEmpty else {
            throw DupesEval.EvalError("Set NEXTSHOT_JEV_EVAL_OUT to the output folder.")
        }
        guard let key = environment["TYPESAFE_API_KEY"], !key.isEmpty else {
            throw DupesEval.EvalError("Set TYPESAFE_API_KEY. scripts/jev-eval-dupes.sh reads it from the Keychain.")
        }
        let outputFolder = URL(fileURLWithPath: outPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let fixtures = try DupesEval.loadFixtures(from: Self.fixturesFolder)
        let bundleFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nextshot-dupes-eval-\(UUID().uuidString)", isDirectory: true)
        try DupesEval.makeBundleFolder(at: bundleFolder, fixtures: fixtures, fixturesFolder: Self.fixturesFolder)
        defer { try? FileManager.default.removeItem(at: bundleFolder) }

        // Every scenario of every arm, built before the first request, so a
        // bad case fails the test before any money is spent.
        var scenarios: [DupesEval.Scenario] = []
        for fixtureCase in fixtures.cases {
            for arm in DupesEval.Arm.allCases {
                scenarios.append(try DupesEval.scenario(for: fixtureCase, arm: arm, fixtures: fixtures, folder: bundleFolder))
            }
        }
        var notes: [String] = []
        var order = fixtures.cases.map { DupesEval.Report.CaseInfo(id: $0.id, group: $0.group, expected: $0.expected) }
        for pair in fixtures.realPairs {
            do {
                scenarios.append(try DupesEval.realScenario(for: pair, folder: bundleFolder))
                order.append(DupesEval.Report.CaseInfo(id: pair.id, group: "R", expected: pair.expected))
                notes.append("Real pair \(pair.id) (round \(pair.round), items \(pair.earlier) and \(pair.new)) ran in A1.")
            } catch let skip as DupesEval.EvalError {
                notes.append("Real pair \(pair.id) was skipped: \(skip.message)")
            }
        }
        try #require(!scenarios.isEmpty, "no scenario was built")

        let jobs = scenarios.flatMap { scenario in
            (1...DupesEval.runsPerCase).map { (scenario: scenario, run: $0) }
        }
        let client = JevClient(transport: URLSessionTransport(), keyProvider: EnvironmentKey())
        let limiter = AsyncLimiter(limit: DupesEval.maxConcurrentRequests)
        let progress = DupesEval.Progress()
        let total = jobs.count
        let records = await DupesEval.boundedMap(jobs, limit: DupesEval.maxConcurrentRuns) { job in
            let record = await DupesEval.execute(job.scenario, run: job.run, client: client, limiter: limiter)
            let done = await progress.tick()
            if done % 50 == 0 || done == total {
                print("dupes eval: \(done) of \(total) runs")
            }
            return record
        }

        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let results = DupesEval.Results(
            generatedAt: generatedAt,
            model: JevEndpoint.model,
            runsPerCase: DupesEval.runsPerCase,
            notes: notes,
            runs: records
        )
        try encoder.encode(results).write(to: outputFolder.appendingPathComponent("results.json"), options: .atomic)
        let report = DupesEval.Report.markdown(
            runs: records,
            order: order,
            arms: DupesEval.Arm.allCases.map(\.rawValue),
            variants: DupesEval.variants,
            runsPerCase: DupesEval.runsPerCase,
            notes: notes,
            generatedAt: generatedAt
        )
        try report.write(to: outputFolder.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)

        let checked = records.filter { $0.failure == nil }.count
        print("dupes eval: \(checked) of \(records.count) runs checked. Output: \(outputFolder.path)")
        // A run that checked nothing must fail, not pass.
        #expect(checked > 0, "no run was checked, see failures in results.json")
    }
}

/// The eval's own code, kept out of the suite so the suite reads as one test.
private enum DupesEval {
    static let runsPerCase = 3
    /// At most this many requests are in flight, across all runs.
    static let maxConcurrentRequests = 4
    /// Runs in progress. Each loads images, so this also bounds memory.
    static let maxConcurrentRuns = 8
    static let requestDeadline: Duration = .seconds(15)
    static let imageSize = PixelSize(width: 1440, height: 900)
    static let variants = ["V1", "V2", "V2w", "V3a", "V3b"]

    struct EvalError: Error, CustomStringConvertible {
        var message: String
        init(_ message: String) { self.message = message }
        var description: String { message }
    }

    // MARK: Fixtures

    struct Fixtures: Decodable, Sendable {
        var pages: [String: Page]
        var cases: [Case]
        var realPairs: [RealPair]
        /// Element boxes by page name, read from each page's boxes file.
        var elements: [String: [String: Element]] = [:]

        private enum CodingKeys: String, CodingKey { case pages, cases, realPairs }
    }

    struct Page: Decodable, Sendable {
        var image: String
        var boxes: String
        var app: String
        var window: String
    }

    struct CaseEntry: Decodable, Sendable {
        var page: String
        var element: String?
        var note: String
    }

    struct Case: Decodable, Sendable {
        var id: String
        var group: String
        var expected: String
        var layout: String
        var earlier: CaseEntry
        var new: CaseEntry
    }

    struct RealPair: Decodable, Sendable {
        var id: String
        var expected: String
        var round: String
        var earlier: String
        var new: String
    }

    struct Element: Decodable, Sendable {
        var x1: Int
        var y1: Int
        var x2: Int
        var y2: Int
        var text: String
    }

    private struct BoxesFile: Decodable {
        var boxes: [String: Element]
    }

    static let validCalls: Set<String> = ["duplicate", "overlap", "conflict", "different"]

    static func loadFixtures(from folder: URL) throws -> Fixtures {
        var fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: folder.appendingPathComponent("cases.json")))
        // An empty set would make every gate below pass with nothing in it.
        guard !fixtures.cases.isEmpty, !fixtures.pages.isEmpty else {
            throw EvalError("cases.json holds no cases or no pages.")
        }
        for (name, page) in fixtures.pages {
            let boxes = try JSONDecoder().decode(BoxesFile.self, from: Data(contentsOf: folder.appendingPathComponent(page.boxes)))
            fixtures.elements[name] = boxes.boxes
        }
        for fixtureCase in fixtures.cases {
            guard validCalls.contains(fixtureCase.expected) else {
                throw EvalError("Case \(fixtureCase.id) has expected call \(fixtureCase.expected).")
            }
            for entry in [fixtureCase.earlier, fixtureCase.new] {
                guard fixtures.pages[entry.page] != nil else {
                    throw EvalError("Case \(fixtureCase.id) names page \(entry.page), which does not exist.")
                }
                if let element = entry.element, fixtures.elements[entry.page]?[element] == nil {
                    throw EvalError("Case \(fixtureCase.id) names element \(element) of page \(entry.page), which does not exist.")
                }
            }
        }
        for pair in fixtures.realPairs where !validCalls.contains(pair.expected) {
            throw EvalError("Real pair \(pair.id) has expected call \(pair.expected).")
        }
        return fixtures
    }

    /// Copies each page PNG into the bundle folder under both file names of
    /// each capture position, so `JevImageLoader.bundle` loads crops as the
    /// app does. Two capture positions are enough: no case has more.
    static func makeBundleFolder(at folder: URL, fixtures: Fixtures, fixturesFolder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, page) in fixtures.pages {
            let source = fixturesFolder.appendingPathComponent(page.image)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw EvalError("Page image \(page.image) is missing.")
            }
            for index in 1...2 {
                for file in [imageFile(index: index, page: name), cleanImageFile(index: index, page: name)] {
                    try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(file))
                }
            }
        }
    }

    static func imageFile(index: Int, page: String) -> String { "\(index)-\(page).png" }
    static func cleanImageFile(index: Int, page: String) -> String { "\(index)-\(page)-clean.png" }

    // MARK: Arms

    enum Arm: String, CaseIterable, Sendable {
        case A1, A2, A3, A4

        /// The consent flags of the arm.
        var allowed: JevDataKinds {
            switch self {
            case .A1: [.reviewerText]
            case .A2: [.reviewerText, .screenText]
            case .A3, .A4: [.reviewerText, .screenText, .images]
            }
        }

        /// A4 gives every capture one app name, so every pair counts as the
        /// same source and gets images. It is an experiment and never ships.
        var forcedApp: String? {
            self == .A4 ? "Browser" : nil
        }
    }

    // MARK: Scenarios

    /// One pair in one arm: the round, the capture the job runs on, and the
    /// ids that name the pair in the answers.
    struct Scenario: Sendable {
        var caseID: String
        var group: String
        var expected: String
        var arm: Arm
        var round: FeedbackRound
        var runIndex: Int
        var folder: URL
        var newID: String
        var earlierID: String
        var newEntry: DupesConflicts.Entry
        var earlierEntry: DupesConflicts.Entry
        var images: JevImageLoader
    }

    enum Corner { case topLeft, topRight }

    struct Placement {
        var entry: CaseEntry
        var element: Element?
        var badge: Int
        var corner: Corner
    }

    /// A 30 by 30 badge at the element's top-left corner, 12 pixels up and
    /// left, or at the top-right corner, 12 pixels up and right. It stays
    /// inside the image.
    static func badgeBox(for element: Element, corner: Corner) -> FeedbackBox {
        let side = 30
        let offset = 12
        var x1 = corner == .topLeft ? element.x1 - offset : element.x2 + offset - side
        var y1 = element.y1 - offset
        x1 = min(max(x1, 0), imageSize.width - side)
        y1 = min(max(y1, 0), imageSize.height - side)
        return FeedbackBox(x1: x1, y1: y1, x2: x1 + side, y2: y1 + side)
    }

    /// The element's box with 6 pixels of padding, inside the image.
    static func rectangleBox(for element: Element) -> FeedbackBox {
        let padding = 6
        return FeedbackBox(
            x1: max(element.x1 - padding, 0),
            y1: max(element.y1 - padding, 0),
            x2: min(element.x2 + padding, imageSize.width),
            y2: min(element.y2 + padding, imageSize.height)
        )
    }

    /// An entry with an element gets a badge with its note and a rectangle
    /// around the element, as Nextshot stores them. The screen text under both
    /// is the element's own text, as OCR would give it. An entry with no
    /// element is the capture's general note, and the capture has no marks.
    static func capture(index: Int, pageName: String, page: Page, app: String, placements: [Placement]) -> FeedbackCapture {
        var marks: [FeedbackMark] = []
        var note: String?
        for placement in placements {
            guard let element = placement.element else {
                note = placement.entry.note
                continue
            }
            let text = element.text.isEmpty ? nil : element.text
            marks.append(FeedbackMark(
                kind: .counter,
                badge: placement.badge,
                box: badgeBox(for: element, corner: placement.corner),
                ocrText: text,
                instruction: placement.entry.note
            ))
            marks.append(FeedbackMark(kind: .rectangle, box: rectangleBox(for: element), ocrText: text))
        }
        return FeedbackCapture(
            index: index,
            imageFile: imageFile(index: index, page: pageName),
            cleanImageFile: cleanImageFile(index: index, page: pageName),
            size: imageSize,
            capturedAt: Date(timeIntervalSince1970: 1_792_000_000 + Double(index) * 60),
            sourceApp: app,
            windowTitle: page.window,
            note: note,
            marks: marks
        )
    }

    static func entryID(captureIndex: Int, badge: Int, element: String?) -> String {
        element == nil ? "\(captureIndex).note" : "\(captureIndex).\(badge)"
    }

    static func round(captures: [FeedbackCapture]) -> FeedbackRound {
        FeedbackRound(
            name: "dupes-eval",
            slug: "dupes-eval",
            folderName: "dupes-eval",
            startedAt: Date(timeIntervalSince1970: 1_792_000_000),
            captures: captures
        )
    }

    static func scenario(for fixtureCase: Case, arm: Arm, fixtures: Fixtures, folder: URL) throws -> Scenario {
        func element(_ entry: CaseEntry) -> Element? {
            entry.element.flatMap { fixtures.elements[entry.page]?[$0] }
        }
        func page(_ entry: CaseEntry) throws -> Page {
            guard let page = fixtures.pages[entry.page] else { throw EvalError("Case \(fixtureCase.id): no page \(entry.page).") }
            return page
        }
        func app(_ page: Page) -> String { arm.forcedApp ?? page.app }

        let earlierPage = try page(fixtureCase.earlier)
        let newPage = try page(fixtureCase.new)
        let captures: [FeedbackCapture]
        let runIndex: Int
        let earlierID: String
        let newID: String

        switch fixtureCase.layout {
        case "two-captures":
            captures = [
                capture(index: 1, pageName: fixtureCase.earlier.page, page: earlierPage, app: app(earlierPage), placements: [
                    Placement(entry: fixtureCase.earlier, element: element(fixtureCase.earlier), badge: 1, corner: .topLeft),
                ]),
                capture(index: 2, pageName: fixtureCase.new.page, page: newPage, app: app(newPage), placements: [
                    Placement(entry: fixtureCase.new, element: element(fixtureCase.new), badge: 1, corner: .topLeft),
                ]),
            ]
            runIndex = 2
            earlierID = entryID(captureIndex: 1, badge: 1, element: fixtureCase.earlier.element)
            newID = entryID(captureIndex: 2, badge: 1, element: fixtureCase.new.element)
        case "one-capture":
            guard fixtureCase.earlier.page == fixtureCase.new.page,
                  fixtureCase.earlier.element != nil, fixtureCase.new.element != nil
            else {
                throw EvalError("Case \(fixtureCase.id): a one-capture case needs one page and two elements.")
            }
            // Badge 2 sits at the top-right corner, so two badges on one
            // element do not share a box.
            captures = [
                capture(index: 1, pageName: fixtureCase.earlier.page, page: earlierPage, app: app(earlierPage), placements: [
                    Placement(entry: fixtureCase.earlier, element: element(fixtureCase.earlier), badge: 1, corner: .topLeft),
                    Placement(entry: fixtureCase.new, element: element(fixtureCase.new), badge: 2, corner: .topRight),
                ]),
            ]
            runIndex = 1
            earlierID = "1.1"
            newID = "1.2"
        default:
            throw EvalError("Case \(fixtureCase.id) has layout \(fixtureCase.layout).")
        }
        return try finish(
            caseID: fixtureCase.id,
            group: fixtureCase.group,
            expected: fixtureCase.expected,
            arm: arm,
            captures: captures,
            runIndex: runIndex,
            folder: folder,
            newID: newID,
            earlierID: earlierID,
            images: .bundle(folderURL: folder, round: round(captures: captures))
        )
    }

    /// Looks up the job's own entries for the pair, so the variants use the
    /// same app, window, and capture facts as the job.
    static func finish(
        caseID: String,
        group: String,
        expected: String,
        arm: Arm,
        captures: [FeedbackCapture],
        runIndex: Int,
        folder: URL,
        newID: String,
        earlierID: String,
        images: JevImageLoader
    ) throws -> Scenario {
        let entries = captures.flatMap { DupesConflicts.entries(of: $0) }
        guard let newEntry = entries.first(where: { $0.id.text == newID }),
              let earlierEntry = entries.first(where: { $0.id.text == earlierID })
        else {
            throw EvalError("Case \(caseID): the job finds no entry \(newID) or \(earlierID).")
        }
        return Scenario(
            caseID: caseID,
            group: group,
            expected: expected,
            arm: arm,
            round: round(captures: captures),
            runIndex: runIndex,
            folder: folder,
            newID: newID,
            earlierID: earlierID,
            newEntry: newEntry,
            earlierEntry: earlierEntry,
            images: images
        )
    }

    /// A real pair from Drew's rounds, for arm A1. Capture 1 is a copy of the
    /// earlier item's capture with only that item's badge, its shape, and its
    /// instruction. Capture 2 is the same for the new item. App and window stay.
    /// The round's folder is only read. The image loader always fails, and A1
    /// sends no image, so no image of Drew's leaves the Mac.
    static func realScenario(for pair: RealPair, folder: URL) throws -> Scenario {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Nextshot/\(pair.round)/feedback.json")
        guard let data = try? Data(contentsOf: url) else {
            throw EvalError("\(url.lastPathComponent) of round \(pair.round) was not found.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let source = try? decoder.decode(FeedbackRound.self, from: data) else {
            throw EvalError("feedback.json of round \(pair.round) did not decode.")
        }

        func copy(item: String, as index: Int) throws -> (capture: FeedbackCapture, badge: Int) {
            let parts = item.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 2,
                  let capture = source.captures.first(where: { $0.index == parts[0] }),
                  let found = FeedbackItems.split(capture).items.first(where: { $0.badge.badge == parts[1] }),
                  let instruction = found.badge.instruction,
                  !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw EvalError("Item \(item) of round \(pair.round) is missing or has no note.")
            }
            var result = capture
            result.index = index
            result.note = nil
            result.marks = [found.badge] + (found.shape.map { [$0] } ?? [])
            return (result, parts[1])
        }

        let earlier = try copy(item: pair.earlier, as: 1)
        let new = try copy(item: pair.new, as: 2)
        return try finish(
            caseID: pair.id,
            group: "R",
            expected: pair.expected,
            arm: .A1,
            captures: [earlier.capture, new.capture],
            runIndex: 2,
            folder: folder,
            newID: "2.\(new.badge)",
            earlierID: "1.\(earlier.badge)",
            images: JevImageLoader { _, _, _ in throw JevError(.jobError) }
        )
    }

    // MARK: Variants

    /// V1 with a different cut point for a duplicate.
    static func outcome(sameAsk: Double?, opposite: Double?, duplicateAt: Double) -> DupesConflicts.Outcome {
        if let opposite, opposite >= DupesConflicts.conflictAt { return .conflict }
        guard let sameAsk else { return .different }
        if sameAsk >= duplicateAt { return .duplicate }
        if sameAsk >= DupesConflicts.overlapAt { return .overlap }
        return .different
    }

    /// The call of every variant, scored from one set of answers.
    static func calls(
        sameAsk: Double?,
        opposite: Double?,
        new: DupesConflicts.Entry,
        earlier: DupesConflicts.Entry
    ) -> [String: String] {
        func overlapUnless(_ keep: Bool, _ outcome: DupesConflicts.Outcome) -> DupesConflicts.Outcome {
            outcome == .duplicate && !keep ? .overlap : outcome
        }
        let v1 = DupesConflicts.outcome(sameAsk: sameAsk, opposite: opposite)
        let sameWindow = new.windowTitle != nil && new.windowTitle == earlier.windowTitle
        return [
            "V1": v1.code.text,
            "V2": overlapUnless(new.sharesSource(with: earlier), v1).code.text,
            "V2w": overlapUnless(new.captureIndex == earlier.captureIndex || sameWindow, v1).code.text,
            "V3a": outcome(sameAsk: sameAsk, opposite: opposite, duplicateAt: 1.6).code.text,
            "V3b": outcome(sameAsk: sameAsk, opposite: opposite, duplicateAt: 1.7).code.text,
        ]
    }

    // MARK: Running

    struct RunRecord: Codable, Sendable {
        var caseID: String
        var group: String
        var expected: String
        var arm: String
        var run: Int
        var sameAsk: Double?
        var levelProbabilities: [Double]?
        var opposite: Double?
        /// The call of each variant. Nil when the run was not checked.
        var calls: [String: String]?
        var requests: Int
        var failedRequests: Int
        var imagesSent: Int
        var dataKinds: [String]
        var inputTokens: Int?
        var milliseconds: Int?
        var retries: Int
        var failure: String?

        private enum CodingKeys: String, CodingKey {
            case caseID = "case"
            case group, expected, arm, run, sameAsk, levelProbabilities, opposite, calls
            case requests, failedRequests, imagesSent, dataKinds, inputTokens, milliseconds, retries, failure
        }

        /// Writes null for an empty value, so every run has every key.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(caseID, forKey: .caseID)
            try container.encode(group, forKey: .group)
            try container.encode(expected, forKey: .expected)
            try container.encode(arm, forKey: .arm)
            try container.encode(run, forKey: .run)
            try container.encode(sameAsk, forKey: .sameAsk)
            try container.encode(levelProbabilities, forKey: .levelProbabilities)
            try container.encode(opposite, forKey: .opposite)
            try container.encode(calls, forKey: .calls)
            try container.encode(requests, forKey: .requests)
            try container.encode(failedRequests, forKey: .failedRequests)
            try container.encode(imagesSent, forKey: .imagesSent)
            try container.encode(dataKinds, forKey: .dataKinds)
            try container.encode(inputTokens, forKey: .inputTokens)
            try container.encode(milliseconds, forKey: .milliseconds)
            try container.encode(retries, forKey: .retries)
            try container.encode(failure, forKey: .failure)
        }
    }

    struct Results: Codable, Sendable {
        var generatedAt: String
        var model: String
        var runsPerCase: Int
        var notes: [String]
        var runs: [RunRecord]
    }

    actor Progress {
        private var done = 0
        func tick() -> Int {
            done += 1
            return done
        }
    }

    /// What the asker saw for each request of one run.
    actor Recorder {
        struct Entry: Sendable {
            var imagesSent: Int
            var kinds: JevDataKinds
            var milliseconds: Int
            var retries: Int
            var inputTokens: Int?
            var failure: String?
            var response: JevResponse?
        }

        private(set) var entries: [Entry] = []

        func record(request: JevRequest, elapsed: Duration, result: Result<JevSendResult, JevError>) {
            let parts = elapsed.components
            let milliseconds = Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
            switch result {
            case .success(let sent):
                entries.append(Entry(
                    imagesSent: request.images.count,
                    kinds: request.kinds,
                    milliseconds: milliseconds,
                    retries: sent.retries,
                    inputTokens: sent.response.inputTokens,
                    failure: nil,
                    response: sent.response
                ))
            case .failure(let error):
                entries.append(Entry(
                    imagesSent: request.images.count,
                    kinds: request.kinds,
                    milliseconds: milliseconds,
                    retries: 0,
                    inputTokens: nil,
                    failure: error.description,
                    response: nil
                ))
            }
        }
    }

    static func kindNames(_ kinds: JevDataKinds) -> [String] {
        var names: [String] = []
        if kinds.contains(.reviewerText) { names.append("reviewerText") }
        if kinds.contains(.screenText) { names.append("screenText") }
        if kinds.contains(.images) { names.append("images") }
        return names
    }

    /// Runs the real job once. The asker sends through the real client, holds
    /// one of `maxConcurrentRequests` slots while it waits, and refuses a
    /// request with a data kind that the arm does not allow, as the runner does.
    static func execute(_ scenario: Scenario, run: Int, client: JevClient, limiter: AsyncLimiter) async -> RunRecord {
        let recorder = Recorder()
        let allowed = scenario.arm.allowed
        let asker = JevAsker { request in
            guard allowed.isSuperset(of: request.kinds) else { throw JevError(.consent) }
            try await limiter.acquire()
            let started = ContinuousClock.now
            let result: Result<JevSendResult, JevError>
            do {
                result = .success(try await client.send(request, deadline: .now + requestDeadline))
            } catch let error as JevError {
                result = .failure(error)
            } catch {
                result = .failure(JevError(.jobError))
            }
            let elapsed = ContinuousClock.now - started
            await limiter.release()
            await recorder.record(request: request, elapsed: elapsed, result: result)
            return try result.get().response
        }
        let capture = scenario.round.captures.first { $0.index == scenario.runIndex }
        var jobFailure: String?
        if let capture {
            let context = JevJobContext(
                round: scenario.round,
                capture: capture,
                folderURL: scenario.folder,
                allowed: allowed,
                deadline: .now + .seconds(60),
                jev: asker,
                images: scenario.images,
                // Both sub-flags are on, so the eval measures every question.
                optionModes: [.dupesMerge: .on, .dupesConflict: .on]
            )
            do {
                _ = try await DupesConflictsJob().run(context)
            } catch let error as JevError {
                jobFailure = error.description
            } catch {
                jobFailure = "jobError"
            }
        } else {
            jobFailure = "jobError (no capture \(scenario.runIndex))"
        }

        let entries = await recorder.entries
        var sameAsk: JevScoreAnswer?
        var opposite: Double?
        for response in entries.compactMap(\.response) {
            for id in response.answers.keys {
                guard let parsed = DupesConflicts.parse(questionID: id),
                      parsed.new == scenario.newID,
                      parsed.earlier == scenario.earlierID
                else { continue }
                switch parsed.kind {
                case .sameAsk: sameAsk = response.score(id)
                case .opposite: opposite = response.noul(id)
                }
            }
        }

        // A failed request is not checked. It is never a call.
        var failure = entries.compactMap(\.failure).first ?? jobFailure
        if failure == nil, entries.isEmpty {
            failure = "noRequest"
        }
        if failure == nil, sameAsk == nil || opposite == nil {
            failure = "answerMissing"
        }
        let calls = failure == nil
            ? Self.calls(sameAsk: sameAsk?.score, opposite: opposite, new: scenario.newEntry, earlier: scenario.earlierEntry)
            : nil
        let succeeded = entries.filter { $0.failure == nil }
        return RunRecord(
            caseID: scenario.caseID,
            group: scenario.group,
            expected: scenario.expected,
            arm: scenario.arm.rawValue,
            run: run,
            sameAsk: sameAsk?.score,
            levelProbabilities: sameAsk?.probabilities,
            opposite: opposite,
            calls: calls,
            requests: entries.count,
            failedRequests: entries.count - succeeded.count,
            imagesSent: entries.reduce(0) { $0 + $1.imagesSent },
            dataKinds: kindNames(entries.reduce(into: JevDataKinds()) { $0.formUnion($1.kinds) }),
            inputTokens: succeeded.isEmpty ? nil : succeeded.reduce(0) { $0 + ($1.inputTokens ?? 0) },
            milliseconds: succeeded.isEmpty ? nil : succeeded.reduce(0) { $0 + $1.milliseconds },
            retries: entries.reduce(0) { $0 + $1.retries },
            failure: failure
        )
    }

    /// Runs `body` on every input with at most `limit` at once. Results keep
    /// the order of `inputs`.
    static func boundedMap<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        limit: Int,
        _ body: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        var results = [Output?](repeating: nil, count: inputs.count)
        await withTaskGroup(of: (Int, Output).self) { group in
            var iterator = inputs.enumerated().makeIterator()
            for _ in 0..<max(limit, 1) {
                guard let (position, input) = iterator.next() else { break }
                group.addTask { (position, await body(input)) }
            }
            while let (position, output) = await group.next() {
                results[position] = output
                if let (nextPosition, input) = iterator.next() {
                    group.addTask { (nextPosition, await body(input)) }
                }
            }
        }
        return results.compactMap { $0 }
    }

    // MARK: Report

    enum Report {
        static let callNames = ["duplicate", "overlap", "conflict", "different"]
        /// The least number of duplicate (or conflict) calls the bar needs,
        /// and the least precision: at most 1 wrong call in 10.
        static let barMinimumCalls = 10

        struct CaseInfo: Sendable {
            var id: String
            var group: String
            var expected: String
        }

        /// One labeled outcome. `call` is nil when the runs of a case had no
        /// majority: the case was checked but made no call.
        struct Item {
            var group: String
            var expected: String
            var call: String?
        }

        struct Metrics {
            var dupCalls = 0
            var dupRight = 0
            var dupExpected = 0
            var confCalls = 0
            var confRight = 0
            var confExpected = 0
            var xCalledDuplicate = 0

            init(_ items: [Item]) {
                for item in items {
                    if item.expected == "duplicate" { dupExpected += 1 }
                    if item.expected == "conflict" { confExpected += 1 }
                    if item.call == "duplicate" {
                        dupCalls += 1
                        if item.expected == "duplicate" { dupRight += 1 }
                        if item.group == "X" { xCalledDuplicate += 1 }
                    }
                    if item.call == "conflict" {
                        confCalls += 1
                        if item.expected == "conflict" { confRight += 1 }
                    }
                }
            }
        }

        /// The call that more than half of the checked runs made. "split" when
        /// none did, "not checked" when no run was checked.
        static func majority(_ calls: [String]) -> String {
            guard !calls.isEmpty else { return "not checked" }
            let counts = Dictionary(grouping: calls, by: { $0 }).mapValues(\.count)
            if let top = counts.max(by: { $0.value < $1.value }), top.value * 2 > calls.count {
                return top.key
            }
            return "split"
        }

        static func ratio(_ part: Int, _ whole: Int) -> String {
            whole == 0 ? "n/a" : String(format: "%.2f", Double(part) / Double(whole))
        }

        static func percent(_ part: Int, _ whole: Int) -> String {
            whole == 0 ? "n/a" : String(format: "%.1f%% (%ld of %ld)", Double(part) * 100 / Double(whole), part, whole)
        }

        static func number(_ value: Double?) -> String {
            value.map { String(format: "%.2f", $0) } ?? "n/a"
        }

        static func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        /// The bar for one call type: at least 10 calls, at most 1 wrong in 10.
        static func bar(right: Int, calls: Int) -> String {
            calls >= barMinimumCalls && right * 10 >= calls * 9 ? "yes" : "no"
        }

        /// An empty cell reads n/a, never a dash or a blank.
        static func table(_ header: [String], _ rows: [[String]]) -> [String] {
            func line(_ cells: [String]) -> String {
                "| " + cells.map { $0.isEmpty ? "n/a" : $0 }.joined(separator: " | ") + " |"
            }
            return [line(header), line(header.map { _ in "---" })] + rows.map(line)
        }

        static func markdown(
            runs: [RunRecord],
            order: [CaseInfo],
            arms: [String],
            variants: [String],
            runsPerCase: Int,
            notes: [String],
            generatedAt: String
        ) -> String {
            let byArm: [String: [String: [RunRecord]]] = Dictionary(grouping: runs, by: \.arm)
                .mapValues { Dictionary(grouping: $0, by: \.caseID) }

            func runsOf(arm: String, caseID: String) -> [RunRecord] {
                (byArm[arm]?[caseID] ?? []).sorted { $0.run < $1.run }
            }

            /// The runs of one arm that were checked, as labeled items.
            func runItems(arm: String, variant: String) -> [Item] {
                (byArm[arm] ?? [:]).values.flatMap { $0 }.compactMap { run in
                    run.calls.map { Item(group: run.group, expected: run.expected, call: $0[variant]) }
                }
            }

            /// The majority call of one case in one arm: a call name, "split",
            /// or "not checked". Nil when the case did not run in that arm.
            func caseCall(arm: String, info: CaseInfo, variant: String) -> String? {
                let caseRuns = runsOf(arm: arm, caseID: info.id)
                guard !caseRuns.isEmpty else { return nil }
                return majority(caseRuns.compactMap { $0.calls?[variant] })
            }

            /// One item per checked case: its majority call.
            func caseItems(arm: String, variant: String) -> [Item] {
                order.compactMap { info in
                    guard let result = caseCall(arm: arm, info: info, variant: variant), result != "not checked" else { return nil }
                    return Item(group: info.group, expected: info.expected, call: callNames.contains(result) ? result : nil)
                }
            }

            var out: [String] = []
            out.append("# Duplicates and conflicts live eval")
            out.append("")
            out.append("Generated \(generatedAt). Model \(JevEndpoint.model). \(runs.count) runs: \(runsPerCase) per case and arm. Arms: \(arms.joined(separator: ", ")).")
            out.append("")
            out.append("A run whose request failed is not checked and is never a call. Recall counts checked runs and cases only. The majority call of a case is the call that more than half of its checked runs made. A case with no majority is split: it counts in recall as a miss and makes no call.")
            for note in notes {
                out.append("")
                out.append(note)
            }

            // 1. Precision and recall per arm and variant.
            out.append("")
            out.append("## 1. Precision and recall by arm and variant")
            out.append("")
            out.append("The bar for each call type: at least \(barMinimumCalls) calls and at most 1 wrong in 10. Real pairs R1 and R2 count in A1 only. Basis runs counts every checked run. Basis cases counts the majority call of each case.")
            out.append("")
            var rows: [[String]] = []
            for arm in arms {
                for variant in variants {
                    for (basis, items) in [("runs", runItems(arm: arm, variant: variant)), ("cases", caseItems(arm: arm, variant: variant))] {
                        let metrics = Metrics(items)
                        rows.append([
                            arm, variant, basis,
                            String(metrics.dupCalls), String(metrics.dupRight),
                            ratio(metrics.dupRight, metrics.dupCalls), ratio(metrics.dupRight, metrics.dupExpected),
                            String(metrics.confCalls), String(metrics.confRight),
                            ratio(metrics.confRight, metrics.confCalls), ratio(metrics.confRight, metrics.confExpected),
                            String(metrics.xCalledDuplicate),
                            bar(right: metrics.dupRight, calls: metrics.dupCalls),
                            bar(right: metrics.confRight, calls: metrics.confCalls),
                        ])
                    }
                }
            }
            out += table([
                "Arm", "Variant", "Basis",
                "Dup calls", "Dup right", "Dup precision", "Dup recall",
                "Conflict calls", "Conflict right", "Conflict precision", "Conflict recall",
                "X called dup", "Dup bar", "Conflict bar",
            ], rows)

            // 2. Expected call by actual call, V1, majority calls.
            out.append("")
            out.append("## 2. Expected call by actual call (V1, majority call of each case)")
            for arm in arms {
                var counts: [String: [String: Int]] = [:]
                for info in order {
                    guard let result = caseCall(arm: arm, info: info, variant: "V1") else { continue }
                    counts[info.expected, default: [:]][result, default: 0] += 1
                }
                out.append("")
                out.append("Arm \(arm). Rows are the expected call, columns the actual call.")
                out.append("")
                let columns = callNames + ["split", "not checked"]
                out += table(["Expected"] + columns, callNames.map { expected in
                    [expected] + columns.map { String(counts[expected]?[$0] ?? 0) }
                })
            }

            // 3. One row per case.
            out.append("")
            out.append("## 3. Every case")
            out.append("")
            out.append("Each arm cell is the V1 majority call, then the mean sameAsk and the mean opposite of the checked runs. [!] marks a case whose checked runs gave different V1 calls.")
            out.append("")
            var caseRows: [[String]] = []
            for info in order {
                var row = [info.id, info.group, info.expected]
                for arm in arms {
                    let caseRuns = runsOf(arm: arm, caseID: info.id)
                    if caseRuns.isEmpty {
                        row.append("n/a")
                        continue
                    }
                    let checked = caseRuns.filter { $0.calls != nil }
                    if checked.isEmpty {
                        row.append("not checked")
                        continue
                    }
                    let v1 = checked.compactMap { $0.calls?["V1"] }
                    var cell = "\(majority(v1)) (\(number(mean(checked.compactMap(\.sameAsk)))), \(number(mean(checked.compactMap(\.opposite)))))"
                    if Set(v1).count > 1 { cell += " [!]" }
                    if checked.count < caseRuns.count { cell += " (\(caseRuns.count - checked.count) not checked)" }
                    row.append(cell)
                }
                caseRows.append(row)
            }
            out += table(["Case", "Group", "Expected"] + arms, caseRows)

            // 4. Stability.
            out.append("")
            out.append("## 4. Stability")
            out.append("")
            out.append("The share of cases whose runs all gave the same V1 call. Cases with a not-checked run are left out.")
            out.append("")
            var stabilityRows: [[String]] = []
            for arm in arms {
                var complete = 0
                var stable = 0
                for info in order {
                    let caseRuns = runsOf(arm: arm, caseID: info.id)
                    guard !caseRuns.isEmpty, caseRuns.allSatisfy({ $0.calls != nil }) else { continue }
                    complete += 1
                    if Set(caseRuns.compactMap { $0.calls?["V1"] }).count == 1 { stable += 1 }
                }
                stabilityRows.append([arm, percent(stable, complete)])
            }
            out += table(["Arm", "Same V1 call in every run"], stabilityRows)

            // 5. Requests, failures, time, and tokens.
            out.append("")
            out.append("## 5. Requests, failures, time, and tokens")
            out.append("")
            out.append("Mean milliseconds and mean input tokens are over requests that succeeded.")
            out.append("")
            var requestRows: [[String]] = []
            for arm in arms {
                let armRuns = (byArm[arm] ?? [:]).values.flatMap { $0 }
                let requests = armRuns.reduce(0) { $0 + $1.requests }
                let failed = armRuns.reduce(0) { $0 + $1.failedRequests }
                let succeeded = requests - failed
                let milliseconds = armRuns.compactMap(\.milliseconds).reduce(0, +)
                let tokens = armRuns.compactMap(\.inputTokens).reduce(0, +)
                let reasons = Dictionary(grouping: armRuns.compactMap(\.failure), by: { $0 })
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key) \($0.value.count)" }
                    .joined(separator: ", ")
                requestRows.append([
                    arm,
                    String(requests),
                    String(failed),
                    reasons,
                    String(armRuns.reduce(0) { $0 + $1.imagesSent }),
                    succeeded == 0 ? "n/a" : String(format: "%.0f", Double(milliseconds) / Double(succeeded)),
                    succeeded == 0 ? "n/a" : String(format: "%.0f", Double(tokens) / Double(succeeded)),
                ])
            }
            out += table(["Arm", "Requests", "Failed", "Not checked runs by reason", "Images sent", "Mean milliseconds", "Mean input tokens"], requestRows)
            out.append("")
            return out.joined(separator: "\n")
        }
    }
}
