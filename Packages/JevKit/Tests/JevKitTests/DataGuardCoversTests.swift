import CoreGraphics
import FeedbackKit
import Foundation
import Testing
@testable import JevKit

/// The RGBA bytes of one pixel, with row 0 at the top of the image.
func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    let start = (y * image.width + x) * 4
    return Array(bytes[start..<start + 4])
}

@Suite("Data guard: covers and faces")
struct DataGuardCoversTests {
    @Test("Boxes grow and clamp")
    func geometry() {
        let box = FeedbackBox(x1: 10, y1: 20, x2: 110, y2: 40)
        #expect(DataGuardCovers.padded(box, by: 4) == FeedbackBox(x1: 6, y1: 16, x2: 114, y2: 44))
        // 10% of 100 is 10, and 10% of 20 is 2, raised to the minimum of 8.
        #expect(DataGuardCovers.grown(box, share: 0.1, minimum: 8) == FeedbackBox(x1: 0, y1: 12, x2: 120, y2: 48))
        #expect(DataGuardCovers.clamped(FeedbackBox(x1: -5, y1: -5, x2: 50, y2: 300), width: 100, height: 80) == FeedbackBox(x1: 0, y1: 0, x2: 50, y2: 80))
        #expect(DataGuardCovers.clamped(FeedbackBox(x1: 120, y1: 0, x2: 150, y2: 10), width: 100, height: 80) == nil)
    }

    @Test("A cover is black inside, and the image is unchanged outside")
    func drawing() throws {
        let image = blankImage(width: 100, height: 80)
        let covered = try #require(DataGuardCovers.draw([FeedbackBox(x1: 10, y1: 5, x2: 30, y2: 20)], on: image))
        #expect(covered.width == 100 && covered.height == 80)
        // Top left corner and the last pixel inside the box: black.
        #expect(pixel(covered, x: 10, y: 5) == [0, 0, 0, 255])
        #expect(pixel(covered, x: 29, y: 19) == [0, 0, 0, 255])
        // Just outside, and far away: still the red fill of the fixture.
        #expect(pixel(covered, x: 30, y: 19) == [255, 0, 0, 255])
        #expect(pixel(covered, x: 15, y: 20) == [255, 0, 0, 255])
        #expect(pixel(covered, x: 15, y: 70) == [255, 0, 0, 255])
        // The source image is a separate value and stays red.
        #expect(pixel(image, x: 15, y: 10) == [255, 0, 0, 255])
    }

    @Test("A cover past the edge is clamped, and one outside is skipped")
    func edges() throws {
        let image = blankImage(width: 60, height: 40)
        let covered = try #require(DataGuardCovers.draw([FeedbackBox(x1: 50, y1: 30, x2: 90, y2: 90), FeedbackBox(x1: 70, y1: 0, x2: 80, y2: 5)], on: image))
        #expect(pixel(covered, x: 59, y: 39) == [0, 0, 0, 255])
        #expect(pixel(covered, x: 49, y: 39) == [255, 0, 0, 255])
    }

    @Test("Decode refuses a file name with a path part")
    func decodeGuard() {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        #expect(DataGuardCovers.decode("../secret.png", in: folder) == nil)
        #expect(DataGuardCovers.decode("a/b.png", in: folder) == nil)
        #expect(DataGuardCovers.decode("", in: folder) == nil)
    }

    @Test("The Vision finder runs on a blank image and finds no face")
    func visionOnBlank() throws {
        #expect(try DataGuardFaceFinder.vision.faces(in: blankImage(width: 400, height: 300)).isEmpty)
    }
}
