// Packages/FeedbackKit/Sources/FeedbackKit/PreviewCrop.swift
import Foundation

/// The crop of a capture that the note panel shows while it asks about one
/// circle, so the reviewer sees which circle the question is about.
///
/// The circle sits in the middle. The crop includes the box or ellipse the
/// circle sits on and the point its arrow aims at, plus `margin` pixels of
/// context on every side. The crop then widens to `aspectRatio` (width over
/// height) and slides inside the image near an edge.
public enum PreviewCrop {
    public static func cropsByBadge(marks: [FeedbackMark], imageSize: PixelSize, margin: Int, aspectRatio: Double) -> [Int: FeedbackBox] {
        let capture = FeedbackCapture(
            index: 0,
            imageFile: "",
            cleanImageFile: "",
            size: imageSize,
            capturedAt: Date(timeIntervalSince1970: 0),
            marks: marks
        )
        var crops: [Int: FeedbackBox] = [:]
        for item in FeedbackItems.split(capture).items {
            guard let number = item.badge.badge, crops[number] == nil else { continue }
            var focus = item.badge.box
            if let shape = item.shape {
                focus = focus.union(shape.box)
            }
            if let tip = item.badge.point {
                focus = focus.union(FeedbackBox(x1: tip.x, y1: tip.y, x2: tip.x, y2: tip.y))
            }
            crops[number] = crop(center: item.badge.box.center, focus: focus, imageSize: imageSize, margin: margin, aspectRatio: aspectRatio)
        }
        return crops
    }

    private static func crop(center: FeedbackPoint, focus: FeedbackBox, imageSize: PixelSize, margin: Int, aspectRatio: Double) -> FeedbackBox {
        let centerX = Double(center.x)
        let centerY = Double(center.y)
        var halfWidth = max(centerX - Double(focus.x1), Double(focus.x2) - centerX) + Double(margin)
        var halfHeight = max(centerY - Double(focus.y1), Double(focus.y2) - centerY) + Double(margin)
        if halfWidth / halfHeight < aspectRatio {
            halfWidth = halfHeight * aspectRatio
        } else {
            halfHeight = halfWidth / aspectRatio
        }

        let imageWidth = Double(imageSize.width)
        let imageHeight = Double(imageSize.height)
        let width = min(2 * halfWidth, imageWidth)
        let height = min(2 * halfHeight, imageHeight)
        let x1 = min(max(centerX - width / 2, 0), imageWidth - width)
        let y1 = min(max(centerY - height / 2, 0), imageHeight - height)
        return FeedbackBox(
            x1: Int(x1.rounded()),
            y1: Int(y1.rounded()),
            x2: Int((x1 + width).rounded()),
            y2: Int((y1 + height).rounded())
        )
    }
}
