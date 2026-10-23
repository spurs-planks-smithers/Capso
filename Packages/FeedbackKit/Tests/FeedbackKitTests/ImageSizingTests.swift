import CoreGraphics
import Testing
@testable import FeedbackKit

@Suite("ImageSizing")
struct ImageSizingTests {
    @Test("Counts one visual token per started 28 px patch")
    func visualTokensRoundUpToPatches() {
        #expect(ImageSizing.visualTokens(for: PixelSize(width: 1075, height: 1520)) == 2145)
        #expect(ImageSizing.visualTokens(for: PixelSize(width: 28, height: 29)) == 2)
    }

    @Test("Resizes Anthropic's A4 scan example at the standard tier")
    func a4ScanAtStandardTier() {
        let size = ImageSizing.resizedSize(PixelSize(width: 1075, height: 1520), limits: .standard)
        #expect(size == PixelSize(width: 924, height: 1307))
    }

    @Test("Resizes Anthropic's 1920x1080 example at the standard tier")
    func fullHDAtStandardTier() {
        let size = ImageSizing.resizedSize(PixelSize(width: 1920, height: 1080), limits: .standard)
        #expect(size == PixelSize(width: 1456, height: 819))
    }

    @Test("Resizes Anthropic's 3840x2160 example at the high-resolution tier")
    func fourKAtHighResolutionTier() {
        let size = ImageSizing.resizedSize(PixelSize(width: 3840, height: 2160), limits: .highResolution)
        #expect(size == PixelSize(width: 2576, height: 1449))
    }

    @Test("Keeps an image that already fits the limits")
    func keepsImageThatFits() {
        #expect(ImageSizing.resizedSize(PixelSize(width: 200, height: 200), limits: .standard) == PixelSize(width: 200, height: 200))
        #expect(ImageSizing.resizedSize(PixelSize(width: 1920, height: 1080), limits: .highResolution) == PixelSize(width: 1920, height: 1080))
    }

    /// Expected sizes come from Anthropic's Python reference implementation
    /// run with max_edge=2000 and max_tokens=4784.
    @Test("Export limits keep the long edge at 2000 px or less and the cost at 4784 tokens or less")
    func exportLimits() {
        let cases: [(input: PixelSize, expected: PixelSize)] = [
            (PixelSize(width: 3840, height: 2160), PixelSize(width: 1988, height: 1118)),
            (PixelSize(width: 2880, height: 1800), PixelSize(width: 1988, height: 1242)),
            (PixelSize(width: 1170, height: 2532), PixelSize(width: 919, height: 1988)),
            (PixelSize(width: 1920, height: 1080), PixelSize(width: 1920, height: 1080)),
        ]
        for testCase in cases {
            let size = ImageSizing.resizedSize(testCase.input, limits: .feedbackExport)
            #expect(size == testCase.expected)
            #expect(max(size.width, size.height) <= 2000)
            #expect(ImageSizing.visualTokens(for: size) <= 4784)
        }
    }

    @Test("Scales a box to the exported size on each axis")
    func scalesBox() {
        let box = ImageSizing.scale(
            CGRect(x: 100, y: 50, width: 200, height: 100),
            from: PixelSize(width: 3840, height: 2160),
            to: PixelSize(width: 1988, height: 1118)
        )
        // 100 * 1988/3840 = 51.8, 50 * 1118/2160 = 25.9, 300 * 1988/3840 = 155.3, 150 * 1118/2160 = 77.6
        #expect(box == FeedbackBox(x1: 52, y1: 26, x2: 155, y2: 78))
    }

    @Test("Scales a point and clamps it inside the exported image")
    func scalesAndClampsPoint() {
        let source = PixelSize(width: 3840, height: 2160)
        let target = PixelSize(width: 1988, height: 1118)
        #expect(ImageSizing.scale(CGPoint(x: 1920, y: 1080), from: source, to: target) == FeedbackPoint(x: 994, y: 559))
        #expect(ImageSizing.scale(CGPoint(x: 4000, y: -5), from: source, to: target) == FeedbackPoint(x: 1988, y: 0))
    }
}
