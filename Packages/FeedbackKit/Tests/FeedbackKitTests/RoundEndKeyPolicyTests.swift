import Testing
@testable import FeedbackKit

@Suite("RoundEndKeyPolicy")
struct RoundEndKeyPolicyTests {
    @Test("Allows the end keys with nothing open")
    func nothingOpen() {
        #expect(RoundEndKeyPolicy.allows(selectionActive: false, editorOpen: false, screenshotBusy: false, notePanelOpen: false))
    }

    @Test("Allows the end keys while only the note panel is open (#266)")
    func notePanelOnly() {
        #expect(RoundEndKeyPolicy.allows(selectionActive: false, editorOpen: false, screenshotBusy: false, notePanelOpen: true))
    }

    @Test("Refuses the end keys during a selection, in an editor, or while a screenshot is busy (#25)")
    func unsavedCapture() {
        #expect(!RoundEndKeyPolicy.allows(selectionActive: true, editorOpen: false, screenshotBusy: false, notePanelOpen: false))
        #expect(!RoundEndKeyPolicy.allows(selectionActive: false, editorOpen: true, screenshotBusy: false, notePanelOpen: false))
        #expect(!RoundEndKeyPolicy.allows(selectionActive: false, editorOpen: false, screenshotBusy: true, notePanelOpen: false))
        #expect(!RoundEndKeyPolicy.allows(selectionActive: false, editorOpen: true, screenshotBusy: false, notePanelOpen: true))
    }
}
