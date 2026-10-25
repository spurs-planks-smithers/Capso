import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import FeedbackKit

/// Test PNGs for the zip export tests.
enum ZipTestImages {
    /// Writes a PNG of `size`. `noise: true` fills random pixels, which
    /// compress poorly. `false` fills one color. `metadata` goes into the file.
    static func writePNG(to url: URL, size: PixelSize, noise: Bool, metadata: [CFString: Any]? = nil) throws {
        let bytesPerRow = size.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * size.height)
        if noise {
            pixels.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
        } else {
            for index in stride(from: 0, to: pixels.count, by: 4) {
                pixels[index] = 230
                pixels[index + 1] = 120
                pixels[index + 2] = 40
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let image = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(
                data: buffer.baseAddress, width: size.width, height: size.height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )?.makeImage()
        }
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image!, metadata as CFDictionary?)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// The pixel size and type of encoded image data.
    static func info(_ data: Data) -> (type: String?, size: PixelSize?, properties: [CFString: Any]) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return (nil, nil, [:]) }
        let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        let size = width.flatMap { w in height.map { PixelSize(width: w, height: $0) } }
        return (CGImageSourceGetType(source) as String?, size, properties)
    }

    /// A new empty folder under the temporary folder.
    static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zip-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
