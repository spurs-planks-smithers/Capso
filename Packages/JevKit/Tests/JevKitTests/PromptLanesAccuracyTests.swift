import FeedbackKit
import Foundation
import Testing
@testable import JevKit

private let evalPath = ProcessInfo.processInfo.environment["NEXTSHOT_PROMPT_LANES_EVAL"] ?? ""

/// Measures how well the lanes job rates real reviewer notes. It sends
/// reviewer note text to TypeSafe, which keeps each request. Drew approved
/// text-only sends on 2026-10-24 (issue #73). It runs only when
/// NEXTSHOT_PROMPT_LANES_EVAL names a set file, through
/// `scripts/prompt-lanes-eval.sh`. The set file and the results file stay
/// outside the repository. The results hold labels and numbers, never note
/// text. The five spec bars print PASS or FAIL. They do not fail the test.
@Suite("Prompt lanes accuracy (live)", .enabled(if: !evalPath.isEmpty))
struct PromptLanesAccuracyTests {
    /// A lane in the set file (the expected lane) or in a result (the actual
    /// lane). Only a result can be `notRated`.
    private enum Lane: String, Decodable, CaseIterable {
        case a = "A"
        case b = "B"
        case askFirst
        case notRated
    }

    private enum SeverityName: String, Decodable, CaseIterable {
        case nit, polish, bug, blocker
    }

    private struct EvalSet: Decodable {
        struct Item: Decodable {
            var badge: Int
            var note: String
            var lane: Lane
            var severity: SeverityName?
            var vague: Bool?
        }

        struct Capture: Decodable {
            var key: String
            var set: String
            var index: Int
            var generalNote: String?
            var items: [Item]

            enum CodingKeys: String, CodingKey {
                case key, set, index, items
                case generalNote = "general_note"
            }
        }

        var captures: [Capture]
    }

    private struct Row {
        var key: String
        var set: String
        var badge: Int
        var expectedLane: Lane
        var expectedSeverity: SeverityName?
        var vague: Bool
        var lane = Lane.notRated
        var severity: String?
        var size: String?
        var severityProbabilities: [Double]?
        var sizeProbabilities: [Double]?
        var exact: Double?

        var json: [String: Any] {
            func value(_ value: Any?) -> Any { value ?? NSNull() }
            // JSONSerialization raises on a number that is not finite.
            func number(_ value: Double?) -> Any {
                guard let value, value.isFinite else { return NSNull() }
                return value
            }
            func numbers(_ values: [Double]?) -> Any {
                guard let values, values.allSatisfy(\.isFinite) else { return NSNull() }
                return values
            }
            return [
                "key": key, "set": set, "badge": badge,
                "expected_lane": expectedLane.rawValue,
                "expected_severity": value(expectedSeverity?.rawValue),
                "vague": vague,
                "lane": lane.rawValue,
                "severity": value(severity),
                "size": value(size),
                "severity_probabilities": numbers(severityProbabilities),
                "size_probabilities": numbers(sizeProbabilities),
                "exact": number(exact),
            ]
        }
    }

    /// The answer that the asker got for one capture.
    private actor Recorded {
        private(set) var response: JevResponse?
        private(set) var retries = 0

        func store(_ response: JevResponse, retries: Int) {
            self.response = response
            self.retries += retries
        }
    }

    private struct NoImages: Error {}

    private static func makeCapture(_ input: EvalSet.Capture) -> FeedbackCapture {
        let general = input.generalNote ?? ""
        return FeedbackCapture(
            index: input.index,
            imageFile: "eval.png",
            cleanImageFile: "eval-clean.png",
            size: PixelSize(width: 800, height: 600),
            capturedAt: Date(timeIntervalSince1970: 1_792_000_000),
            note: general.isEmpty ? nil : general,
            marks: input.items.map {
                FeedbackMark(kind: .counter, badge: $0.badge, box: FeedbackBox(x1: 10, y1: 10, x2: 40, y2: 40), instruction: $0.note.isEmpty ? nil : $0.note)
            }
        )
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    /// A bar over a population. An empty population cannot pass: a set that
    /// holds no item for the bar measures nothing.
    private static func check(_ name: String, population: Int, _ pass: Bool, _ detail: String) {
        if population == 0 {
            print("FAIL: \(name): the set holds no item to measure")
        } else {
            print("\(pass ? "PASS" : "FAIL"): \(name): \(detail)")
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Prints one table. Rows are the expected value. Columns are the value
    /// that the job gave.
    private static func table(rows: [String], columns: [String], count: (_ expected: String, _ actual: String) -> Int) {
        print(pad("", 12) + columns.map { pad($0, 10) }.joined())
        for expected in rows {
            print(pad(expected, 12) + columns.map { pad(String(count(expected, $0)), 10) }.joined())
        }
    }

    @Test("Rates the set's notes and measures five checks")
    func measure() async throws {
        let input = URL(fileURLWithPath: evalPath)
        let evalSet = try JSONDecoder().decode(EvalSet.self, from: Data(contentsOf: input))
        try #require(!evalSet.captures.isEmpty, "the set holds no captures")
        try #require(!evalSet.captures.contains { $0.items.contains { $0.lane == .notRated } }, "an expected lane is A, B, or askFirst")

        let client = JevClient(transport: URLSessionTransport(), keyProvider: JevLiveTests.EnvironmentKey())
        let started = ContinuousClock.now
        var rows: [Row] = []
        var errors: [(key: String, error: String)] = []
        var inputTokens = 0
        var retries = 0

        for entry in evalSet.captures {
            let capture = Self.makeCapture(entry)
            let recorded = Recorded()
            let deadline = ContinuousClock.now + .seconds(10)
            let context = JevJobContext(
                round: FeedbackRound(name: "eval", slug: "eval", folderName: "eval", startedAt: capture.capturedAt, captures: [capture]),
                capture: capture,
                folderURL: input.deletingLastPathComponent(),
                allowed: .reviewerText,
                deadline: deadline,
                jev: JevAsker { request in
                    let result = try await client.send(request, deadline: deadline)
                    await recorded.store(result.response, retries: result.retries)
                    return result.response
                },
                images: JevImageLoader { _, _, _ in throw NoImages() },
                // Both sub-flags on, as a trial with `feature promptLanes on` runs the job.
                optionModes: [.lanesOrder: .on, .lanesSplit: .on]
            )
            do {
                _ = try await PromptLanesJob().run(context)
            } catch {
                // A JevError names only a reason. Any other error gives its type, never its text.
                errors.append((key: entry.key, error: error is JevError ? "\(error)" : String(describing: type(of: error))))
            }

            let response = await recorded.response
            inputTokens += response?.inputTokens ?? 0
            retries += await recorded.retries
            for item in entry.items {
                var row = Row(key: entry.key, set: entry.set, badge: item.badge, expectedLane: item.lane, expectedSeverity: item.severity, vague: item.vague ?? false)
                if item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    row.lane = .askFirst
                } else {
                    let id = "\(entry.index).\(item.badge)"
                    let severity = response?.score("\(id).severity")
                    let size = response?.score("\(id).size")
                    let kind = response?.choice("\(id).kind")
                    row.severityProbabilities = severity?.probabilities
                    row.sizeProbabilities = size?.probabilities
                    row.exact = kind?.probabilities["exact"]
                    if let rating = PromptLanesRule.rate(severity: severity, size: size, kind: kind) {
                        row.lane = rating.laneA ? .a : .b
                        row.severity = rating.severity.name
                        row.size = rating.size.name
                    }
                }
                rows.append(row)
            }
        }
        let elapsed = ContinuousClock.now - started

        let report: [String: Any] = [
            "model": JevEndpoint.model,
            "ran_at": ISO8601DateFormatter().string(from: Date()),
            "elapsed_seconds": Self.seconds(elapsed),
            "exact_minimum": PromptLanesRule.exactMinimum,
            "errors": errors.map { ["key": $0.key, "error": $0.error] },
            "items": rows.map(\.json),
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: input.deletingLastPathComponent().appendingPathComponent("prompt-lanes-results.json"), options: .atomic)

        let known = ["real", "test", "made-up"]
        let setNames = known.filter { name in rows.contains { $0.set == name } } + Set(rows.map(\.set)).subtracting(known).sorted()
        let expectedLanes = Lane.allCases.filter { $0 != .notRated }.map(\.rawValue)
        let severityNames = SeverityName.allCases.map(\.rawValue) + ["none"]
        for name in setNames {
            let subset = rows.filter { $0.set == name }
            print("\nSet \(name), \(subset.count) items. Lanes. Rows: expected. Columns: actual.")
            Self.table(rows: expectedLanes, columns: Lane.allCases.map(\.rawValue)) { expected, actual in
                subset.filter { $0.expectedLane.rawValue == expected && $0.lane.rawValue == actual }.count
            }
            print("\nSet \(name). Severity. Rows: expected. Columns: actual (none: no severity).")
            Self.table(rows: severityNames, columns: severityNames) { expected, actual in
                subset.filter { ($0.expectedSeverity?.rawValue ?? "none") == expected && ($0.severity ?? "none") == actual }.count
            }
        }
        print("\nInput tokens: \(inputTokens). Retries: \(retries). Elapsed: \(elapsed). Capture errors: \(errors.count).\n")

        let real = rows.filter { $0.set == "real" }

        // 1. At least 90% of the real items that the job put in lane A are expected there.
        let realInA = real.filter { $0.lane == .a }
        let realInAHits = realInA.filter { $0.expectedLane == .a }.count
        Self.check("Lane A precision, real", population: real.count, realInAHits * 10 >= realInA.count * 9, "\(realInAHits) of \(realInA.count) real items in lane A are expected in lane A (must be at least 90%)")

        // 2. No blocker in lane A, in any set.
        let blockers = rows.filter { $0.expectedSeverity == .blocker }
        let blockersInA = blockers.filter { $0.lane == .a }.count
        Self.check("Blockers in lane A", population: blockers.count, blockersInA == 0, "\(blockersInA) of \(blockers.count) expected blockers are in lane A (must be 0)")

        // 3. At least 50% of the real items that are expected in lane A reach it.
        let realExpectedA = real.filter { $0.expectedLane == .a }
        let recallHits = realExpectedA.filter { $0.lane == .a }.count
        Self.check("Lane A recall, real", population: realExpectedA.count, recallHits * 2 >= realExpectedA.count, "\(recallHits) of \(realExpectedA.count) real items expected in lane A are in lane A (must be at least 50%)")

        // 4. Every real bug or blocker is rated bug or blocker.
        let realBugs = real.filter { $0.expectedSeverity == .bug || $0.expectedSeverity == .blocker }
        let bugHits = realBugs.filter { $0.severity == "bug" || $0.severity == "blocker" }.count
        Self.check("Bug recall, real", population: realBugs.count, bugHits == realBugs.count, "\(bugHits) of \(realBugs.count) real bug and blocker items are rated bug or blocker (must be all)")

        // 5. No vague test or made-up note in lane A.
        let vagueItems = rows.filter { ($0.set == "test" || $0.set == "made-up") && $0.vague }
        let vagueInA = vagueItems.filter { $0.lane == .a }.count
        Self.check("Vague notes in lane A, test and made-up", population: vagueItems.count, vagueInA == 0, "\(vagueInA) of \(vagueItems.count) vague test and made-up items are in lane A (must be 0)")

        #expect(errors.isEmpty, "capture errors: \(errors.map { "\($0.key): \($0.error)" })")
        let unrated = rows.filter { $0.lane == .notRated }
        #expect(unrated.isEmpty, "not rated: \(unrated.map { "\($0.key) badge \($0.badge)" })")
    }
}
