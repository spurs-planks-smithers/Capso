// App/Feedback/FeedbackRoundDot.swift
import AppKit

/// Fork: a small green dot over the top right corner of the menu bar mark. It
/// shows that a round (an active feedback round) exists, like the camera-in-use
/// light.
///
/// The mark is a template image, so macOS tints it for the menu bar and for the
/// open-menu highlight. The dot is a separate subview of the status bar button,
/// so it keeps its green while the mark follows the tint. The button holds the
/// only reference to the dot. `setActive(_:on:)` finds it again among the
/// button's subviews.
@MainActor
final class FeedbackRoundDot: NSView {
    /// Diameter in points. The mark is 14 points tall, so 5 stays subtle.
    static let diameter: CGFloat = 5

    /// The dot as an image for a menu row, 8 points across like the help box's
    /// dot. It is not a template, so it stays green on the row highlight. The
    /// color resolves when the image draws, so it follows the menu's appearance.
    static let menuImage: NSImage = {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Active round"
        return image
    }()

    /// How far the dot's center sits inside the mark's top right corner, in points.
    /// The center is inside the corner so the dot does not reach the button's edge.
    private static let cornerInset: CGFloat = 0.5

    /// Shows or hides the dot on the button. Hiding removes the view, so the
    /// plain mark is exactly what it was before the dot existed.
    static func setActive(_ active: Bool, on button: NSButton) {
        let existing = button.subviews.compactMap { $0 as? FeedbackRoundDot }.first
        guard active else {
            existing?.removeFromSuperview()
            return
        }
        if let existing {
            existing.reposition()
            return
        }
        let dot = FeedbackRoundDot(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        button.addSubview(dot)
        dot.reposition()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The dot never takes a click, so the button below it still opens the menu.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // A dynamic color, resolved against the appearance this view draws in.
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        NotificationCenter.default.removeObserver(self)
        guard let button = superview else { return }
        // The button changes size when its title changes, and the status bar
        // lays it out later. Follow it so the dot stays on the corner.
        button.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(buttonFrameChanged),
            name: NSView.frameDidChangeNotification,
            object: button
        )
    }

    @objc private func buttonFrameChanged(_ note: Notification) {
        reposition()
    }

    /// Puts the dot on the top right corner of the mark. The mark's rectangle
    /// comes from the button's cell, so it follows the real layout.
    func reposition() {
        guard let button = superview as? NSButton,
              let cell = button.cell as? NSButtonCell,
              button.image != nil, !button.bounds.isEmpty else {
            isHidden = true
            return
        }
        let mark = cell.imageRect(forBounds: button.bounds)
        guard !mark.isEmpty else {
            isHidden = true
            return
        }
        isHidden = false
        let topY = button.isFlipped ? mark.minY : mark.maxY
        let centerY = button.isFlipped ? topY + Self.cornerInset : topY - Self.cornerInset
        let size = Self.diameter
        setFrameOrigin(NSPoint(
            x: mark.maxX - Self.cornerInset - size / 2,
            y: centerY - size / 2
        ))
    }
}
