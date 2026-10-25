import Foundation
import Testing
@testable import FeedbackKit

@Suite("ItemCrop")
struct ItemCropTests {
    private let image = PixelSize(width: 2000, height: 1500)

    private func badge(_ number: Int, x: Int, y: Int, tip: FeedbackPoint? = nil) -> FeedbackMark {
        FeedbackMark(kind: .counter, badge: number, box: FeedbackBox(x1: x - 12, y1: y - 12, x2: x + 12, y2: y + 12), point: tip)
    }

    private func capture(marks: [FeedbackMark]) -> FeedbackCapture {
        FeedbackCapture(
            index: 1,
            imageFile: "0627-claude.png",
            cleanImageFile: "0627-claude-clean.png",
            size: image,
            capturedAt: Date(timeIntervalSince1970: 0),
            marks: marks
        )
    }

    // MARK: Seed and window

    @Test("The seed joins the badge, the shape it sits on, and the arrow tip")
    func seedJoinsBadgeShapeAndTip() {
        let marks = [
            badge(1, x: 500, y: 400, tip: FeedbackPoint(x: 900, y: 420)),
            FeedbackMark(kind: .rectangle, box: FeedbackBox(x1: 480, y1: 380, x2: 700, y2: 450)),
            badge(2, x: 1200, y: 900),
        ]
        let seeds = ItemCrop.seeds(for: capture(marks: marks))
        #expect(seeds[1] == FeedbackBox(x1: 480, y1: 380, x2: 900, y2: 450))
        #expect(seeds[2] == FeedbackBox(x1: 1188, y1: 888, x2: 1212, y2: 912))
        #expect(Set(seeds.keys) == [1, 2])
    }

    @Test("The first badge with a number wins")
    func firstBadgeWins() {
        let seeds = ItemCrop.seeds(for: capture(marks: [badge(1, x: 300, y: 300), badge(1, x: 900, y: 900)]))
        #expect(seeds[1] == FeedbackBox(x1: 288, y1: 288, x2: 312, y2: 312))
    }

    @Test("A capture with no badges has no seeds")
    func noBadgesNoSeeds() {
        let rectangle = FeedbackMark(kind: .rectangle, box: FeedbackBox(x1: 0, y1: 0, x2: 10, y2: 10))
        #expect(ItemCrop.seeds(for: capture(marks: [rectangle])).isEmpty)
    }

    @Test("The window and the marks crop grow by their margins")
    func windowAndMarksCrop() {
        let seed = FeedbackBox(x1: 480, y1: 380, x2: 900, y2: 450)
        #expect(ItemCrop.window(seed: seed, imageSize: image) == FeedbackBox(x1: 280, y1: 180, x2: 1100, y2: 650))
        #expect(ItemCrop.marksCrop(seed: seed, imageSize: image) == FeedbackBox(x1: 360, y1: 260, x2: 1020, y2: 570))
    }

    @Test("The window and the marks crop stop at the image edges")
    func clampAtEdges() {
        let corner = FeedbackBox(x1: 10, y1: 10, x2: 40, y2: 40)
        #expect(ItemCrop.window(seed: corner, imageSize: image) == FeedbackBox(x1: 0, y1: 0, x2: 240, y2: 240))
        #expect(ItemCrop.marksCrop(seed: corner, imageSize: image) == FeedbackBox(x1: 0, y1: 0, x2: 160, y2: 160))

        let far = FeedbackBox(x1: 1980, y1: 1480, x2: 1990, y2: 1490)
        #expect(ItemCrop.window(seed: far, imageSize: image) == FeedbackBox(x1: 1780, y1: 1280, x2: 2000, y2: 1500))
        #expect(ItemCrop.marksCrop(seed: far, imageSize: image) == FeedbackBox(x1: 1860, y1: 1360, x2: 2000, y2: 1500))
    }

    // MARK: Target crop

    @Test("Joins the target with the seed, pads, and keeps the marks crop")
    func targetCropJoinsSeed() {
        let target = FeedbackBox(x1: 300, y1: 150, x2: 600, y2: 300)
        let seed = FeedbackBox(x1: 700, y1: 400, x2: 720, y2: 420)
        // Joined with the seed and padded by 24: (276, 126, 744, 444).
        // Joined with the marks crop (580, 280, 840, 540): (276, 126, 840, 540).
        #expect(ItemCrop.targetCrop(target: target, seed: seed, imageSize: image) == FeedbackBox(x1: 276, y1: 126, x2: 840, y2: 540))
    }

    @Test("A tight target never gives a crop smaller than the marks crop")
    func targetCropNeverSmallerThanMarksCrop() {
        let seed = FeedbackBox(x1: 1038, y1: 1226, x2: 1066, y2: 1254)
        let target = FeedbackBox(x1: 1039, y1: 1210, x2: 1061, y2: 1251)
        let crop = ItemCrop.targetCrop(target: target, seed: seed, imageSize: image)
        #expect(crop == ItemCrop.marksCrop(seed: seed, imageSize: image))
    }

    @Test("The target crop always contains the seed and stays in the image")
    func targetCropContainsSeed() {
        let target = FeedbackBox(x1: 0, y1: 0, x2: 200, y2: 150)
        let seed = FeedbackBox(x1: 1900, y1: 1400, x2: 1990, y2: 1490)
        #expect(ItemCrop.targetCrop(target: target, seed: seed, imageSize: image) == FeedbackBox(x1: 0, y1: 0, x2: 2000, y2: 1500))
    }

    @Test("A zero-size target, as a Box answer in the padding gives, still yields the marks crop")
    func targetCropZeroSizeTarget() {
        let target = FeedbackBox(x1: 710, y1: 410, x2: 710, y2: 410)
        let seed = FeedbackBox(x1: 700, y1: 400, x2: 720, y2: 420)
        #expect(ItemCrop.targetCrop(target: target, seed: seed, imageSize: image) == FeedbackBox(x1: 580, y1: 280, x2: 840, y2: 540))
    }

    // MARK: Edge checks

    @Test("Moves only the named edges, by 25% of the crop's size on that axis")
    func expandedMovesNamedEdges() {
        let crop = FeedbackBox(x1: 400, y1: 300, x2: 800, y2: 500)
        // Width 400 gives 100. Height 200 gives 50.
        #expect(ItemCrop.expanded(crop, edges: [.left, .bottom], imageSize: image) == FeedbackBox(x1: 300, y1: 300, x2: 800, y2: 550))
        #expect(ItemCrop.expanded(crop, edges: [.right, .top], imageSize: image) == FeedbackBox(x1: 400, y1: 250, x2: 900, y2: 500))
        #expect(ItemCrop.expanded(crop, edges: [.left, .right, .top, .bottom], imageSize: image) == FeedbackBox(x1: 300, y1: 250, x2: 900, y2: 550))
        #expect(ItemCrop.expanded(crop, edges: [], imageSize: image) == crop)
    }

    @Test("A moved edge stops at the image edge")
    func expandedClamps() {
        let nearTopLeft = FeedbackBox(x1: 50, y1: 40, x2: 450, y2: 240)
        #expect(ItemCrop.expanded(nearTopLeft, edges: [.left, .top], imageSize: image) == FeedbackBox(x1: 0, y1: 0, x2: 450, y2: 240))

        let nearBottomRight = FeedbackBox(x1: 1600, y1: 1300, x2: 1950, y2: 1480)
        #expect(ItemCrop.expanded(nearBottomRight, edges: [.right, .bottom], imageSize: image) == FeedbackBox(x1: 1600, y1: 1300, x2: 2000, y2: 1500))
    }

    @Test("Rounds the step to whole pixels")
    func expandedRounds() {
        // Width 402 gives 100.5, which rounds to 101. Cutting off the fraction would give 100.
        let crop = FeedbackBox(x1: 500, y1: 500, x2: 902, y2: 700)
        #expect(ItemCrop.expanded(crop, edges: [.left], imageSize: image).x1 == 399)
    }

    @Test("A shaped box always fits 5.6, and one pixel less on the grown side would not")
    func shapedSweep() {
        let big = PixelSize(width: 4000, height: 4000)
        for width in stride(from: 50, through: 3000, by: 37) {
            for height in [1, 7, 20, 88, 140, 300] {
                let box = FeedbackBox(x1: 400, y1: 1800, x2: 400 + width, y2: 1800 + height)
                guard let shaped = ItemCrop.shaped(box, imageSize: big) else {
                    Issue.record("nil for \(width) by \(height)")
                    continue
                }
                let long = max(shaped.x2 - shaped.x1, shaped.y2 - shaped.y1)
                let short = min(shaped.x2 - shaped.x1, shaped.y2 - shaped.y1)
                #expect(short * ItemCrop.jevMaxSide >= long * ItemCrop.jevMinSide)
                if shaped != box {
                    #expect((short - 1) * ItemCrop.jevMaxSide < long * ItemCrop.jevMinSide)
                }
            }
        }
    }

    @Test("Slides a grown tall box inside the image at the left edge")
    func shapedSlidesHorizontally() {
        let column = FeedbackBox(x1: 0, y1: 100, x2: 40, y2: 1300)
        // Needs a width of ceil(1200 * 280 / 1568) = 215, from x 0.
        #expect(ItemCrop.shaped(column, imageSize: image) == FeedbackBox(x1: 0, y1: 100, x2: 215, y2: 1300))
    }

    // MARK: Shape for Jev

    @Test("Grows the short side of a wide, thin box around its center")
    func shapedGrowsShortSide() {
        let row = FeedbackBox(x1: 400, y1: 700, x2: 1600, y2: 788)
        let shaped = ItemCrop.shaped(row, imageSize: image)
        // 1200 / 5.6 rounded up is 215. Grow 127: 63 above and 64 below.
        #expect(shaped == FeedbackBox(x1: 400, y1: 637, x2: 1600, y2: 852))
    }

    @Test("Grows the width of a tall, thin box")
    func shapedGrowsWidth() {
        let column = FeedbackBox(x1: 900, y1: 100, x2: 988, y2: 1300)
        #expect(ItemCrop.shaped(column, imageSize: image) == FeedbackBox(x1: 837, y1: 100, x2: 1052, y2: 1300))
    }

    @Test("Slides the grown box inside the image at an edge")
    func shapedSlidesInside() {
        let top = FeedbackBox(x1: 400, y1: 0, x2: 1600, y2: 88)
        #expect(ItemCrop.shaped(top, imageSize: image) == FeedbackBox(x1: 400, y1: 0, x2: 1600, y2: 215))

        let bottom = FeedbackBox(x1: 400, y1: 1412, x2: 1600, y2: 1500)
        #expect(ItemCrop.shaped(bottom, imageSize: image) == FeedbackBox(x1: 400, y1: 1285, x2: 1600, y2: 1500))
    }

    @Test("Leaves a box whose aspect already fits, including exactly 5.6")
    func shapedKeepsFittingBox() {
        let fitting = FeedbackBox(x1: 100, y1: 100, x2: 700, y2: 500)
        #expect(ItemCrop.shaped(fitting, imageSize: image) == fitting)

        let limit = FeedbackBox(x1: 100, y1: 100, x2: 1668, y2: 380)
        #expect(ItemCrop.shaped(limit, imageSize: image) == limit)

        // 1569 / 5.6 rounded up is 281. Grow 1: the upper side takes the smaller half, so 0 above and 1 below.
        let over = FeedbackBox(x1: 100, y1: 100, x2: 1669, y2: 380)
        #expect(ItemCrop.shaped(over, imageSize: image) == FeedbackBox(x1: 100, y1: 100, x2: 1669, y2: 381))
    }

    @Test("Grows a box with a zero side")
    func shapedZeroSide() {
        let line = FeedbackBox(x1: 100, y1: 200, x2: 900, y2: 200)
        let shaped = ItemCrop.shaped(line, imageSize: image)
        // 800 / 5.6 rounded up is 143: 71 above and 72 below.
        #expect(shaped == FeedbackBox(x1: 100, y1: 129, x2: 900, y2: 272))
    }

    @Test("Returns nil when the image is too small on the short axis")
    func shapedTooSmall() {
        let row = FeedbackBox(x1: 100, y1: 50, x2: 1600, y2: 150)
        #expect(ItemCrop.shaped(row, imageSize: PixelSize(width: 2000, height: 200)) == nil)
    }

    // MARK: Worth it and file names

    @Test("A small crop is worth cutting and a near-full crop is not")
    func worthIt() {
        #expect(ItemCrop.isWorthIt(FeedbackBox(x1: 100, y1: 100, x2: 500, y2: 400), imageSize: image))
        #expect(!ItemCrop.isWorthIt(FeedbackBox(x1: 50, y1: 50, x2: 1950, y2: 1450), imageSize: image))
    }

    @Test("A crop at exactly half the visual tokens is worth cutting")
    func worthItAtHalf() {
        let square = PixelSize(width: 560, height: 560)
        // 400 tokens in the image. A 280 by 560 crop is 200 tokens.
        #expect(ItemCrop.isWorthIt(FeedbackBox(x1: 0, y1: 0, x2: 280, y2: 560), imageSize: square))
        #expect(!ItemCrop.isWorthIt(FeedbackBox(x1: 0, y1: 0, x2: 281, y2: 560), imageSize: square))
    }

    @Test("Names the crop files after the capture image and the badge number")
    func fileNames() {
        let names = ItemCrop.fileNames(imageFile: "0627-claude.png", badge: 2)
        #expect(names.annotated == "0627-claude-item-2.png")
        #expect(names.clean == "0627-claude-item-2-clean.png")

        let bare = ItemCrop.fileNames(imageFile: "capture", badge: 10)
        #expect(bare.annotated == "capture-item-10.png")
        #expect(bare.clean == "capture-item-10-clean.png")
    }

    @Test("Exposes the sizing constants")
    func constants() {
        #expect(ItemCrop.windowMargin == 200)
        #expect(ItemCrop.targetPad == 24)
        #expect(ItemCrop.marksPad == 120)
        #expect(ItemCrop.edgeStep == 0.25)
        #expect(ItemCrop.maxEdgeChecks == 2)
        #expect(ItemCrop.jevMinSide == 280)
        #expect(ItemCrop.jevMaxSide == 1568)
        #expect(abs(ItemCrop.maxAspect - 5.6) < 1e-9)
    }
}
