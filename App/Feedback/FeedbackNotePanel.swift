// App/Feedback/FeedbackNotePanel.swift
import AppKit
import SwiftUI

/// Fork: a one-line note field shown after each saved feedback capture.
/// Return saves the note. Esc skips it.
///
/// The panel makes Capso the active app so the field has keyboard focus.
/// Dictation tools such as Wispr Flow type into the active app's focused
/// field. When the panel closes, the app that was active before gets focus back.
@MainActor
final class FeedbackNotePanel {
    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?

    func show(captureIndex: Int, badges: [Int], onSave: @escaping (String) -> Void) {
        close()
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost

        let hint = badges.isEmpty
            ? "Return saves. Esc skips."
            : "Return saves. Esc skips. Badges: \(badges.map(String.init).joined(separator: ", ")). Start with a badge number for its instruction, for example 1: fix price"
        let panel = KeyNotePanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 90),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Feedback note for capture \(captureIndex)"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        // A panel hides when its app is not active. Capso is a menu bar app
        // and is usually not active, so the panel must stay visible.
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: FeedbackNoteView(
            hint: hint,
            onSubmit: { [weak self] text in
                onSave(text)
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
            }
        ))
        panel.center()
        self.panel = panel
        // Same call upstream uses for its menu bar windows (PreferencesWindow).
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        panel.close()
        self.panel = nil
        previousApp?.activate()
        previousApp = nil
    }
}

private final class KeyNotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct FeedbackNoteView: View {
    let hint: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(text: $text, prompt: Text(verbatim: "1: fix price; cards feel cramped")) {
                Text(verbatim: "Note")
            }
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit { onSubmit(text) }
            .onExitCommand { onCancel() }

            Text(verbatim: hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 480)
        .onAppear { isFocused = true }
    }
}
