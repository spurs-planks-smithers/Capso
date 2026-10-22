// App/Feedback/FeedbackThumbnails.swift
import AppKit
import ImageIO

/// Fork: small preview images for the capture rows in the feedback menu. A
/// thumbnail is about 80 pixels on its long side, which is twice the 40 by 26
/// point box a row draws it in. The cache key holds the file path and its
/// modification date, so an edited capture gets a fresh thumbnail.
@MainActor
enum FeedbackThumbnails {
    private static let maxPixelSize = 80
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    /// Returns nil when the file is missing or is not an image.
    static func image(for url: URL) -> NSImage? {
        // Read the date from the file system. `URL.resourceValues` can return
        // a value cached on the URL, which would keep an old thumbnail.
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            return nil
        }
        let cacheKey = "\(url.path)|\(modified.timeIntervalSinceReferenceDate)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        // Decode only a small version. The full capture can be several megabytes.
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }

        // Point size is half the pixel size, so the image is sharp on a 2x display.
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width) / 2, height: CGFloat(cgImage.height) / 2)
        )
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}
