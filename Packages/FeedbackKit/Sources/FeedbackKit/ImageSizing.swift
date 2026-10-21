// Packages/FeedbackKit/Sources/FeedbackKit/ImageSizing.swift
import CoreGraphics
import Foundation

/// Export sizing for feedback images, ported from Anthropic's published
/// resize rule ("How Claude resizes and pads images",
/// platform.claude.com/docs/en/build-with-claude/vision-coordinates).
///
/// An image exported at `resizedSize(_:limits:)` is the exact image Claude
/// sees, so pixel coordinates in the manifest need no conversion.
public enum ImageSizing {
    /// Claude views images in 28x28 pixel patches. One patch is one visual token.
    public static let patchSize = 28

    public struct Limits: Equatable, Sendable {
        public var maxEdge: Int
        public var maxTokens: Int

        public init(maxEdge: Int, maxTokens: Int) {
            self.maxEdge = maxEdge
            self.maxTokens = maxTokens
        }

        public static let standard = Limits(maxEdge: 1568, maxTokens: 1568)
        public static let highResolution = Limits(maxEdge: 2576, maxTokens: 4784)
        /// Requests with more than 20 images reject any image over 2000 px,
        /// so feedback exports stay at or under 2000 px.
        public static let feedbackExport = Limits(maxEdge: 2000, maxTokens: 4784)
    }

    public static func visualTokens(for size: PixelSize) -> Int {
        patches(size.width) * patches(size.height)
    }

    /// The largest aspect-preserving size that fits both limits. An image that
    /// already fits is returned unchanged.
    public static func resizedSize(_ size: PixelSize, limits: Limits) -> PixelSize {
        guard size.width > 0, size.height > 0 else { return size }
        if fits(size, limits) { return size }
        if size.height > size.width {
            let rotated = resizedSize(PixelSize(width: size.height, height: size.width), limits: limits)
            return PixelSize(width: rotated.height, height: rotated.width)
        }

        // Binary search along the long edge. `low` always fits; `high` never fits.
        let aspectRatio = Double(size.width) / Double(size.height)
        func shortEdge(_ longEdge: Int) -> Int {
            max(Int((Double(longEdge) / aspectRatio).rounded(.toNearestOrEven)), 1)
        }
        var low = 1
        var high = size.width
        while low + 1 < high {
            let mid = (low + high) / 2
            if fits(PixelSize(width: mid, height: shortEdge(mid)), limits) {
                low = mid
            } else {
                high = mid
            }
        }
        return PixelSize(width: low, height: shortEdge(low))
    }

    /// Maps a rectangle in source pixels (origin top-left) to the exported size.
    public static func scale(_ rect: CGRect, from source: PixelSize, to target: PixelSize) -> FeedbackBox {
        let rect = rect.standardized
        let topLeft = scale(CGPoint(x: rect.minX, y: rect.minY), from: source, to: target)
        let bottomRight = scale(CGPoint(x: rect.maxX, y: rect.maxY), from: source, to: target)
        return FeedbackBox(x1: topLeft.x, y1: topLeft.y, x2: bottomRight.x, y2: bottomRight.y)
    }

    /// Maps a point in source pixels (origin top-left) to the exported size,
    /// clamped to the exported image.
    public static func scale(_ point: CGPoint, from source: PixelSize, to target: PixelSize) -> FeedbackPoint {
        FeedbackPoint(
            x: scaled(point.x, from: source.width, to: target.width),
            y: scaled(point.y, from: source.height, to: target.height)
        )
    }

    private static func patches(_ length: Int) -> Int {
        (length + patchSize - 1) / patchSize
    }

    private static func fits(_ size: PixelSize, _ limits: Limits) -> Bool {
        patches(size.width) * patchSize <= limits.maxEdge
            && patches(size.height) * patchSize <= limits.maxEdge
            && visualTokens(for: size) <= limits.maxTokens
    }

    private static func scaled(_ value: CGFloat, from source: Int, to target: Int) -> Int {
        guard source > 0 else { return 0 }
        let mapped = (Double(value) * Double(target) / Double(source)).rounded()
        return min(max(Int(mapped), 0), target)
    }
}
