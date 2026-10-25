import AppKit
import XCTest
import AnnotationKit
import SharedKit
@testable import Capso

/// A local key monitor consumes a key by returning nil. Two upstream monitors
/// wrote `self?.handle(event) ?? event`, which turned that nil back into the
/// event: tool letters beeped in the editors, and the selection overlay ran
/// Space and Esc twice (Drew, 2026-10-24). These tests send keys through
/// `NSApp.sendEvent`, the path that runs the monitors.
@MainActor
final class KeyMonitorConsumeTests: XCTestCase {
    private var savedTool: String?

    override func setUp() async throws {
        savedTool = UserDefaults.standard.string(forKey: "annotationLastTool")
        UserDefaults.standard.set(AnnotationTool.counter.rawValue, forKey: "annotationLastTool")
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedTool, forKey: "annotationLastTool")
    }

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

    private func keyEvent(
        _ character: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        windowNumber: Int
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func send(_ event: NSEvent) {
        NSApp.sendEvent(event)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    /// Puts a view first in the responder chain that records each key it gets.
    private func installRecorder(in window: NSWindow) throws -> KeyRecorderView {
        let recorder = KeyRecorderView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        window.contentView?.addSubview(recorder)
        XCTAssertTrue(window.makeFirstResponder(recorder))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(window.isKeyWindow)
        return recorder
    }

    private var currentTool: String? {
        UserDefaults.standard.string(forKey: "annotationLastTool")
    }

    func testInlineEditorToolLettersSwitchToolWithoutReachingTheResponderChain() throws {
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
        defer { window.close() }
        window.show()
        let recorder = try installRecorder(in: window)

        for (letter, keyCode, tool) in [("a", UInt16(0), AnnotationTool.arrow), ("r", 15, .rectangle), ("t", 17, .text), ("c", 8, .counter)] {
            try send(keyEvent(letter, keyCode: keyCode, windowNumber: window.windowNumber))
            XCTAssertEqual(currentTool, tool.rawValue, "\(letter) picks its tool")
        }
        XCTAssertEqual(recorder.received, [], "Tool letters stop at the monitor, so nothing beeps")
    }

    /// Shift plus the center-lock key (C by default) recenters a drag, so the
    /// tool monitor leaves that chord alone.
    func testCenterLockChordDoesNotSwitchTheTool() throws {
        UserDefaults.standard.set(AnnotationTool.arrow.rawValue, forKey: "annotationLastTool")
        var copied = false
        let screen = try XCTUnwrap(NSScreen.main)
        let window = InlineAnnotationEditorWindow(
            image: try makeImage(),
            screen: screen,
            screenLocalRect: CGRect(x: 100, y: 100, width: 400, height: 300),
            onSave: { _ in },
            onCopy: { _ in copied = true },
            onPin: { _, _ in },
            onClose: {}
        )
        defer { window.close() }
        window.show()
        let recorder = try installRecorder(in: window)

        try send(keyEvent("C", keyCode: 8, modifiers: .shift, windowNumber: window.windowNumber))
        XCTAssertEqual(currentTool, AnnotationTool.arrow.rawValue)
        XCTAssertFalse(copied)
        XCTAssertTrue(window.isVisible)
        _ = recorder
    }

    func testSelectionOverlayRunsSpaceAndEscOncePerPress() throws {
        let suiteName = "KeyMonitorConsumeTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let screen = try XCTUnwrap(NSScreen.main)
        let window = CaptureOverlayWindow(screen: screen, settings: settings, handlesGlobalKeyEvents: false)
        defer {
            window.deactivate()
            window.close()
        }
        var toggles = 0
        var cancels = 0
        window.onSpaceToggle = { toggles += 1 }
        window.onCancelled = { cancels += 1 }
        window.activate(mode: .area)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        try send(keyEvent(" ", keyCode: 49, windowNumber: window.windowNumber))
        XCTAssertEqual(toggles, 1, "One Space press toggles once")

        try send(keyEvent("\u{1b}", keyCode: 53, windowNumber: window.windowNumber))
        XCTAssertEqual(cancels, 1, "One Esc press cancels once")
    }
}

@MainActor
private final class KeyRecorderView: NSView {
    var received: [String] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        received.append(event.charactersIgnoringModifiers ?? "")
    }
}
