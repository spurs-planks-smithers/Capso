// Packages/FeedbackKit/Sources/FeedbackKit/ExportImageEncoder.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ExportImageError: Error, Equatable {
    case unreadable(URL)
    case encodeFailed
}

/// JPEG images for a zip export (#85). A bundle PNG averages about 900 KB.
/// The same capture as a JPEG at the standard tier size, quality 0.75,
/// averages about 200 KB, and its text stays legible (26 captures, 2026-10-25).
public enum ExportImageEncoder {
    /// Reads the PNG at `url`, draws it at `size` in sRGB, and encodes it as
    /// a JPEG. Only the compression quality goes to the encoder, so no
    /// metadata from the source carries over.
    public static func jpeg(contentsOf url: URL, size: PixelSize, quality: Double) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ExportImageError.unreadable(url)
        }
        guard size.width > 0, size.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            throw ExportImageError.encodeFailed
        }
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        // A JPEG has no alpha, so a clear pixel shows white, not black.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)

        let data = NSMutableData()
        guard let scaled = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ExportImageError.encodeFailed
        }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportImageError.encodeFailed
        }
        return data as Data
    }
}
