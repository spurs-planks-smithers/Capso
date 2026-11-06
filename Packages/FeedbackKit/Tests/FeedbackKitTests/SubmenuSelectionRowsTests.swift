import Testing
@testable import FeedbackKit

@Suite("SubmenuSelectionRows")
struct SubmenuSelectionRowsTests {
    @Test("Nothing checked: neutral titles, every row off")
    func nothingChecked() {
        let rows = SubmenuSelectionRows(selectedCount: 0, zipEnabled: true)
        #expect(rows.copy == .init(title: "Copy Selected", isEnabled: false))
        #expect(rows.zip == .init(title: "Zip Selected", isEnabled: false))
        #expect(rows.clear == .init(title: "Clear Selection", isEnabled: false))
    }

    @Test("A negative count reads as nothing checked")
    func negativeCount() {
        let rows = SubmenuSelectionRows(selectedCount: -3, zipEnabled: false)
        #expect(rows.copy.title == "Copy Selected")
        #expect(rows.copy.isEnabled == false)
    }

    @Test("One checked capture: count in the titles, every row on")
    func oneChecked() {
        let rows = SubmenuSelectionRows(selectedCount: 1, zipEnabled: true)
        #expect(rows.copy == .init(title: "Copy 1 Selected", isEnabled: true))
        #expect(rows.zip == .init(title: "Zip 1 Selected", isEnabled: true))
        #expect(rows.clear == .init(title: "Clear Selection", isEnabled: true))
    }

    @Test("Many checked captures use the total across rounds")
    func manyChecked() {
        let rows = SubmenuSelectionRows(selectedCount: 12, zipEnabled: true)
        #expect(rows.copy.title == "Copy 12 Selected")
        #expect(rows.zip?.title == "Zip 12 Selected")
    }

    @Test("No zip row when zipHandoff is off")
    func zipOff() {
        #expect(SubmenuSelectionRows(selectedCount: 0, zipEnabled: false).zip == nil)
        #expect(SubmenuSelectionRows(selectedCount: 4, zipEnabled: false).zip == nil)
    }

    @Test("The top-level rows use the same titles")
    func sharedTitles() {
        #expect(SubmenuSelectionRows.copyTitle(3) == "Copy 3 Selected")
        #expect(SubmenuSelectionRows.zipTitle(3) == "Zip 3 Selected")
    }
}
