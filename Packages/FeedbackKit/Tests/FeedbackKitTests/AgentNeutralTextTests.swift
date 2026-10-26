import Foundation
import Testing
@testable import FeedbackKit

/// Nextshot works with any AI agent (#109). No text it writes into a bundle
/// names an agent product. Per-agent commands live in
/// `docs/agents/bundle-guide.md`, not in the bundle.
@Suite("Agent-neutral bundle text")
struct AgentNeutralTextTests {
    static let agentNames = ["codex", "claude", "chatgpt", "gemini", "copilot", "openai", "anthropic"]

    /// Every text that a bundle or a zip export holds, in both path modes.
    static func bundleTexts() -> [(name: String, text: String)] {
        let one = FeedbackFixtures.pricingCapture(index: 1)
        let two = FeedbackFixtures.pricingCapture(index: 2)
        let round = FeedbackFixtures.round(captures: [one, two])
        let folder = "/Users/test/Feedback/2026-10-20-1912-pricing-page"
        let absolute = BundlePathMode.absolute(folderPath: folder)
        let relative = BundlePathMode.relative(exportFolderName: "nextshot-round-x")
        let zipPlan = ZipPlanner.plan(
            kind: .round,
            entries: ZipPlanTests.entries(round),
            folderName: "nextshot-round-x",
            zipTime: FeedbackFixtures.date(25, 7, 0),
            pixelScale: 1
        )
        let zone = FeedbackFixtures.timeZone
        return [
            ("manifest (absolute)", ManifestWriter.render(round, paths: absolute, timeZone: zone)),
            ("manifest (relative)", ManifestWriter.render(round, paths: relative, timeZone: zone)),
            ("manifest (no captures)", ManifestWriter.render(FeedbackFixtures.round(captures: []), paths: absolute, timeZone: zone)),
            ("round prompt", PromptBuilder.render(round, paths: absolute)),
            ("round prompt (redo, refined)", PromptBuilder.render(round, paths: absolute, redo: true, refined: true)),
            ("round prompt (relative)", PromptBuilder.render(round, paths: relative)),
            ("capture prompt", PromptBuilder.renderCapture(two, paths: absolute)),
            ("capture prompt (relative)", PromptBuilder.renderCapture(two, paths: relative)),
            ("selection prompt", PromptBuilder.renderSelection(ZipPlanTests.entries(round))),
            ("zip README", ZipReadme.render(zipPlan, kind: .round, missing: [])),
        ]
    }

    @Test("No text written into a bundle names an agent product")
    func bundleTextNamesNoAgent() throws {
        let texts = Self.bundleTexts()
        try #require(texts.count >= 10, "the guard renders too few texts")
        for (name, text) in texts {
            try #require(!text.isEmpty, "\(name) is empty")
            let lowered = text.lowercased()
            for agent in Self.agentNames {
                #expect(!lowered.contains(agent), "\(name) names \(agent)")
            }
        }
    }

    @Test("The guard catches an agent name")
    func guardCatchesAgentName() {
        let text = "## Codex command\ncodex --image a.png".lowercased()
        #expect(Self.agentNames.contains { text.contains($0) })
    }
}
