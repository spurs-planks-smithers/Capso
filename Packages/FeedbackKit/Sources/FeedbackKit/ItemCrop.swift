// Packages/FeedbackKit/Sources/FeedbackKit/ItemCrop.swift
import Foundation

/// The geometry of an item crop: the part of a capture that shows one numbered
/// item. All boxes are export pixels of the capture's PNG, with the origin at
/// the top-left corner.
///
/// The steps follow the design in `docs/superpowers/specs/2026-10-24-crops-anchors-design.md`.
/// The seed box holds the badge, its shape, and its arrow tip. The window is
/// the region Jev looks at. The marks crop is the fallback when Jev cannot find
/// the target. Edge checks move a crop outward. Nothing here reads or writes an
/// image, and nothing here talks to Jev.
public enum ItemCrop {
    /// Context around the seed box for the window Jev looks at.
    public static let windowMargin = 200
    /// Pad around the target box joined with the seed box.
    public static let targetPad = 24
    /// Pad around the seed box for the crop cut around the marks.
    public static let marksPad = 120
    /// An edge that is cut off moves out by this share of the crop's size on that axis.
    public static let edgeStep = 0.25
    /// The most edge-check requests for one item.
    public static let maxEdgeChecks = 2
    /// Jev accepts images with every side from 280 to 1568 pixels.
    public static let jevMinSide = 280
    public static let jevMaxSide = 1568
    /// The most the long side may exceed the short side, so one scale factor
    /// can meet both Jev limits.
    public static let maxAspect: Double = Double(jevMaxSide) / Double(jevMinSide)

    /// The edges of a crop.
    public struct Edges: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let left = Edges(rawValue: 1 << 0)
        public static let right = Edges(rawValue: 1 << 1)
        public static let top = Edges(rawValue: 1 << 2)
        public static let bottom = Edges(rawValue: 1 << 3)
    }

    // MARK: Seed and window

    /// One seed box per badge number. When two badges share a number, the first wins.
    public static func seeds(for capture: FeedbackCapture) -> [Int: FeedbackBox] {
        var seeds: [Int: FeedbackBox] = [:]
        for item in FeedbackItems.split(capture).items {
            guard let number = item.badge.badge, seeds[number] == nil else { continue }
            seeds[number] = item.focus
        }
        return seeds
    }

    /// `box` grown by `pad` on every side and kept inside the image.
    public static func padded(_ box: FeedbackBox, by pad: Int, imageSize: PixelSize) -> FeedbackBox {
        FeedbackBox(
            x1: min(max(box.x1 - pad, 0), imageSize.width),
            y1: min(max(box.y1 - pad, 0), imageSize.height),
            x2: min(max(box.x2 + pad, 0), imageSize.width),
            y2: min(max(box.y2 + pad, 0), imageSize.height)
        )
    }

    /// The region Jev looks at: the seed box plus `windowMargin` on each side.
    public static func window(seed: FeedbackBox, imageSize: PixelSize) -> FeedbackBox {
        padded(seed, by: windowMargin, imageSize: imageSize)
    }

    /// The crop cut around the marks, when Jev finds no target: the seed box
    /// plus `marksPad` on each side.
    public static func marksCrop(seed: FeedbackBox, imageSize: PixelSize) -> FeedbackBox {
        padded(seed, by: marksPad, imageSize: imageSize)
    }

    // MARK: Target and edges

    /// The crop for the box that Jev found, already mapped to capture pixels
    /// (JevKit's `JevImage.sourceBox` does this). The result joins the seed
    /// box, so the badge stays in the crop, and adds `targetPad`.
    public static func targetCrop(target: FeedbackBox, seed: FeedbackBox, imageSize: PixelSize) -> FeedbackBox {
        padded(target.union(seed), by: targetPad, imageSize: imageSize)
    }

    /// Moves each named edge outward by `edgeStep` of the crop's width (left,
    /// right) or height (top, bottom). Other edges stay. The result stays inside the image.
    public static func expanded(_ crop: FeedbackBox, edges: Edges, imageSize: PixelSize) -> FeedbackBox {
        let stepX = Int((edgeStep * Double(crop.x2 - crop.x1)).rounded())
        let stepY = Int((edgeStep * Double(crop.y2 - crop.y1)).rounded())
        var box = crop
        if edges.contains(.left) { box.x1 = max(crop.x1 - stepX, 0) }
        if edges.contains(.right) { box.x2 = min(crop.x2 + stepX, imageSize.width) }
        if edges.contains(.top) { box.y1 = max(crop.y1 - stepY, 0) }
        if edges.contains(.bottom) { box.y2 = min(crop.y2 + stepY, imageSize.height) }
        return box
    }

    // MARK: Images for Jev

    /// Makes a box fit Jev's limits. When the long side is more than
    /// `maxAspect` times the short side, grows the short side around the box
    /// center to the smallest length that fits. The grown box slides inside
    /// the image at an edge. A box that already fits comes back unchanged.
    /// A box with a zero side counts as the short side. Returns nil when the
    /// image is too small on that axis to hold the grown box.
    ///
    /// JevKit's image loader scales a region into 280 to 1568 pixels and pads
    /// whatever one scale cannot fit. A shaped box needs no padding, so the
    /// edges that an edge check asks about are the crop's own edges.
    public static func shaped(_ box: FeedbackBox, imageSize: PixelSize) -> FeedbackBox? {
        let width = box.x2 - box.x1
        let height = box.y2 - box.y1
        let isWide = width >= height
        let long = isWide ? width : height
        let short = isWide ? height : width
        // Whole-number form of `long / short <= maxAspect`, free of rounding error.
        guard short * jevMaxSide < long * jevMinSide else { return box }

        // The smallest whole short side with `long / short <= maxAspect`.
        let needed = (long * jevMinSide + jevMaxSide - 1) / jevMaxSide
        if isWide {
            guard let span = grown(box.y1, box.y2, to: needed, limit: imageSize.height) else { return nil }
            return FeedbackBox(x1: box.x1, y1: span.low, x2: box.x2, y2: span.high)
        }
        guard let span = grown(box.x1, box.x2, to: needed, limit: imageSize.width) else { return nil }
        return FeedbackBox(x1: span.low, y1: box.y1, x2: span.high, y2: box.y2)
    }

    // MARK: Decide and write

    /// True when the crop costs at most half the visual tokens of the full image.
    public static func isWorthIt(_ crop: FeedbackBox, imageSize: PixelSize) -> Bool {
        let cropTokens = ImageSizing.visualTokens(for: PixelSize(width: crop.x2 - crop.x1, height: crop.y2 - crop.y1))
        return cropTokens * 2 <= ImageSizing.visualTokens(for: imageSize)
    }

    /// The crop file names: `<stem>-item-<N>.png` from the annotated image and
    /// `<stem>-item-<N>-clean.png` from the clean image. The stem is the image
    /// file name without a trailing `.png`.
    public static func fileNames(imageFile: String, badge: Int) -> (annotated: String, clean: String) {
        let stem = imageFile.hasSuffix(".png") ? String(imageFile.dropLast(4)) : imageFile
        return ("\(stem)-item-\(badge).png", "\(stem)-item-\(badge)-clean.png")
    }

    /// A span `low...high` grown to `length` around its center, then slid inside
    /// `0...limit`. The low side takes the smaller half of an odd growth.
    /// Returns nil when `length` is more than `limit`.
    private static func grown(_ low: Int, _ high: Int, to length: Int, limit: Int) -> (low: Int, high: Int)? {
        guard length <= limit else { return nil }
        var newLow = low - (length - (high - low)) / 2
        var newHigh = newLow + length
        if newLow < 0 {
            newHigh -= newLow
            newLow = 0
        }
        if newHigh > limit {
            newLow -= newHigh - limit
            newHigh = limit
        }
        return (newLow, newHigh)
    }
}
