// App/Feedback/FeedbackShortcutPanel.swift
import AppKit
import KeyboardShortcuts
import SwiftUI

/// Fork: records the feedback capture shortcut. It lives here so the upstream
/// Shortcuts settings tab stays unchanged.
@MainActor
final class FeedbackShortcutPanel {
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 70),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Feedback Shortcut"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: FeedbackShortcutView())
        panel.center()
        return panel
    }()

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct FeedbackShortcutView: View {
    var body: some View {
        HStack {
            Text(verbatim: "Capture into feedback session:")
            KeyboardShortcuts.Recorder(for: .feedbackCapture)
        }
        .padding(16)
    }
}
