// App/Feedback/FeedbackNotePanel.swift
import AppKit
import SwiftUI

/// One answer in the note panel: a circle's instruction, or the general note.
enum FeedbackNoteStep: Hashable {
    case circle(Int)
    case note
}

/// Fork: asks for one instruction per circle, then a general note, after
/// each saved feedback capture. Return saves the answer and moves on. Esc
/// skips the current step. The arrow keys move back and forward between
/// steps, and a step shows its saved answer again. After the last step the
/// panel closes and calls `onFinish`. A panel closed early (close button,
/// End Round) does not.
///
/// The panel takes keyboard focus without making the app active, the same
/// setup as `InlineAnnotationEditorWindow`. macOS 27 refuses to activate a
/// menu bar app here (measured 2026-10-20: key=false, appActive=false), so a
/// non-activating key panel is the reliable way to receive typing and
/// dictation (Wispr Flow) while the reviewed app stays active.
@MainActor
final class FeedbackNotePanel {
    /// Width over height of the preview under the answer field.
    static let previewAspectRatio = 1.6
    static let previewWidth: CGFloat = 496

    /// Called when the panel closes, by any path.
    var onClosed: (() -> Void)?

    private var panel: KeyNotePanel?

    var isOpen: Bool { panel != nil }

    /// `previews` holds one crop per circle number. `overview` is the whole
    /// annotated capture, shown with the general note. `onEnd` runs once when
    /// this panel closes by any path, before `onFinish`: the capture's notes
    /// are then final.
    func show(
        title: String,
        badges: [Int],
        previews: [Int: CGImage],
        overview: CGImage?,
        onAnswer: @escaping (FeedbackNoteStep, String) -> Void,
        onFinish: @escaping () -> Void,
        onEnd: @escaping () -> Void = {}
    ) {
        close()

        let model = FeedbackNoteModel(
            steps: badges.map(FeedbackNoteStep.circle) + [.note],
            onAnswer: { step, text in
                FeedbackLog.logger.notice("note answer for \(String(describing: step), privacy: .public): \(text.count) characters")
                onAnswer(step, text)
            },
            onFinish: { [weak self] in
                FeedbackLog.logger.notice("note panel finished")
                self?.close()
                onFinish()
            }
        )
        let panel = KeyNotePanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 110),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        // A panel hides when its app is not active. This is a menu bar app
        // and is usually not active, so the panel must stay visible.
        panel.hidesOnDeactivate = false
        panel.onStep = { delta in model.move(by: delta) }
        panel.onClose = { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel else { return }
            self.panel = nil
            onEnd()
            self.onClosed?()
        }
        let hostingView = NSHostingView(rootView: FeedbackNoteView(
            model: model,
            previews: previews,
            overview: overview
        ))
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)
        panel.center()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        FeedbackLog.logger.notice("note panel shown with \(model.steps.count) steps: visible=\(panel.isVisible) key=\(panel.isKeyWindow) appActive=\(NSApp.isActive)")
    }

    func close() {
        guard let panel else { return }
        FeedbackLog.logger.notice("note panel closing")
        panel.close()
    }
}

/// The steps, the current step, and the answers given so far.
@MainActor
@Observable
final class FeedbackNoteModel {
    let steps: [FeedbackNoteStep]
    private(set) var position = 0
    var text = ""

    @ObservationIgnored private var answers: [FeedbackNoteStep: String] = [:]
    private let onAnswer: (FeedbackNoteStep, String) -> Void
    private let onFinish: () -> Void

    init(
        steps: [FeedbackNoteStep],
        onAnswer: @escaping (FeedbackNoteStep, String) -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.steps = steps
        self.onAnswer = onAnswer
        self.onFinish = onFinish
    }

    var step: FeedbackNoteStep { steps[position] }

    /// Return: saves the answer and goes on.
    func submit() {
        saveAnswer()
        goForwardOrFinish()
    }

    /// Esc: goes on without saving. An answer saved earlier stays.
    func skip() {
        goForwardOrFinish()
    }

    /// Saves the answer and moves `delta` steps. Returns false, and stays,
    /// at the first or last step.
    func move(by delta: Int) -> Bool {
        let target = position + delta
        guard steps.indices.contains(target) else { return false }
        saveAnswer()
        show(target)
        return true
    }

    /// Sends a new or changed answer. A cleared answer is sent as blank text,
    /// which removes it from the capture.
    private func saveAnswer() {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard answer != answers[step, default: ""] else { return }
        answers[step] = answer.isEmpty ? nil : answer
        onAnswer(step, answer)
    }

    private func goForwardOrFinish() {
        if position + 1 < steps.count {
            show(position + 1)
        } else {
            onFinish()
        }
    }

    private func show(_ target: Int) {
        position = target
        text = answers[step, default: ""]
    }
}

private final class KeyNotePanel: NSPanel {
    /// Moves one step back (-1) or forward (+1). Returns false at the first
    /// or last step.
    var onStep: ((Int) -> Bool)?
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func close() {
        super.close()
        onClose?()
    }

    /// Up and Down always move between steps. Left moves back when the
    /// cursor is at the start of the answer, and Right moves on when it is
    /// at the end (Drew, 2026-10-21). Text being composed (dictation, input
    /// methods) keeps its keys.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let delta = stepDelta(for: event), onStep?(delta) == true {
            placeCursor(atStart: delta < 0)
            return
        }
        super.sendEvent(event)
    }

    private func stepDelta(for event: NSEvent) -> Int? {
        // Arrow keys always carry the keypad and fn flags.
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard modifiers.isEmpty else { return nil }
        let field = firstResponder as? NSTextView
        guard field?.hasMarkedText() != true else { return nil }
        let selection = field?.selectedRange() ?? NSRange(location: 0, length: 0)
        let length = ((field?.string ?? "") as NSString).length
        switch event.keyCode {
        case 126: return -1 // Up
        case 125: return 1 // Down
        case 123: return selection == NSRange(location: 0, length: 0) ? -1 : nil // Left
        case 124: return selection == NSRange(location: length, length: 0) ? 1 : nil // Right
        default: return nil
        }
    }

    /// The cursor goes to the start after a step back and to the end after a
    /// step forward, so the same arrow pressed again keeps moving.
    private func placeCursor(atStart: Bool) {
        // SwiftUI puts the step's answer in the field on its next update.
        DispatchQueue.main.async { [weak self] in
            guard let field = self?.firstResponder as? NSTextView else { return }
            let end = (field.string as NSString).length
            field.setSelectedRange(NSRange(location: atStart ? 0 : end, length: 0))
        }
    }
}

private struct FeedbackNoteView: View {
    @Bindable var model: FeedbackNoteModel
    let previews: [Int: CGImage]
    let overview: CGImage?

    @FocusState private var isFocused: Bool

    private var previewImage: CGImage? {
        switch model.step {
        case .circle(let number): previews[number]
        case .note: overview
        }
    }

    private var circleCount: Int {
        model.steps.filter { $0 != .note }.count
    }

    private var question: String {
        switch model.step {
        case .circle(let number):
            "Circle \(number) (\(model.position + 1) of \(circleCount)): what should change?"
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
            TextField(text: $model.text, prompt: Text(verbatim: "Type or dictate, then press Return")) {
                Text(verbatim: "Answer")
            }
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit {
                model.submit()
                isFocused = true
            }
            .onExitCommand {
                model.skip()
                isFocused = true
            }

            Text(verbatim: model.steps.count > 1
                ? "Return saves and goes on. Esc skips this one. Arrow keys go back and forward."
                : "Return saves. Esc skips.")
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
}
