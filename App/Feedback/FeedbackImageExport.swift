// App/Feedback/FeedbackImageExport.swift
import CoreGraphics
import FeedbackKit
import Foundation
import SharedKit

enum FeedbackImageExport {
    /// PNG data for `image` drawn at `size`. PNG is lossless, so text stays sharp.
    static func png(_ image: CGImage, size: PixelSize) -> Data? {
        guard size.width != image.width || size.height != image.height else {
            return ImageUtilities.pngData(from: image)
        }
        let colorSpace = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage().flatMap(ImageUtilities.pngData(from:))
    }
}
