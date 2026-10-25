import Foundation
import ImageIO
import Testing
@testable import FeedbackKit

/// JPEG images for the zip export (#85).
@Suite("Export image encoder")
struct ExportImageEncoderTests {
    @Test("Encodes a PNG as a JPEG of the given size")
    func encodesAtSize() throws {
        let folder = try ZipTestImages.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("a.png")
        try ZipTestImages.writePNG(to: png, size: PixelSize(width: 2000, height: 1200), noise: false)

        let data = try ExportImageEncoder.jpeg(contentsOf: png, size: PixelSize(width: 1456, height: 874), quality: 0.75)
        let info = ZipTestImages.info(data)
        #expect(info.type == "public.jpeg")
        #expect(info.size == PixelSize(width: 1456, height: 874))
    }

    @Test("Lower quality gives fewer bytes")
    func lowerQualityIsSmaller() throws {
        let folder = try ZipTestImages.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("noise.png")
        try ZipTestImages.writePNG(to: png, size: PixelSize(width: 800, height: 600), noise: true)

        let size = PixelSize(width: 800, height: 600)
        let high = try ExportImageEncoder.jpeg(contentsOf: png, size: size, quality: 0.75)
        let low = try ExportImageEncoder.jpeg(contentsOf: png, size: size, quality: 0.5)
        #expect(low.count < high.count)
    }

    @Test("The JPEG carries no metadata from the source PNG")
    func noMetadata() throws {
        let folder = try ZipTestImages.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("tagged.png")
        let metadata: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestMake"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 33.4],
        ]
        try ZipTestImages.writePNG(to: png, size: PixelSize(width: 400, height: 300), noise: false, metadata: metadata)
        // The source really holds the tag, so the check below means something.
        let sourceInfo = ZipTestImages.info(try Data(contentsOf: png))
        try #require((sourceInfo.properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String == "TestMake")

        let info = ZipTestImages.info(try ExportImageEncoder.jpeg(contentsOf: png, size: PixelSize(width: 400, height: 300), quality: 0.75))
        #expect(info.properties[kCGImagePropertyGPSDictionary] == nil)
        #expect((info.properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil)
    }

    @Test("A missing file throws unreadable")
    func missingFileThrows() {
        let url = URL(fileURLWithPath: "/nonexistent/zip-tests/missing.png")
        #expect(throws: ExportImageError.unreadable(url)) {
            try ExportImageEncoder.jpeg(contentsOf: url, size: PixelSize(width: 10, height: 10), quality: 0.75)
        }
    }
}
