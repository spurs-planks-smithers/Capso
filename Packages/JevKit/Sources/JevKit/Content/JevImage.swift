// Packages/JevKit/Sources/JevKit/Content/JevImage.swift
import FeedbackKit
import Foundation

/// A PNG ready to send: each side is 280 to 1568 pixels, TypeSafe's limits
/// (docs.typesafe.ai/images, "Limits"). The API rejects other sizes and never
/// resizes. `JevImageLoader` makes these from a capture's files.
///
/// The image shows `sourceRegion` of a capture, scaled into `contentRect`.
/// Any rest of the image is padding. `sourceBox(for:)` maps a Box answer
/// back to capture pixels.
public struct JevImage: Equatable, Sendable {
    public static let minSide = 280
    public static let maxSide = 1568

    /// A new id per image. Its asset reference in a request derives from it.
    public let id: UUID
    public let png: Data
    /// The pixel size of `png`.
    public let size: PixelSize
    /// The region of the capture that the image shows, in capture pixels.
    public let sourceRegion: FeedbackBox
    /// Where that region sits in `png`, in its pixels. Outside it is padding.
    public let contentRect: FeedbackBox

    public init(id: UUID = UUID(), png: Data, size: PixelSize, sourceRegion: FeedbackBox, contentRect: FeedbackBox) {
        self.id = id
        self.png = png
        self.size = size
        self.sourceRegion = sourceRegion
        self.contentRect = contentRect
    }

    /// Maps a box in fractions of this image to capture pixels, clamped to
    /// `sourceRegion`. A box in the padding maps to the nearest edge.
    public func sourceBox(for box: JevBox) -> FeedbackBox {
        let contentWidth = Double(max(contentRect.x2 - contentRect.x1, 1))
        let contentHeight = Double(max(contentRect.y2 - contentRect.y1, 1))
        let sourceWidth = Double(sourceRegion.x2 - sourceRegion.x1)
        let sourceHeight = Double(sourceRegion.y2 - sourceRegion.y1)

        func mapX(_ fraction: Double) -> Int {
            let sent = fraction * Double(size.width)
            let local = (sent - Double(contentRect.x1)) / contentWidth
            let value = Double(sourceRegion.x1) + min(max(local, 0), 1) * sourceWidth
            return Int(value.rounded())
        }
        func mapY(_ fraction: Double) -> Int {
            let sent = fraction * Double(size.height)
            let local = (sent - Double(contentRect.y1)) / contentHeight
            let value = Double(sourceRegion.y1) + min(max(local, 0), 1) * sourceHeight
            return Int(value.rounded())
        }
        return FeedbackBox(x1: mapX(box.left), y1: mapY(box.top), x2: mapX(box.right), y2: mapY(box.bottom))
    }
}
