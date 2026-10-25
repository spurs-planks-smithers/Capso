import Foundation
import Testing
@testable import FeedbackKit

/// The two level scales of the lanes feature (issue #69). Jev rates each
/// item on them, and the round plan sorts by them.
@Suite("Prompt lanes: level names")
struct PromptLanesTests {
    @Test("Each severity level has its name, from nit up to blocker")
    func severityNames() {
        #expect(PromptLanes.Severity.allCases.map(\.name) == ["nit", "polish", "bug", "blocker"])
        #expect(PromptLanes.Severity.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(PromptLanes.Severity(rawValue: 0) == .nit)
        #expect(PromptLanes.Severity(rawValue: 1) == .polish)
        #expect(PromptLanes.Severity(rawValue: 2) == .bug)
        #expect(PromptLanes.Severity(rawValue: 3) == .blocker)
        #expect(PromptLanes.Severity(rawValue: 4) == nil)
    }

    @Test("Each size level has its name, from one line up to many files")
    func sizeNames() {
        #expect(PromptLanes.Size.allCases.map(\.name) == ["one line", "one file", "several files", "many files"])
        #expect(PromptLanes.Size.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(PromptLanes.Size(rawValue: 0) == .oneLine)
        #expect(PromptLanes.Size(rawValue: 1) == .oneFile)
        #expect(PromptLanes.Size(rawValue: 2) == .severalFiles)
        #expect(PromptLanes.Size(rawValue: 3) == .manyFiles)
        #expect(PromptLanes.Size(rawValue: 4) == nil)
    }
}

/// The "Order and lanes" section of the copied round prompt (issue #72).
@Suite("Prompt lanes: the prompt section")
struct PromptLanesSectionTests {
    private let folder = "/Users/test/Feedback/2026-10-20-1912-pricing-page"

    private func entry(_ item: String, _ severity: PromptLanes.Severity? = nil, _ size: PromptLanes.Size? = nil) -> PromptLanes.Entry {
        PromptLanes.Entry(item: item, severity: severity, size: size)
    }

    private static let intro = [
        "Order and lanes:",
        "These labels come from an automated model. The reviewer's words win. Each item appears once.",
    ]
    private static let laneAHeading = "Lane A, exact edits. After your plan table, hand these items to a subagent on a fast, low-cost model as one batch, with each item's instruction from manifest.md. In Claude Code, set the subagent's model to haiku. With fewer than three items, do them yourself. Check each edit before you start lane B."
    private static let laneBHeading = "Lane B, needs judgment. Plan these yourself, in this order:"

    @Test("The full section reads exactly as the design shows it")
    func fullExample() {
        let lanes = PromptLanes(
            laneA: [entry("3.2", .polish, .oneLine)],
            laneB: [entry("4.1", .bug, .severalFiles), entry("7.1")],
            askFirst: ["4.5", "6.2"]
        )
        #expect(lanes.promptLines.joined(separator: "\n") == """
        Order and lanes:
        These labels come from an automated model. The reviewer's words win. Each item appears once.
        Lane A, exact edits. After your plan table, hand these items to a subagent on a fast, low-cost model as one batch, with each item's instruction from manifest.md. In Claude Code, set the subagent's model to haiku. With fewer than three items, do them yourself. Check each edit before you start lane B.
        - 3.2 polish, one line
        Lane B, needs judgment. Plan these yourself, in this order:
        - 4.1 bug, several files
        - 7.1 not rated
        Ask first: 4.5, 6.2 (no instruction).
        Start with lane A. Then work lane B from the top.
        """)
    }

    @Test("An entry prints its id, severity name, and size name")
    func entryLines() {
        let lanes = PromptLanes(
            laneA: [entry("1.1", .nit, .oneFile)],
            laneB: [entry("2.1", .blocker, .manyFiles), entry("2.2", .polish, .severalFiles)],
            askFirst: []
        )
        #expect(lanes.promptLines.contains("- 1.1 nit, one file"))
        #expect(lanes.promptLines.contains("- 2.1 blocker, many files"))
        #expect(lanes.promptLines.contains("- 2.2 polish, several files"))
    }

    @Test("An entry with only one level counts as not rated")
    func halfRatedEntry() {
        let lanes = PromptLanes(laneA: [], laneB: [entry("1.1", .bug, nil), entry("1.2", nil, .oneLine)], askFirst: [])
        #expect(lanes.promptLines.contains("- 1.1 not rated"))
        #expect(lanes.promptLines.contains("- 1.2 not rated"))
    }

    @Test("An empty lane A prints its none line, and the last line points to lane B")
    func emptyLaneA() {
        let lanes = PromptLanes(laneA: [], laneB: [entry("1.1", .bug, .oneFile)], askFirst: [])
        #expect(lanes.promptLines == Self.intro + [
            "Lane A, exact edits: none.",
            Self.laneBHeading,
            "- 1.1 bug, one file",
            "Work lane B from the top.",
        ])
    }

    @Test("An empty lane B prints its none line, and the last line points to lane A")
    func emptyLaneB() {
        let lanes = PromptLanes(laneA: [entry("1.1", .nit, .oneLine)], laneB: [], askFirst: [])
        #expect(lanes.promptLines == Self.intro + [
            Self.laneAHeading,
            "- 1.1 nit, one line",
            "Lane B, needs judgment: none.",
            "Start with lane A.",
        ])
    }

    @Test("With both lanes empty, the section has no start line")
    func bothLanesEmpty() {
        let lanes = PromptLanes(laneA: [], laneB: [], askFirst: ["1.1"])
        #expect(lanes.promptLines == Self.intro + [
            "Lane A, exact edits: none.",
            "Lane B, needs judgment: none.",
            "Ask first: 1.1 (no instruction).",
        ])
    }

    @Test("The Ask first line shows only when an item has no note")
    func askFirstLine() {
        let without = PromptLanes(laneA: [entry("1.1", .nit, .oneLine)], laneB: [], askFirst: [])
        #expect(!without.promptLines.contains { $0.hasPrefix("Ask first") })
        let with = PromptLanes(laneA: [entry("1.1", .nit, .oneLine)], laneB: [], askFirst: ["1.2"])
        #expect(with.promptLines.contains("Ask first: 1.2 (no instruction)."))
    }

    @Test("The Ask first line comes just before the start line")
    func askFirstPosition() {
        let lanes = PromptLanes(laneA: [entry("1.1", .nit, .oneLine)], laneB: [entry("1.2", .bug, .oneFile)], askFirst: ["1.3"])
        let lines = lanes.promptLines
        #expect(lines.last == "Start with lane A. Then work lane B from the top.")
        #expect(lines[lines.count - 2] == "Ask first: 1.3 (no instruction).")
    }

    @Test("The section text has no em dash and no middot")
    func plainPunctuation() {
        let lanes = PromptLanes(laneA: [entry("1.1", .nit, .oneLine)], laneB: [entry("2.1")], askFirst: ["3.1"])
        let joined = lanes.promptLines.joined(separator: "\n")
        #expect(!joined.contains("\u{2014}"))
        #expect(!joined.contains("\u{00B7}"))
    }

    // MARK: PromptBuilder.render

    private var round: FeedbackRound {
        FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture()])
    }

    @Test("Without lanes, the round prompt is the plain prompt, byte for byte")
    func nilLanesIsUnchanged() {
        let plain = PromptBuilder.render(round, folderPath: folder)
        #expect(PromptBuilder.render(round, folderPath: folder, lanes: nil) == plain)
        #expect(PromptBuilder.render(round, folderPath: folder, redo: true, refined: true, lanes: nil) == PromptBuilder.render(round, folderPath: folder, redo: true, refined: true))
        #expect(!plain.contains("Order and lanes"))
        #expect(plain.hasSuffix("- Read each image only when you work on its items. Each image costs up to \(ImageSizing.Limits.feedbackExport.maxTokens) tokens.\n</feedback_bundle>\n"))
    }

    @Test("With lanes, the section sits after the Context line, before the closing tag")
    func lanesInsertion() {
        let lanes = PromptLanes(laneA: [entry("2.1", .nit, .oneLine)], laneB: [entry("2.2", .bug, .oneFile)], askFirst: ["2.3"])
        let plain = PromptBuilder.render(round, folderPath: folder)
        let with = PromptBuilder.render(round, folderPath: folder, lanes: lanes)
        let expected = plain.replacingOccurrences(
            of: "</feedback_bundle>\n",
            with: "\n" + lanes.promptLines.joined(separator: "\n") + "\n</feedback_bundle>\n"
        )
        #expect(with == expected)
        #expect(with != plain)
    }

    @Test("The lanes section also follows the refined step and the redo line")
    func lanesWithRefinedAndRedo() {
        let lanes = PromptLanes(laneA: [], laneB: [entry("2.1", .bug, .oneFile)], askFirst: [])
        let plain = PromptBuilder.render(round, folderPath: folder, redo: true, refined: true)
        let with = PromptBuilder.render(round, folderPath: folder, redo: true, refined: true, lanes: lanes)
        let body = plain.replacingOccurrences(of: "</feedback_bundle>\n", with: "")
        #expect(with.hasPrefix(body + "\n" + lanes.promptLines.joined(separator: "\n")))
        #expect(with.hasSuffix("\n</feedback_bundle>\n"))
        #expect(with.contains(PromptBuilder.redoLine))
        #expect(with.contains("6. If `\(folder)/refined.md` exists"))
    }
}
