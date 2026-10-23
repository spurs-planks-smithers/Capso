// App/Feedback/FeedbackCaptureRowView.swift
import AppKit
import FeedbackKit

/// Fork: one capture row in a session's submenu. From the left: a checkbox,
/// a thumbnail, and two lines of text (the capture title and an item count).
///
/// The row is a custom menu item view, so a click does not close the menu.
/// A mouse-up flips the checkbox and calls `onToggle`. A mouse-up with Option
/// held calls `onQuickLook` and leaves the checkbox as it is. A tracking area
/// draws the same rounded highlight and white text that native rows use,
/// because a view in a menu item gets no native highlight.
@MainActor
final class FeedbackCaptureRowView: NSView {
    static let rowSize = NSSize(width: 350, height: 34)

    private static let highlightInset: CGFloat = 5
    private static let highlightRadius: CGFloat = 6
    private static let checkboxSide: CGFloat = 14
    private static let checkboxX: CGFloat = 15
    private static let thumbnailSize = NSSize(width: 40, height: 26)
    private static let partSpacing: CGFloat = 8
    private static let thumbnailX = checkboxX + checkboxSide + partSpacing
    private static let textX = thumbnailX + thumbnailSize.width + partSpacing
    private static let trailingPadding: CGFloat = 14

    private let key: FeedbackBasketKey
    private let thumbnail: NSImage?
    private let onToggle: (FeedbackBasketKey) -> Void
    private let onQuickLook: (FeedbackBasketKey) -> Void
    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField
    private var checked: Bool

    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            updateTextColors()
            needsDisplay = true
        }
    }

    init(
        key: FeedbackBasketKey,
        title: String,
        subtitle: String,
        thumbnail: NSImage?,
        checked: Bool,
        onToggle: @escaping (FeedbackBasketKey) -> Void,
        onQuickLook: @escaping (FeedbackBasketKey) -> Void
    ) {
        self.key = key
        self.thumbnail = thumbnail
        self.checked = checked
        self.onToggle = onToggle
        self.onQuickLook = onQuickLook
        titleLabel = Self.makeLabel(title, size: 13)
        subtitleLabel = Self.makeLabel(subtitle, size: 11)
        super.init(frame: NSRect(origin: .zero, size: Self.rowSize))
        // The menu can make a row wider than 350 points to match its widest item.
        autoresizingMask = [.width]

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.textX),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.trailingPadding),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateTextColors()

        // `.enabledDuringMouseDrag` covers a user who presses on the menu bar
        // item and drags into the submenu in one motion.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .enabledDuringMouseDrag, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func makeLabel(_ text: String, size: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.lineBreakMode = .byTruncatingTail
        // A low resistance lets the trailing constraint shorten a long title.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func updateTextColors() {
        titleLabel.textColor = isHovered ? .white : .labelColor
        subtitleLabel.textColor = isHovered ? .white : .secondaryLabelColor
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: Self.highlightInset, dy: 0),
                xRadius: Self.highlightRadius,
                yRadius: Self.highlightRadius
            ).fill()
        }
        drawCheckbox()
        drawThumbnail()
    }

    private func drawCheckbox() {
        let box = NSRect(
            x: Self.checkboxX,
            y: ((bounds.height - Self.checkboxSide) / 2).rounded(),
            width: Self.checkboxSide,
            height: Self.checkboxSide
        )
        // On the blue highlight a blue box would vanish, so a checked box turns white.
        let boxPath = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5)
        if checked {
            (isHovered ? NSColor.white : NSColor.controlAccentColor).setFill()
            boxPath.fill()
            drawCheckmark(in: box, color: isHovered ? .controlAccentColor : .white)
        } else {
            NSColor.controlBackgroundColor.setFill()
            boxPath.fill()
            (isHovered ? NSColor.white : NSColor.secondaryLabelColor).setStroke()
            boxPath.lineWidth = 1
            boxPath.stroke()
        }
    }

    private func drawCheckmark(in box: NSRect, color: NSColor) {
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: box.minX + 3.5, y: box.midY + 0.5))
        mark.line(to: NSPoint(x: box.minX + 6, y: box.minY + 4))
        mark.line(to: NSPoint(x: box.maxX - 3, y: box.maxY - 3.5))
        mark.lineWidth = 1.6
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        color.setStroke()
        mark.stroke()
    }

    private func drawThumbnail() {
        let box = NSRect(
            x: Self.thumbnailX,
            y: ((bounds.height - Self.thumbnailSize.height) / 2).rounded(),
            width: Self.thumbnailSize.width,
            height: Self.thumbnailSize.height
        )
        let boxPath = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        NSColor.white.setFill()
        boxPath.fill()

        if let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 {
            // Fit the whole capture inside the box. Never crop or stretch it.
            let scale = min(box.width / thumbnail.size.width, box.height / thumbnail.size.height)
            let fitted = NSSize(width: thumbnail.size.width * scale, height: thumbnail.size.height * scale)
            let imageRect = NSRect(
                x: box.midX - fitted.width / 2,
                y: box.midY - fitted.height / 2,
                width: fitted.width,
                height: fitted.height
            )
            NSGraphicsContext.saveGraphicsState()
            boxPath.addClip()
            thumbnail.draw(
                in: imageRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high.rawValue]
            )
            NSGraphicsContext.restoreGraphicsState()
        }

        // A half-point line centered on the edge would spill outside the box, so inset it.
        let borderPath = NSBezierPath(roundedRect: box.insetBy(dx: 0.25, dy: 0.25), xRadius: 2.75, yRadius: 2.75)
        borderPath.lineWidth = 0.5
        NSColor.separatorColor.setStroke()
        borderPath.stroke()
    }

    // MARK: Mouse

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A menu can close with the pointer over the row, and no exit event
        // arrives then. Start each open without the highlight.
        isHovered = false
    }

    /// Return self for any point in the row, so the labels never take the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Claim the press. The action happens on mouse-up, as in a native menu row.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        // Ignore a release outside the row, for example after a drag from another row.
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if event.modifierFlags.contains(.option) {
            onQuickLook(key)
        } else {
            toggle()
        }
    }

    private func toggle() {
        checked.toggle()
        needsDisplay = true
        // The menu runs its own event loop, so draw now instead of waiting for the next pass.
        displayIfNeeded()
        onToggle(key)
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilityLabel() -> String? {
        "\(titleLabel.stringValue), \(subtitleLabel.stringValue)"
    }
    override func accessibilityValue() -> Any? { checked ? 1 : 0 }
    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }
}
