import Foundation
import Testing
@testable import FeedbackKit

/// The prompt is the product, so a parameter that leaks into it when off is a
/// regression every user feels. Each of these parameters changes the copied
/// prompt only when it is set: at its off value the render is byte-identical
/// to the call with no argument at all.
///
/// A parameter that never changed anything would also pass that check, so each
/// test below also proves the parameter does change the prompt when set. The
/// two halves together say "off is inert" and "on is real", which is what a
/// flag rollout needs.
@Suite("Render parameters are inert when off")
struct RenderParameterTests {
    let folder = "/Users/test/Library/Application Support/Nextshot/2026-10-20-1912-pricing-page"
    var capture: FeedbackCapture { FeedbackFixtures.pricingCapture() }
    var round: FeedbackRound { FeedbackFixtures.round(captures: [capture]) }
    var entry: FeedbackSelectionEntry {
        FeedbackSelectionEntry(round: round, capture: capture, folderPath: folder)
    }

    /// A summary that names this round, so `summaries` has something to add.
    private var namingSummary: SummaryNames {
        var names = SummaryNames()
        if let input = SummaryNames.input(of: round.captures) {
            names.set("Pricing card spacing", forInput: input)
        }
        return names
    }

    private var lanes: PromptLanes {
        PromptLanes(laneA: [], laneB: [], askFirst: ["2.1"], layout: .order)
    }

    @Test("Every off value renders the same bytes as no argument at all")
    func allOffMatchesDefaults() {
        let roundDefault = PromptBuilder.render(round, folderPath: folder)
        #expect(PromptBuilder.render(
            round, folderPath: folder,
            redo: false, refined: false, lanes: nil, sessionTitle: false, summaries: .none, linkedPlan: false
        ) == roundDefault)
        #expect(PromptBuilder.render(round, folderPath: folder, redo: false) == roundDefault)
        #expect(PromptBuilder.render(round, folderPath: folder, refined: false) == roundDefault)
        #expect(PromptBuilder.render(round, folderPath: folder, lanes: nil) == roundDefault)
        #expect(PromptBuilder.render(round, folderPath: folder, sessionTitle: false) == roundDefault)
        #expect(PromptBuilder.render(round, folderPath: folder, summaries: .none) == roundDefault)
        #expect(PromptBuilder.render(round, folderPath: folder, linkedPlan: false) == roundDefault)

        let captureDefault = PromptBuilder.renderCapture(capture, folderPath: folder)
        #expect(PromptBuilder.renderCapture(capture, folderPath: folder, redo: false) == captureDefault)
        #expect(PromptBuilder.renderCapture(capture, folderPath: folder, refined: false) == captureDefault)
        #expect(PromptBuilder.renderCapture(capture, folderPath: folder, sessionTitle: false) == captureDefault)
        #expect(PromptBuilder.renderCapture(capture, folderPath: folder, summaries: .none) == captureDefault)
        #expect(PromptBuilder.renderCapture(capture, folderPath: folder, linkedPlan: false) == captureDefault)

        let selectionDefault = PromptBuilder.renderSelection([entry])
        #expect(PromptBuilder.renderSelection([entry], sessionTitle: false) == selectionDefault)
        #expect(PromptBuilder.renderSelection([entry], summaries: .none) == selectionDefault)
        #expect(PromptBuilder.renderSelection([entry], linkedPlan: false) == selectionDefault)
    }

    @Test("Each parameter changes its prompt when it is set")
    func eachParameterIsReal() {
        #expect(PromptBuilder.render(round, folderPath: folder, redo: true) != PromptBuilder.render(round, folderPath: folder))
        #expect(PromptBuilder.render(round, folderPath: folder, refined: true) != PromptBuilder.render(round, folderPath: folder))
        #expect(PromptBuilder.render(round, folderPath: folder, lanes: lanes) != PromptBuilder.render(round, folderPath: folder))
        #expect(PromptBuilder.render(round, folderPath: folder, sessionTitle: true) != PromptBuilder.render(round, folderPath: folder))
        #expect(PromptBuilder.render(round, folderPath: folder, linkedPlan: true) != PromptBuilder.render(round, folderPath: folder))
        #expect(PromptBuilder.renderCapture(capture, folderPath: folder, redo: true) != PromptBuilder.renderCapture(capture, folderPath: folder))
        #expect(PromptBuilder.renderCapture(capture, folderPath: folder, sessionTitle: true) != PromptBuilder.renderCapture(capture, folderPath: folder))
        #expect(PromptBuilder.renderSelection([entry], sessionTitle: true) != PromptBuilder.renderSelection([entry]))
        #expect(PromptBuilder.renderSelection([entry], linkedPlan: true) != PromptBuilder.renderSelection([entry]))
    }

    @Test("redo adds exactly one line, after the Goal line, in both layouts")
    func redoAddsOneLine() throws {
        for linkedPlan in [false, true] {
            let plain = PromptBuilder.render(round, folderPath: folder, linkedPlan: linkedPlan).components(separatedBy: "\n")
            let redo = PromptBuilder.render(round, folderPath: folder, redo: true, linkedPlan: linkedPlan).components(separatedBy: "\n")
            let index = try #require(redo.firstIndex(of: PromptBuilder.redoLine))
            #expect(redo[index - 1].hasPrefix("Goal: "))
            #expect(redo.filter { $0 != PromptBuilder.redoLine } == plain)
        }
        #expect(!PromptBuilder.render(round, folderPath: folder).contains(PromptBuilder.redoLine))
    }

    @Test("summaries change nothing without sessionTitle, which owns the first line")
    func summariesNeedSessionTitle() throws {
        #expect(namingSummary.name(for: round.captures) != nil)
        // The names are set, and the prompt is still exactly the default one:
        // only the session name line would show a name, and it is off.
        let withSummary = PromptBuilder.render(round, folderPath: folder, summaries: namingSummary)
        #expect(withSummary == PromptBuilder.render(round, folderPath: folder))
        #expect(!withSummary.contains("Session Name:"))
        #expect(!withSummary.contains("Pricing card spacing"))
    }

    @Test("sessionTitle alone cuts the reviewer's words and adds the session name line")
    func sessionTitleUsesReviewerWords() {
        let text = PromptBuilder.render(round, folderPath: folder, sessionTitle: true)
        #expect(text.hasPrefix("Session Name: "))
        #expect(text.contains(PromptBuilder.sessionNameLine))
        #expect(!text.contains("Pricing Card Spacing")) // no model name was stored
        // With a stored name and sessionTitle on, the name is the summary.
        let named = PromptBuilder.render(round, folderPath: folder, sessionTitle: true, summaries: namingSummary)
        #expect(named.hasPrefix("Session Name: "))
        #expect(named != text)
    }

    @Test("linkedPlan ignores lanes: the two layouts never both apply")
    func linkedPlanIgnoresLanes() {
        #expect(PromptBuilder.render(round, folderPath: folder, lanes: lanes, linkedPlan: true)
            == PromptBuilder.render(round, folderPath: folder, linkedPlan: true))
    }

    @Test("A selection prompt always carries the redo line, because it is never the first pass")
    func selectionAlwaysHasRedo() {
        // The selection has no redo parameter on purpose: a capture checked in
        // the menu may already have been pasted once. The round and capture
        // prompts take one, so the app can leave it out of the bundle files.
        #expect(PromptBuilder.renderSelection([entry]).contains(PromptBuilder.redoLine))
        #expect(PromptBuilder.renderSelection([entry], linkedPlan: true).contains(PromptBuilder.redoLine))
    }
}
