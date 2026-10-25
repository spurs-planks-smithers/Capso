import AppKit
import QuartzCore

/// A light blur of the screen around a feedback capture and a soft shadow
/// under it, so the capture reads as ready to mark on a busy screen (Drew,
/// 2026-10-24).
///
/// The panel sits just below the inline editor. The editor still draws its
/// 34% dim around the capture, and its opaque capture image covers the blur
/// inside the capture, so only the surroundings blur. `NSVisualEffectView`
/// with `.behindWindow` blending blurs whatever lies behind the window, other
/// apps included, with no screen recording. With Reduce Transparency on, the
/// blur is left out and only the shadow shows.
@MainActor
final class FeedbackCaptureBackdrop {
    /// Below 1, part of the sharp screen shows through, for a lighter blur.
    static let blurOpacity: CGFloat = 0.6
    static let shadowRadius: CGFloat = 24
    static let shadowOpacity: Float = 0.45

    private var panel: NSPanel?

    /// `captureFrame` is the capture in the screen's own coordinates
    /// (origin at the screen's bottom left), as the editor gets it.
    func show(on screen: NSScreen, captureFrame: CGRect, below editor: NSWindow) {
        hide()
        let panel = NSPanel(
            contentRect: screen.frame,
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
        panel.setFrame(screen.frame, display: false)

        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let blur = NSVisualEffectView(frame: content.bounds)
            blur.autoresizingMask = [.width, .height]
            blur.blendingMode = .behindWindow
            blur.material = .fullScreenUI
            blur.state = .active
            blur.appearance = NSAppearance(named: .darkAqua)
            blur.alphaValue = Self.blurOpacity
            content.addSubview(blur)
        }
        let shadow = CALayer()
        shadow.frame = content.bounds
        shadow.shadowPath = CGPath(
            roundedRect: captureFrame,
            cornerWidth: 6,
            cornerHeight: 6,
            transform: nil
        )
        shadow.shadowColor = NSColor.black.cgColor
        shadow.shadowOpacity = Self.shadowOpacity
        shadow.shadowRadius = Self.shadowRadius
        shadow.shadowOffset = CGSize(width: 0, height: -6)
        content.layer?.addSublayer(shadow)
        panel.contentView = content

        panel.alphaValue = 0
        panel.order(.below, relativeTo: editor.windowNumber)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
