import AppKit
import QuickLookUI
import SwiftUI

/// Fork: the Find Capture window (#125). It owns one panel, made at the first
/// show and kept when it closes, so the search and the filters stay for the
/// next open. Opening it starts no capture, no request, and no optional
/// service.
@MainActor
final class ScreenshotHistoryWindow: NSObject, NSWindowDelegate {
    let presentation = ScreenshotHistoryPresentation()
    private let actions: FindCaptureActions
    private var window: NSPanel?
    /// Runs each time the window becomes key, so the list reloads.
    var onBecomeKey: (() -> Void)?

    var isVisible: Bool { window?.isVisible == true }

    init(actions: FindCaptureActions) {
        self.actions = actions
    }

    func show() {
        if window == nil {
            // Not a nonactivating panel: the search field needs real keyboard focus.
            let panel = ScreenshotHistoryPanel(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Find Capture"
            panel.minSize = NSSize(width: 760, height: 560)
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: ScreenshotHistoryView(
                presentation: presentation,
                actions: actions
            ))
            panel.center()
            window = panel
        }
        // This is a menu bar app, so it is not active when the menu row runs.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        presentation.focusRequest &+= 1
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey?()
    }
}

private final class ScreenshotHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Esc closes the window, also while the search field has focus. A text
    /// field that composes text with an input method keeps its Esc.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           (firstResponder as? NSTextView)?.hasMarkedText() != true {
            cancelOperation(nil)
            return
        }
        super.sendEvent(event)
    }

    /// Quick Look takes Esc first while its panel shows.
    override func cancelOperation(_ sender: Any?) {
        if QLPreviewPanel.sharedPreviewPanelExists(), let preview = QLPreviewPanel.shared(), preview.isVisible {
            preview.orderOut(nil)
            return
        }
        close()
    }
}
