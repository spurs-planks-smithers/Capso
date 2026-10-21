// App/Feedback/FeedbackNotePanel.swift
import AppKit
import SwiftUI

/// Fork: a one-line note field shown after each saved feedback capture.
/// Return saves the note. Esc skips it.
///
/// The panel takes keyboard focus without making Capso the active app, the
/// same setup as `InlineAnnotationEditorWindow`. macOS 27 refuses to activate
/// a menu bar app here (measured 2026-10-20: key=false, appActive=false), so
/// a non-activating key panel is the reliable way to receive typing and
/// dictation (Wispr Flow) while the reviewed app stays active.
@MainActor
final class FeedbackNotePanel {
    private var panel: NSPanel?

    func show(captureIndex: Int, badges: [Int], onSave: @escaping (String) -> Void) {
        close()

        let hint = badges.isEmpty
            ? "Return saves. Esc skips."
            : "Return saves. Esc skips. Badges: \(badges.map(String.init).joined(separator: ", ")). Start with a badge number for its instruction, for example 1: fix price"
        let panel = KeyNotePanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 90),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
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
                FeedbackLog.logger.notice("note submitted, \(text.count) characters")
                onSave(text)
                self?.close()
            },
            onCancel: { [weak self] in
                FeedbackLog.logger.notice("note skipped with Esc")
                self?.close()
            }
        ))
        panel.center()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        FeedbackLog.logger.notice("note panel shown: visible=\(panel.isVisible) key=\(panel.isKeyWindow) appActive=\(NSApp.isActive)")
    }

    func close() {
        guard let panel else { return }
        FeedbackLog.logger.notice("note panel closing")
        panel.close()
        self.panel = nil
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
