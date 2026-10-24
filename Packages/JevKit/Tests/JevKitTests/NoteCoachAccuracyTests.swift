import FeedbackKit
import Foundation
import Testing
@testable import JevKit

private let evalPath = ProcessInfo.processInfo.environment["NEXTSHOT_NOTE_COACH_EVAL"] ?? ""

/// Measures how well the note coach labels real reviewer notes. It sends
/// reviewer note text to TypeSafe, which keeps each request. Drew approved
/// text-only sends on 2026-10-24 (issue #62). It runs only when
/// NEXTSHOT_NOTE_COACH_EVAL names a set file, through
/// `scripts/note-coach-eval.sh`. The set file and the results file stay outside
/// the repository. The results hold labels and numbers, never note text.
@Suite("Note coach accuracy (live)", .enabled(if: !evalPath.isEmpty))
struct NoteCoachAccuracyTests {
    private struct EvalSet: Decodable {
        struct Item: Decodable {
            var badge: Int
            var note: String
            var expected: String
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
        var expected: String
        var label: String
        var levels: [Double]
        var namesChange: Double?
        var asksAnswer: Double?

        var json: [String: Any] {
            func number(_ value: Double?) -> Any { value.map { $0 as Any } ?? NSNull() }
            return [
                "key": key, "set": set, "badge": badge, "expected": expected, "label": label,
                "level0": number(levels.count > 0 ? levels[0] : nil),
                "level1": number(levels.count > 1 ? levels[1] : nil),
                "level2": number(levels.count > 2 ? levels[2] : nil),
                "names_change": number(namesChange),
                "asks_answer": number(asksAnswer),
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

    private static func check(_ name: String, _ pass: Bool, _ detail: String) {
        print("\(pass ? "PASS" : "FAIL"): \(name): \(detail)")
    }

    @Test("Labels the set's notes and measures three checks")
    func measure() async throws {
        let input = URL(fileURLWithPath: evalPath)
        let evalSet = try JSONDecoder().decode(EvalSet.self, from: Data(contentsOf: input))
        try #require(!evalSet.captures.isEmpty, "the set holds no captures")

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
                images: JevImageLoader { _, _, _ in throw NoImages() }
            )
            do {
                _ = try await NoteCoachJob().run(context)
            } catch {
                // A JevError names only a reason. Any other error gives its type, never its text.
                errors.append((key: entry.key, error: error is JevError ? "\(error)" : String(describing: type(of: error))))
            }

            let response = await recorded.response
            inputTokens += response?.inputTokens ?? 0
            retries += await recorded.retries
            for item in entry.items {
                var row = Row(key: entry.key, set: entry.set, badge: item.badge, expected: item.expected, label: "empty", levels: [])
                if !item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let id = "\(entry.index).\(item.badge)"
                    let clarity = response?.score("\(id).clarity")
                    row.levels = clarity?.probabilities ?? []
                    row.namesChange = response?.noul("\(id).names_change")
                    row.asksAnswer = response?.noul("\(id).asks_answer")
                    row.label = NoteCoachRule.label(clarity: clarity, namesChange: row.namesChange, asksAnswer: row.asksAnswer)?.rawValue ?? "not_checked"
                }
                rows.append(row)
            }
        }
        let elapsed = ContinuousClock.now - started

        let report: [String: Any] = [
            "model": JevEndpoint.model,
            "ran_at": ISO8601DateFormatter().string(from: Date()),
            "thresholds": [
                "vague_level_minimum": NoteCoachRule.vagueLevelMinimum,
                "yes_minimum": NoteCoachRule.yesMinimum,
                "no_maximum": NoteCoachRule.noMaximum,
            ],
            "errors": errors.map { ["key": $0.key, "error": $0.error] },
            "items": rows.map(\.json),
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: input.deletingLastPathComponent().appendingPathComponent("note-coach-results.json"), options: .atomic)

        // Rows are the expected label. Columns are the label that code gave.
        let columns = NoteCoachLabel.allCases.map(\.rawValue) + ["not_checked"]
        let known = ["real", "test", "made-up"]
        let setNames = known.filter { name in rows.contains { $0.set == name } } + Set(rows.map(\.set)).subtracting(known).sorted()
        for name in setNames {
            let subset = rows.filter { $0.set == name }
            let expectedLabels = ["empty", "vague", "partial", "question", "clear"] + Set(subset.map(\.expected)).subtracting(["empty", "vague", "partial", "question", "clear"]).sorted()
            print("\nSet \(name), \(subset.count) items. Rows: expected. Columns: actual.")
            print(Self.pad("", 10) + columns.map { Self.pad($0, 12) }.joined())
            for expected in expectedLabels {
                print(Self.pad(expected, 10) + columns.map { column in
                    Self.pad(String(subset.filter { $0.expected == expected && $0.label == column }.count), 12)
                }.joined())
            }
        }
        print("\nInput tokens: \(inputTokens). Retries: \(retries). Elapsed: \(elapsed). Capture errors: \(errors.count).\n")

        let real = rows.filter { $0.set == "real" }
        let realVague = real.filter { $0.label == "vague" }.count
        Self.check("Real notes labeled vague", realVague == 0, "\(realVague) of \(real.count) real items (must be 0)")
        let vagueItems = rows.filter { ($0.set == "test" || $0.set == "made-up") && $0.expected == "vague" }
        let vagueHits = vagueItems.filter { $0.label == "vague" }.count
        Self.check("Vague recall", !vagueItems.isEmpty && vagueHits * 5 >= vagueItems.count * 4, "\(vagueHits) of \(vagueItems.count) expected-vague test and made-up items labeled vague (must be at least 80%)")
        let questionItems = real.filter { $0.expected == "question" }
        let questionHits = questionItems.filter { $0.label == "question" }.count
        Self.check("Question recall", questionHits >= 7, "\(questionHits) of \(questionItems.count) expected-question real items labeled question (must be at least 7)")

        #expect(errors.isEmpty, "capture errors: \(errors.map { "\($0.key): \($0.error)" })")
        let unchecked = rows.filter { $0.label == "not_checked" }
        #expect(unchecked.isEmpty, "not checked: \(unchecked.map { "\($0.key) badge \($0.badge)" })")
    }
}
