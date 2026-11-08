import CoreGraphics
import Testing
@testable import FeedbackKit

@Suite("HoverPreviewPolicy")
struct HoverPreviewPolicyTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test("The delay is one second")
    func delay() {
        #expect(HoverPreviewPolicy.delay == 1.0)
    }

    // MARK: fit

    @Test("A wide image fills the width of the box")
    func wideImage() {
        let size = HoverPreviewPolicy.fittedSize(of: CGSize(width: 2560, height: 1440))
        #expect(size == CGSize(width: 640, height: 360))
    }

    @Test("A tall image fills the height of the box")
    func tallImage() {
        let size = HoverPreviewPolicy.fittedSize(of: CGSize(width: 600, height: 1200))
        #expect(size == CGSize(width: 240, height: 480))
    }

    @Test("A small image is not enlarged")
    func smallImage() {
        let size = HoverPreviewPolicy.fittedSize(of: CGSize(width: 300, height: 200))
        #expect(size == CGSize(width: 300, height: 200))
    }

    @Test("An image with no size gives no preview size")
    func emptyImage() {
        #expect(HoverPreviewPolicy.fittedSize(of: .zero) == .zero)
        #expect(HoverPreviewPolicy.fittedSize(of: CGSize(width: 100, height: 0)) == .zero)
        #expect(HoverPreviewPolicy.fittedSize(of: CGSize(width: -5, height: 10)) == .zero)
    }

    @Test("The box shrinks to fit a small display")
    func boxOnSmallScreen() {
        let small = CGRect(x: 0, y: 0, width: 500, height: 400)
        #expect(HoverPreviewPolicy.box(on: small) == CGSize(width: 484, height: 384))
        #expect(HoverPreviewPolicy.box(on: screen) == HoverPreviewPolicy.maxSize)
    }

    // MARK: placement

    @Test("The preview sits right of the menu and centers on the row")
    func rightOfMenu() {
        let menu = CGRect(x: 300, y: 400, width: 350, height: 200)
        let origin = HoverPreviewPolicy.origin(
            for: CGSize(width: 640, height: 360), besideMenu: menu, anchorY: 500, in: screen
        )
        #expect(origin == CGPoint(x: 658, y: 320))
    }

    @Test("With no room on the right, the preview sits left of the menu")
    func leftOfMenu() {
        let menu = CGRect(x: 1000, y: 400, width: 350, height: 200)
        let origin = HoverPreviewPolicy.origin(
            for: CGSize(width: 640, height: 360), besideMenu: menu, anchorY: 500, in: screen
        )
        let expected: CGFloat = 352
        #expect(origin.x == expected)
    }

    @Test("A row near the bottom keeps the preview on the display")
    func clampBottom() {
        let menu = CGRect(x: 300, y: 20, width: 350, height: 200)
        let origin = HoverPreviewPolicy.origin(
            for: CGSize(width: 640, height: 480), besideMenu: menu, anchorY: 40, in: screen
        )
        #expect(origin.y == 0)
    }

    @Test("A row near the top keeps the preview on the display")
    func clampTop() {
        let menu = CGRect(x: 300, y: 700, width: 350, height: 190)
        let origin = HoverPreviewPolicy.origin(
            for: CGSize(width: 640, height: 480), besideMenu: menu, anchorY: 880, in: screen
        )
        let expected: CGFloat = 420
        #expect(origin.y == expected)
    }

    @Test("With no room on either side, the preview stays on the display")
    func noRoomEitherSide() {
        let narrow = CGRect(x: 0, y: 0, width: 800, height: 900)
        let menu = CGRect(x: 100, y: 400, width: 350, height: 200)
        let origin = HoverPreviewPolicy.origin(
            for: CGSize(width: 640, height: 360), besideMenu: menu, anchorY: 500, in: narrow
        )
        #expect(origin.x >= narrow.minX)
        #expect(origin.x + 640 <= narrow.maxX)
    }

    @Test("A second display with a nonzero origin")
    func secondDisplay() {
        let right = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let menu = CGRect(x: 3000, y: 300, width: 350, height: 200)
        let origin = HoverPreviewPolicy.origin(
            for: CGSize(width: 640, height: 360), besideMenu: menu, anchorY: 400, in: right
        )
        let expected: CGFloat = 2352
        #expect(origin.x == expected)
        #expect(origin.y >= right.minY)
        #expect(origin.y + 360 <= right.maxY)
    }

    // MARK: Find Capture window (#125)

    @Test("The window preview waits half a second")
    func windowDelay() {
        #expect(HoverPreviewPolicy.windowDelay == 0.5)
    }

    @Test("The window box is the window less its margins")
    func windowBox() {
        let window = CGRect(x: 200, y: 100, width: 1000, height: 700)
        #expect(HoverPreviewPolicy.box(over: window, on: screen) == CGSize(width: 920, height: 620))
    }

    @Test("The window box never passes the display")
    func windowBoxOnSmallDisplay() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 600)
        let window = CGRect(x: 0, y: 0, width: 1200, height: 900)
        #expect(HoverPreviewPolicy.box(over: window, on: small) == CGSize(width: 784, height: 584))
    }

    @Test("A window smaller than its margins gives no box")
    func windowBoxTooSmall() {
        let window = CGRect(x: 0, y: 0, width: 60, height: 60)
        #expect(HoverPreviewPolicy.box(over: window, on: screen) == .zero)
    }

    @Test("The window preview centers on the window")
    func windowCentered() {
        let window = CGRect(x: 200, y: 100, width: 1000, height: 700)
        let origin = HoverPreviewPolicy.origin(for: CGSize(width: 600, height: 400), centeredOn: window, in: screen)
        #expect(origin == CGPoint(x: 400, y: 250))
    }

    @Test("A window near the display edge keeps the preview on the display")
    func windowCenteredClamped() {
        let window = CGRect(x: 1200, y: 700, width: 400, height: 300)
        let origin = HoverPreviewPolicy.origin(for: CGSize(width: 600, height: 400), centeredOn: window, in: screen)
        #expect(origin == CGPoint(x: 840, y: 500))
    }
}
