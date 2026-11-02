// Packages/FeedbackKit/Sources/FeedbackKit/HoverPreviewPolicy.swift
import CoreGraphics
import Foundation

/// Fork: the rules of the capture hover preview (#265). Pure geometry and
/// timing, so tests cover it with no window. Coordinates are AppKit screen
/// points: the origin is at the bottom left.
public enum HoverPreviewPolicy {
    /// How long the pointer rests on a row before the preview shows.
    public static let delay: TimeInterval = 1.0
    /// The largest preview, in points.
    public static let maxSize = CGSize(width: 640, height: 480)
    /// The space between the menu and the preview, and the margin to a display edge.
    public static let gap: CGFloat = 8

    /// The largest preview box that fits a display, with a margin on each side.
    public static func box(on screen: CGRect) -> CGSize {
        CGSize(
            width: min(maxSize.width, screen.width - 2 * gap),
            height: min(maxSize.height, screen.height - 2 * gap)
        )
    }

    /// The image size scaled to fit the box. It keeps the aspect ratio and
    /// never enlarges the image. A size with no area gives `.zero`.
    public static func fittedSize(of image: CGSize, in box: CGSize = maxSize) -> CGSize {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let scale = min(box.width / image.width, box.height / image.height, 1)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    /// Where the preview window goes: right of the menu when it fits, else
    /// left, else clamped onto the display. It centers on `anchorY`, the
    /// middle of the hovered row, then moves to stay on the display.
    public static func origin(for size: CGSize, besideMenu menu: CGRect, anchorY: CGFloat, in screen: CGRect) -> CGPoint {
        let right = menu.maxX + gap
        let left = menu.minX - gap - size.width
        let x: CGFloat
        if right + size.width <= screen.maxX {
            x = right
        } else if left >= screen.minX {
            x = left
        } else {
            x = right
        }
        let y = anchorY - size.height / 2
        return CGPoint(x: clamp(x, low: screen.minX, high: screen.maxX - size.width),
                       y: clamp(y, low: screen.minY, high: screen.maxY - size.height))
    }

    /// The low end wins when the preview is larger than the display.
    private static func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        max(low, min(value, high))
    }
}
