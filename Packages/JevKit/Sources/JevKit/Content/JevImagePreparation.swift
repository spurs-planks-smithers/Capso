// Packages/JevKit/Sources/JevKit/Content/JevImagePreparation.swift
import CoreGraphics
import FeedbackKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Makes a `JevImage` from a capture image or a region of it. TypeSafe
/// rejects an image with a side under 280 or over 1568 pixels and never
/// resizes (docs.typesafe.ai/images, "Preparing images").
///
/// 1. A region with a side over 1568 is scaled down to fit.
/// 2. A region with a side under 280 is scaled up, as far as the long side allows.
/// 3. A side still under 280 (a very wide or tall region) is padded with gray.
public enum JevImagePreparation {
    /// Mid gray, so padding never reads as part of a light or dark interface.
    static let paddingGray: CGFloat = 0.5

    /// The scaled size of a region, before padding.
    static func scaledSize(for size: PixelSize) -> PixelSize {
        let width = Double(max(size.width, 1))
        let height = Double(max(size.height, 1))
        let longest = max(width, height)
        let shortest = min(width, height)
        let maxSide = Double(JevImage.maxSide)
        let minSide = Double(JevImage.minSide)

        var scale = min(1, maxSide / longest)
        if shortest * scale < minSide {
            scale = min(minSide / shortest, maxSide / longest)
        }
        return PixelSize(
            width: min(max(Int((width * scale).rounded()), 1), JevImage.maxSide),
            height: min(max(Int((height * scale).rounded()), 1), JevImage.maxSide)
        )
    }

    /// `image` shows `sourceRegion` of a capture, in capture pixels.
    public static func prepare(_ image: CGImage, sourceRegion: FeedbackBox) throws -> JevImage {
        let content = scaledSize(for: PixelSize(width: image.width, height: image.height))
        let canvas = PixelSize(width: max(content.width, JevImage.minSide), height: max(content.height, JevImage.minSide))
        let originX = (canvas.width - content.width) / 2
        let originY = (canvas.height - content.height) / 2

        guard let context = CGContext(
            data: nil,
            width: canvas.width,
            height: canvas.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw JevError(.jobError) }
        context.setFillColor(gray: paddingGray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        context.interpolationQuality = .high
        // CoreGraphics puts the origin at the bottom left.
        context.draw(image, in: CGRect(
            x: originX,
            y: canvas.height - originY - content.height,
            width: content.width,
            height: content.height
        ))
        guard let rendered = context.makeImage(), let png = pngData(rendered) else { throw JevError(.jobError) }

        return JevImage(
            png: png,
            size: canvas,
            sourceRegion: sourceRegion,
            contentRect: FeedbackBox(x1: originX, y1: originY, x2: originX + content.width, y2: originY + content.height)
        )
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

extension JevImageLoader {
    /// Reads a capture's PNG from the bundle folder, crops it to the region
    /// (clamped to the image), and prepares it. Only the bundle's own files
    /// are read, so Redact marks stay applied.
    public static func bundle(folderURL: URL, round: FeedbackRound) -> JevImageLoader {
        JevImageLoader { index, variant, region in
            guard let capture = round.captures.first(where: { $0.index == index }) else { throw JevError(.jobError) }
            let file = variant == .annotated ? capture.imageFile : capture.cleanImageFile
            let url = folderURL.appendingPathComponent(file)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw JevError(.jobError) }

            let whole = FeedbackBox(x1: 0, y1: 0, x2: image.width, y2: image.height)
            let box = region.map { clamp($0, to: whole) } ?? whole
            guard box.x2 > box.x1, box.y2 > box.y1,
                  let cropped = image.cropping(to: CGRect(x: box.x1, y: box.y1, width: box.x2 - box.x1, height: box.y2 - box.y1))
            else { throw JevError(.jobError) }
            return try JevImagePreparation.prepare(cropped, sourceRegion: box)
        }
    }

    private static func clamp(_ box: FeedbackBox, to bounds: FeedbackBox) -> FeedbackBox {
        FeedbackBox(
            x1: min(max(box.x1, bounds.x1), bounds.x2),
            y1: min(max(box.y1, bounds.y1), bounds.y2),
            x2: min(max(box.x2, bounds.x1), bounds.x2),
            y2: min(max(box.y2, bounds.y1), bounds.y2)
        )
    }
}
