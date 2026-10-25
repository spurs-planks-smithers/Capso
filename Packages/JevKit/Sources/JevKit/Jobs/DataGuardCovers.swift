// Packages/JevKit/Sources/JevKit/Jobs/DataGuardCovers.swift
import CoreGraphics
import FeedbackKit
import Foundation
import ImageIO

/// Draws the guard's covers: opaque black boxes. Blur and pixelation keep
/// part of the data, and tools such as Unredacter (2022) recover pixelated
/// text, so the guard never uses them (Drew, 2026-10-24).
public enum DataGuardCovers {
    /// Grows a box by `pixels` on each side.
    public static func padded(_ box: FeedbackBox, by pixels: Int) -> FeedbackBox {
        FeedbackBox(x1: box.x1 - pixels, y1: box.y1 - pixels, x2: box.x2 + pixels, y2: box.y2 + pixels)
    }

    /// Grows a box on each side by `share` of its size, and by at least
    /// `minimum` pixels.
    public static func grown(_ box: FeedbackBox, share: Double, minimum: Int) -> FeedbackBox {
        let dx = max(Int((Double(box.x2 - box.x1) * share).rounded(.up)), minimum)
        let dy = max(Int((Double(box.y2 - box.y1) * share).rounded(.up)), minimum)
        return FeedbackBox(x1: box.x1 - dx, y1: box.y1 - dy, x2: box.x2 + dx, y2: box.y2 + dy)
    }

    /// The part of the box inside a `width` by `height` image, or nil when
    /// nothing is left.
    public static func clamped(_ box: FeedbackBox, width: Int, height: Int) -> FeedbackBox? {
        let clamped = FeedbackBox(
            x1: min(max(box.x1, 0), width),
            y1: min(max(box.y1, 0), height),
            x2: min(max(box.x2, 0), width),
            y2: min(max(box.y2, 0), height)
        )
        return clamped.x2 > clamped.x1 && clamped.y2 > clamped.y1 ? clamped : nil
    }

    /// A copy of `image` with each box filled opaque black. Boxes are in the
    /// image's pixels, origin top left, and are clamped to the image. Nil
    /// when drawing fails.
    public static func draw(_ boxes: [FeedbackBox], on image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        // Keep the capture's own color space, so colors outside the covers
        // stay as they were.
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for box in boxes {
            guard let box = clamped(box, width: width, height: height) else { continue }
            // CoreGraphics puts the origin at the bottom left.
            context.fill(CGRect(x: box.x1, y: height - box.y2, width: box.x2 - box.x1, height: box.y2 - box.y1))
        }
        return context.makeImage()
    }

    /// Reads a bundle PNG by its file name. Nil for a name with a path part,
    /// because a tampered feedback.json could name a file outside the bundle.
    static func decode(_ file: String, in folderURL: URL) -> CGImage? {
        guard !file.isEmpty, !file.contains("/"), !file.contains("..") else { return nil }
        let url = folderURL.appendingPathComponent(file)
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }

    static func png(_ image: CGImage) -> Data? {
        JevImagePreparation.pngData(image)
    }
}
