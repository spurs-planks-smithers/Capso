import AppKit
import XCTest
import AnnotationKit
@testable import Capso

/// In a feedback round the Left and Right arrows undo and redo marks in the
/// inline editor (`FeedbackController.stepHistory`). A synthetic Command+Z
/// key event could not do it: Shift+Command+Z never reached the Redo button.
@MainActor
final class FeedbackEditorArrowKeyTests: XCTestCase {
    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 400,
            height: 300,
            bitsPerComponent: 8,
            bytesPerRow: 400 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    private func makeWindow() throws -> InlineAnnotationEditorWindow {
        let screen = try XCTUnwrap(NSScreen.main)
        let window = InlineAnnotationEditorWindow(
            image: try makeImage(),
            screen: screen,
            screenLocalRect: CGRect(x: 100, y: 100, width: 400, height: 300),
            onSave: { _ in },
            onCopy: { _ in },
            onPin: { _, _ in },
            onClose: {}
        )
        window.show()
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    private func firstCanvas(in view: NSView?) -> AnnotationCanvasNSView? {
        guard let view else { return nil }
        if let canvas = view as? AnnotationCanvasNSView { return canvas }
        for subview in view.subviews {
            if let canvas = firstCanvas(in: subview) { return canvas }
        }
        return nil
    }

    private func addTwoCounters(to window: InlineAnnotationEditorWindow) {
        window.document.addObject(CounterObject(center: CGPoint(x: 50, y: 50), number: 1))
        window.document.addObject(CounterObject(center: CGPoint(x: 150, y: 150), number: 2))
    }

    func testRedoBringsBackTheMarkThatUndoRemoved() throws {
        let window = try makeWindow()
        defer { window.close() }
        addTwoCounters(to: window)

        XCTAssertTrue(FeedbackController.stepHistory(of: window, redo: false))
        XCTAssertEqual(window.document.objects.count, 1, "Left arrow undoes the second counter")

        XCTAssertTrue(FeedbackController.stepHistory(of: window, redo: true))
        XCTAssertEqual(window.document.objects.count, 2, "Right arrow brings the second counter back")
        XCTAssertEqual((window.document.objects.last as? CounterObject)?.number, 2)
    }

    func testStepWithNothingToStepThroughReturnsFalseSoTheKeyBeeps() throws {
        let window = try makeWindow()
        defer { window.close() }
        addTwoCounters(to: window)

        XCTAssertFalse(FeedbackController.stepHistory(of: window, redo: true), "Nothing to redo yet")
        XCTAssertTrue(FeedbackController.stepHistory(of: window, redo: false))
        XCTAssertTrue(FeedbackController.stepHistory(of: window, redo: false))
        XCTAssertFalse(FeedbackController.stepHistory(of: window, redo: false), "Nothing left to undo")
        XCTAssertEqual(window.document.objects.count, 0)
    }

    func testStepRedrawsTheCanvas() throws {
        let window = try makeWindow()
        defer { window.close() }
        addTwoCounters(to: window)
        let canvas = try XCTUnwrap(firstCanvas(in: window.contentView))

        canvas.needsDisplay = false
        XCTAssertTrue(FeedbackController.stepHistory(of: window, redo: false))
        XCTAssertTrue(canvas.needsDisplay, "Undo marks the canvas for redraw")

        canvas.needsDisplay = false
        XCTAssertTrue(FeedbackController.stepHistory(of: window, redo: true))
        XCTAssertTrue(canvas.needsDisplay, "Redo marks the canvas for redraw")
    }
}
