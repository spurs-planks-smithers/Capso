import Foundation
import Testing
@testable import FeedbackKit

/// The pointer lines that a Jev feature in the on state adds to a copied
/// prompt. Without `refined`, every prompt stays byte-identical.
@Suite("Refined pointer lines")
struct RefinedPointerTests {
    let folder = "/Users/test/Library/Application Support/Nextshot/2026-10-24-1028-feedback"

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    @Test("Without refined, both prompts are unchanged")
    func defaultIsUnchanged() {
        let capture = FeedbackFixtures.pricingCapture()
        let round = FeedbackFixtures.round(captures: [capture])
        #expect(PromptBuilder.render(round, folderPath: folder) == PromptBuilder.render(round, folderPath: folder, refined: false))
        #expect(PromptBuilder.renderCapture(capture, folderPath: folder) == PromptBuilder.renderCapture(capture, folderPath: folder, refined: false))
        #expect(!PromptBuilder.render(round, folderPath: folder).contains("refined"))
        #expect(!PromptBuilder.renderCapture(capture, folderPath: folder).contains("refined"))
    }

    @Test("The capture prompt lists the refined file after the manifest, and adds one Authority line")
    func capturePointer() throws {
        let capture = FeedbackFixtures.pricingCapture()
        let plain = lines(PromptBuilder.renderCapture(capture, folderPath: folder))
        let refined = lines(PromptBuilder.renderCapture(capture, folderPath: folder, refined: true))

        let pointer = "- `\(folder)/\(PromptBuilder.refinedFile(for: capture))` if it exists (automated labels for these items; the items below win)"
        let pointerIndex = try #require(refined.firstIndex(of: pointer))
        #expect(refined[pointerIndex - 1].hasPrefix("- `\(folder)/manifest.md`"))
        #expect(refined.contains(PromptBuilder.refinedAuthorityLine))
        #expect(refined.filter { $0 != pointer && $0 != PromptBuilder.refinedAuthorityLine } == plain)
    }

    @Test("The round prompt adds step 6 for refined.md, and one Authority line")
    func roundPointer() throws {
        let round = FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture()])
        let plain = lines(PromptBuilder.render(round, folderPath: folder))
        let refined = lines(PromptBuilder.render(round, folderPath: folder, refined: true))

        let step = "6. If `\(folder)/refined.md` exists, read it after manifest.md. It holds automated labels. The written instructions win over it."
        let stepIndex = try #require(refined.firstIndex(of: step))
        #expect(refined[stepIndex - 1].hasPrefix("5. "))
        #expect(refined.filter { $0 != step && $0 != PromptBuilder.refinedAuthorityLine } == plain)
    }

    @Test("The refined file name follows the capture's file stem")
    func refinedFileName() {
        #expect(PromptBuilder.refinedFile(for: FeedbackFixtures.pricingCapture()).hasSuffix("-refined.md"))
        var capture = FeedbackFixtures.pricingCapture()
        capture.imageFile = "1028-claude.png"
        #expect(PromptBuilder.refinedFile(for: capture) == "1028-claude-refined.md")
    }
}
