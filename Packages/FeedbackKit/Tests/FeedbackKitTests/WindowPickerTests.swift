import CoreGraphics
import Testing
@testable import FeedbackKit

@Suite("WindowPicker")
struct WindowPickerTests {
    private let ownPID: Int32 = 100
    /// Front to back, as CGWindowListCopyWindowInfo returns them.
    private let windows = [
        ScreenWindow(pid: 100, layer: 0, bounds: CGRect(x: 0, y: 0, width: 3000, height: 2000), title: "Selection overlay", ownerName: "Capso"),
        ScreenWindow(pid: 200, layer: 24, bounds: CGRect(x: 0, y: 0, width: 3000, height: 30), title: "Menubar", ownerName: "Window Server"),
        ScreenWindow(pid: 300, layer: 0, bounds: CGRect(x: 100, y: 100, width: 800, height: 600), title: "Pricing | Acme", ownerName: "Safari"),
        ScreenWindow(pid: 400, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1500, height: 1000), title: "Notes", ownerName: "Notes"),
    ]

    @Test("Picks the frontmost normal window under the point and skips Capso's own windows")
    func picksFrontWindow() {
        let window = WindowPicker.window(at: CGPoint(x: 400, y: 400), in: windows, excludingPID: ownPID)
        #expect(window?.title == "Pricing | Acme")
        #expect(window?.ownerName == "Safari")
    }

    @Test("Picks the window behind when the point is outside the front window")
    func picksWindowBehind() {
        let window = WindowPicker.window(at: CGPoint(x: 1200, y: 800), in: windows, excludingPID: ownPID)
        #expect(window?.title == "Notes")
    }

    @Test("Returns nil when no normal window covers the point")
    func noWindow() {
        #expect(WindowPicker.window(at: CGPoint(x: 2900, y: 1900), in: windows, excludingPID: ownPID) == nil)
    }
}
