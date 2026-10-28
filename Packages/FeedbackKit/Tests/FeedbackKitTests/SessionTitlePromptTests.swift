import Foundation
import Testing
@testable import FeedbackKit

/// Session names (#164): with `sessionTitle`, a pasted prompt carries the
/// reviewer's words in its first 2000 characters and asks the agent to name
/// its session. Without it, every prompt is as it was.
@Suite("Session title prompts")
struct SessionTitlePromptTests {
    private let folder = "/Users/test/Feedback/2026-10-20-1912-pricing-page"
    private let titleStepLimit = 2000

    private var round: FeedbackRound {
        FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture(index: 1), FeedbackFixtures.pricingCapture(index: 2)])
    }

    @Test("The round prompt lists the reviewer's items and notes inside the title step's first 2000 characters")
    func roundPromptItemsInline() throws {
        let prompt = PromptBuilder.render(round, folderPath: folder, sessionTitle: true)
        let head = String(prompt.prefix(titleStepLimit))
        try #require(head.count == titleStepLimit)
        for expected in [
            "Capture 1 items (badge N in its image is item 1.N):",
            "- 1.1: Price is wrong, should be $15",
            "- 1.2: Make this the primary button",
            "- 1.3: (no instruction)",
            "Capture 2 items (badge N in its image is item 2.N):",
            "- 2.1: Price is wrong, should be $15",
            "Note: The plan cards feel cramped on this page.",
            PromptBuilder.sessionNameLine,
        ] {
            #expect(head.contains(expected), "the first 2000 characters lack: \(expected)")
        }
    }

    @Test("The round prompt puts the items and the name line between the Goal line and the reading steps")
    func roundPromptOrder() throws {
        let prompt = PromptBuilder.render(round, folderPath: folder, redo: true, sessionTitle: true)
        let goal = try #require(prompt.range(of: "Goal:")?.lowerBound)
        let redo = try #require(prompt.range(of: PromptBuilder.redoLine)?.lowerBound)
        let items = try #require(prompt.range(of: "Capture 1 items")?.lowerBound)
        let name = try #require(prompt.range(of: PromptBuilder.sessionNameLine)?.lowerBound)
        let reading = try #require(prompt.range(of: "How to read the bundle:")?.lowerBound)
        #expect(goal < redo && redo < items && items < name && name < reading)
    }

    @Test("Screen text stays out of the titled round prompt")
    func roundPromptHasNoScreenText() {
        let prompt = PromptBuilder.render(round, folderPath: folder, sessionTitle: true)
        for screenText in ["Pricing | Acme", "Starter $19/mo", "Badge-side text", "Billed annually", "Compare plans", "too much padding"] {
            #expect(!prompt.contains(screenText), "\(screenText) is screen text")
        }
    }

    @Test("The capture prompt gets the name line right after the Goal line")
    func capturePrompt() {
        let capture = FeedbackFixtures.pricingCapture()
        let lines = PromptBuilder.renderCapture(capture, folderPath: folder, sessionTitle: true).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[1].hasPrefix("Goal:"))
        #expect(lines[2] == Substring(PromptBuilder.sessionNameLine))
        let redo = PromptBuilder.renderCapture(capture, folderPath: folder, redo: true, sessionTitle: true).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(redo[2] == Substring(PromptBuilder.redoLine))
        #expect(redo[3] == Substring(PromptBuilder.sessionNameLine))
    }

    @Test("The selection prompt gets the name line after the redo line")
    func selectionPrompt() {
        let lines = PromptBuilder.renderSelection(ZipPlanTests.entries(round), sessionTitle: true).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[1].hasPrefix("Goal:"))
        #expect(lines[2] == Substring(PromptBuilder.redoLine))
        #expect(lines[3] == Substring(PromptBuilder.sessionNameLine))
    }

    @Test("Without the flag no prompt has the name line or the inline items")
    func flagOff() {
        let capture = FeedbackFixtures.pricingCapture()
        let texts = [
            PromptBuilder.render(round, folderPath: folder),
            PromptBuilder.render(round, folderPath: folder, sessionTitle: false),
            PromptBuilder.renderCapture(capture, folderPath: folder),
            PromptBuilder.renderSelection(ZipPlanTests.entries(round)),
        ]
        for text in texts {
            #expect(!text.contains("Session name:"))
            #expect(!text.contains("items (badge N in its image"))
        }
        // The flag-off round prompt is the same text as before the flag existed: it holds no reviewer words.
        #expect(!texts[0].contains("Price is wrong"))
    }

    @Test("The name line names a subject, asks for two to five words, and names no tool")
    func nameLine() {
        let line = PromptBuilder.sessionNameLine
        #expect(!line.contains("\n"))
        #expect(line.contains("noun phrase of two to five words"))
        #expect(line.contains("If your tool lets you rename this session"))
    }
}
