// App/Feedback/FeedbackNotePanel.swift
import AppKit
import SwiftUI

/// One answer in the note panel: a circle's instruction, or the general note.
enum FeedbackNoteStep: Equatable {
    case circle(Int)
    case note
}

/// Fork: asks for one instruction per circle, then a general note, after
/// each saved feedback capture. Return saves the answer and moves on. Esc
/// skips the current step. After the last step the panel closes and calls
/// `onFinish`. A panel closed early (close button, End Session) does not.
///
/// The panel takes keyboard focus without making Capso the active app, the
/// same setup as `InlineAnnotationEditorWindow`. macOS 27 refuses to activate
/// a menu bar app here (measured 2026-10-20: key=false, appActive=false), so
/// a non-activating key panel is the reliable way to receive typing and
/// dictation (Wispr Flow) while the reviewed app stays active.
@MainActor
final class FeedbackNotePanel {
    /// Width over height of the preview under the answer field.
    static let previewAspectRatio = 1.6
    static let previewWidth: CGFloat = 496

    private var panel: NSPanel?

    /// `previews` holds one crop per circle number. `overview` is the whole
    /// annotated capture, shown with the general note.
    func show(
        title: String,
        badges: [Int],
        previews: [Int: CGImage],
        overview: CGImage?,
        onAnswer: @escaping (FeedbackNoteStep, String) -> Void,
        onFinish: @escaping () -> Void
    ) {
        close()

        let steps = badges.map(FeedbackNoteStep.circle) + [.note]
        let panel = KeyNotePanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 110),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        // A panel hides when its app is not active. Capso is a menu bar app
        // and is usually not active, so the panel must stay visible.
        panel.hidesOnDeactivate = false
        let hostingView = NSHostingView(rootView: FeedbackNoteView(
            steps: steps,
            previews: previews,
            overview: overview,
            onAnswer: { step, text in
                FeedbackLog.logger.notice("note answer for \(String(describing: step), privacy: .public): \(text.count) characters")
                onAnswer(step, text)
            },
            onFinish: { [weak self] in
                FeedbackLog.logger.notice("note panel finished")
                self?.close()
                onFinish()
            }
        ))
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        panel.center()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        FeedbackLog.logger.notice("note panel shown with \(steps.count) steps: visible=\(panel.isVisible) key=\(panel.isKeyWindow) appActive=\(NSApp.isActive)")
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
    let steps: [FeedbackNoteStep]
    let previews: [Int: CGImage]
    let overview: CGImage?
    let onAnswer: (FeedbackNoteStep, String) -> Void
    let onFinish: () -> Void

    private var previewImage: CGImage? {
        switch steps[position] {
        case .circle(let number): previews[number]
        case .note: overview
        }
    }

    @State private var position = 0
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var circleCount: Int {
        steps.filter { $0 != .note }.count
    }

    private var question: String {
        switch steps[position] {
        case .circle(let number):
            "Circle \(number) (\(position + 1) of \(circleCount)): what should change?"
        case .note:
            circleCount == 0
                ? "What should change in this capture?"
                : "Anything else about this capture? (optional)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: question)
                .font(.headline)
            TextField(text: $text, prompt: Text(verbatim: "Type or dictate, then press Return")) {
                Text(verbatim: "Answer")
            }
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit { advance(saving: true) }
            .onExitCommand { advance(saving: false) }

            Text(verbatim: "Return saves and goes on. Esc skips this one.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // The circle in the middle with what surrounds it, so the
            // question is easy to match to the mark.
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .underPageBackgroundColor))
                if let previewImage {
                    Image(decorative: previewImage, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            }
            .frame(
                width: FeedbackNotePanel.previewWidth,
                height: FeedbackNotePanel.previewWidth / FeedbackNotePanel.previewAspectRatio
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
        .padding(12)
        .frame(width: 520)
        .onAppear { isFocused = true }
    }

    private func advance(saving: Bool) {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if saving, !answer.isEmpty {
            onAnswer(steps[position], answer)
        }
        text = ""
        if position + 1 < steps.count {
            position += 1
            isFocused = true
        } else {
            onFinish()
        }
    }
}
