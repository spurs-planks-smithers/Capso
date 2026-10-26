import AppKit
import SwiftUI
import SupportKit

@MainActor
protocol FeedbackSupportPresenting: AnyObject {
    var onSubmit: ((String, String) -> Void)? { get set }
    var onClosed: (() -> Void)? { get set }
    func show(captureCount: Int)
    func bringForward()
    func setSending(_ status: String)
    func fail(_ status: String, prepared: Bool)
    func received(_ identifier: String)
}

@MainActor
final class FeedbackSupportPanel: FeedbackSupportPresenting {
    var onSubmit: ((String, String) -> Void)?
    var onClosed: (() -> Void)?
    private var panel: SupportKeyPanel?
    private let model = SupportPanelModel()

    func show(captureCount: Int) {
        model.captureCount = captureCount
        let panel = SupportKeyPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 290), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Submit Round to Nextshot"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.onClose = { [weak self] in self?.panel = nil; self?.onClosed?() }
        let view = SupportPanelView(model: model, submit: { [weak self] in
            guard let self else { return }
            self.onSubmit?(self.model.note.trimmingCharacters(in: .whitespaces), self.model.email.trimmingCharacters(in: .whitespaces))
        }, close: { [weak panel] in panel?.close() })
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.center()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func bringForward() { panel?.makeKeyAndOrderFront(nil) }
    func setSending(_ status: String) { model.sending = true; model.locked = true; model.status = status; model.failed = false }
    func fail(_ status: String, prepared: Bool) { model.sending = false; model.locked = prepared; model.status = status; model.failed = true }
    func received(_ identifier: String) {
        model.sending = false
        model.done = true
        model.locked = true
        model.failed = false
        model.status = "Received: \(identifier.prefix(12)). Screening is pending."
    }
}

@MainActor @Observable
private final class SupportPanelModel {
    var note = ""
    var email = ""
    var captureCount = 0
    var sending = false
    var locked = false
    var failed = false
    var done = false
    var status = ""
}

private struct SupportPanelView: View {
    @Bindable var model: SupportPanelModel
    let submit: () -> Void
    let close: () -> Void
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Send feedback to Nextshot").font(.system(size: 18, weight: .semibold))
            Text("Send this round's annotated screenshots and notes to Nextshot on Cloudflare for screening. Clean copies and stored screen text stay on your Mac.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Additional note (optional)").font(.system(size: 12, weight: .medium))
                TextField("What should we know?", text: $model.note).textFieldStyle(.roundedBorder).focused($noteFocused)
                    .disabled(model.locked).onChange(of: model.note) { _, value in
                        model.note = String(value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").prefix(SupportLimits.noteCharacters))
                    }
                TextField("Email for a reply (optional)", text: $model.email).textFieldStyle(.roundedBorder).disabled(model.locked)
            }
            if !model.status.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    if model.sending { ProgressView().controlSize(.small) }
                    Text(model.status).font(.system(size: 12)).foregroundStyle(model.failed ? Color.orange : Color.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            HStack {
                Text("\(model.captureCount) saved capture\(model.captureCount == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(model.done ? "Close" : "Cancel", action: close).keyboardShortcut(.cancelAction)
                if !model.done {
                    Button(model.failed && model.locked ? "Retry" : "Submit", action: submit).keyboardShortcut(.defaultAction).disabled(model.sending)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { noteFocused = true }
    }
}

private final class SupportKeyPanel: NSPanel {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func close() { super.close(); onClose?() }
}
