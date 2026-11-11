import Foundation
import Testing
@testable import FeedbackKit

/// The bar at the bottom of the Find Capture window (#125).
@Suite("FindCaptureBar")
struct FindCaptureBarTests {
    private func actions(_ bar: FindCaptureBar) -> [FindCaptureBar.Action] {
        bar.buttons.map(\.action)
    }

    @Test("Selection mode shows the count, Copy, Zip with the flag, and Clear")
    func selectionMode() {
        let withZip = FindCaptureBar(roundName: nil, selectedCount: 3, zipEnabled: true, roundActive: false)
        #expect(withZip.label == "3 selected")
        #expect(actions(withZip) == [.copySelected, .zipSelected, .clearSelection])
        #expect(withZip.buttons.map(\.title) == ["Copy 3 Selected", "Zip 3 Selected", "Clear"])
        #expect(withZip.buttons.allSatisfy { $0.isEnabled })

        let noZip = FindCaptureBar(roundName: nil, selectedCount: 3, zipEnabled: false, roundActive: true)
        #expect(actions(noZip) == [.copySelected, .clearSelection])
    }

    @Test("With nothing checked, the selection buttons stay and are off")
    func emptySelection() {
        let bar = FindCaptureBar(roundName: nil, selectedCount: 0, zipEnabled: true, roundActive: false)
        #expect(bar.label == "0 selected")
        #expect(actions(bar) == [.copySelected, .zipSelected, .clearSelection])
        #expect(bar.buttons.allSatisfy { !$0.isEnabled })
    }

    @Test("Round mode shows Back, Copy Round Prompt, Zip with the flag, Open Folder, and Resume with no active round")
    func roundMode() {
        let idle = FindCaptureBar(roundName: "Pricing page", selectedCount: 2, zipEnabled: true, roundActive: false)
        #expect(idle.label == "Pricing page")
        #expect(actions(idle) == [.back, .copyRoundPrompt, .zipRound, .openFolder, .resumeRound])
        #expect(idle.buttons.allSatisfy { $0.isEnabled })

        let active = FindCaptureBar(roundName: "Pricing page", selectedCount: 2, zipEnabled: true, roundActive: true)
        #expect(actions(active) == [.back, .copyRoundPrompt, .zipRound, .openFolder])

        let noZip = FindCaptureBar(roundName: "Pricing page", selectedCount: 0, zipEnabled: false, roundActive: false)
        #expect(actions(noZip) == [.back, .copyRoundPrompt, .openFolder, .resumeRound])
    }

    @Test("An imported round never offers Resume, because its captures keep another Mac's coordinates")
    func importedRoundHasNoResume() {
        let imported = FindCaptureBar(
            roundName: "Pricing page", selectedCount: 2, zipEnabled: true,
            roundActive: false, roundImported: true
        )
        #expect(actions(imported) == [.back, .copyRoundPrompt, .zipRound, .openFolder])

        // The default keeps every caller that predates #87 on the old rows.
        let plain = FindCaptureBar(roundName: "Pricing page", selectedCount: 2, zipEnabled: true, roundActive: false)
        #expect(actions(plain) == [.back, .copyRoundPrompt, .zipRound, .openFolder, .resumeRound])
    }
}
