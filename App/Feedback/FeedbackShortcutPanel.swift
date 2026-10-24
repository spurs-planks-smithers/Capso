// App/Feedback/FeedbackShortcutPanel.swift
import AppKit
import KeyboardShortcuts
import SwiftUI

/// Fork: records the start round shortcut (Option+Shift+F) only. Settings >
/// Shortcuts lists all the Nextshot keys (Drew, 2026-10-24).
@MainActor
final class FeedbackShortcutPanel {
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 70),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Change Start Round Shortcut"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        return panel
    }()
    private var centered = false

    /// A new view each time, so a reason from an earlier refusal does not
    /// show again. With `.preferredContentSize`, the panel takes the view's
    /// size and grows when the refusal line shows.
    func show() {
        let controller = NSHostingController(rootView: FeedbackShortcutView())
        controller.sizingOptions = .preferredContentSize
        panel.contentViewController = controller
        panel.setContentSize(controller.view.fittingSize)
        if !centered {
            panel.center()
            centered = true
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct FeedbackShortcutView: View {
    /// Why the last key was refused (#24).
    @State private var refusal: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: "Start round or capture area:")
                KeyboardShortcuts.Recorder(for: .feedbackCapture) { shortcut in
                    refusal = FeedbackShortcutGuard.check(shortcut, for: .feedbackCapture, label: "The start key")
                }
            }
            if let refusal {
                Text(verbatim: refusal)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 328, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }
}
