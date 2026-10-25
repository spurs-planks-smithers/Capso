import AnnotationKit
import AppKit
import SwiftUI

/// A small pill inside the top of a fresh capture: "Click anywhere to add your
/// first red dot". It shows when the capture still has no mark after `delay`,
/// for a reviewer who did not read the help box (Drew, 2026-10-24). It hides at
/// the first mark, when the tool leaves the counter, or when the editor closes.
/// Clicks pass through it to the canvas, and `sharingType = .none` keeps it out
/// of screenshots, as the help box does.
@MainActor
final class FeedbackFirstDotHint {
    static let delay: Duration = .seconds(2)
    /// The view has 10 points of clear padding for its shadow, so the pill
    /// itself shows 14 points below the capture's top edge.
    static let topInset: CGFloat = 4

    private var panel: NSPanel?
    private var task: Task<Void, Never>?

    /// `captureFrame` is the capture in global AppKit coordinates.
    func schedule(for document: AnnotationDocument, captureFrame: CGRect, above editor: NSWindow) {
        cancel()
        task = Task { @MainActor [weak self, weak editor] in
            try? await Task.sleep(for: Self.delay)
            guard let self, let editor, !Task.isCancelled,
                  Self.isWaitingForFirstDot(document: document, editor: editor) else { return }
            self.show(captureFrame: captureFrame, above: editor)
            while !Task.isCancelled, Self.isWaitingForFirstDot(document: document, editor: editor) {
                try? await Task.sleep(for: .milliseconds(200))
            }
            self.hide()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        hide()
    }

    private static func isWaitingForFirstDot(document: AnnotationDocument, editor: NSWindow) -> Bool {
        editor.isVisible
            && document.objects.isEmpty
            && UserDefaults.standard.string(forKey: FeedbackDefaultTool.key) == AnnotationTool.counter.rawValue
    }

    /// Centered on the capture, `topInset` below its top edge. A capture too
    /// short for that gets the pill on its center.
    static func frame(forSize size: CGSize, in captureFrame: CGRect) -> CGRect {
        let x = captureFrame.midX - size.width / 2
        let y = captureFrame.height >= size.height + topInset * 2
            ? captureFrame.maxY - topInset - size.height
            : captureFrame.midY - size.height / 2
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    private func show(captureFrame: CGRect, above editor: NSWindow) {
        let host = NSHostingView(rootView: FeedbackFirstDotHintView())
        let size = host.fittingSize
        let panel = NSPanel(
            contentRect: Self.frame(forSize: size, in: captureFrame),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = editor.level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.alphaValue = 0
        panel.order(.above, relativeTo: editor.windowNumber)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        FeedbackLog.logger.notice("first dot hint shown")
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct FeedbackFirstDotHintView: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: .systemRed))
                .frame(width: 10, height: 10)
            Text(verbatim: "Click anywhere to add your first red dot")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .padding(10)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .fixedSize()
    }
}
