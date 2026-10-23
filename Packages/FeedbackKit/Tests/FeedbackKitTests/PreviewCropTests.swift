import Testing
@testable import FeedbackKit

@Suite("PreviewCrop")
struct PreviewCropTests {
    private let image = PixelSize(width: 2000, height: 1500)

    private func badge(_ number: Int, x: Int, y: Int, tip: FeedbackPoint? = nil) -> FeedbackMark {
        FeedbackMark(kind: .counter, badge: number, box: FeedbackBox(x1: x - 12, y1: y - 12, x2: x + 12, y2: y + 12), point: tip)
    }

    @Test("Centers the crop on the circle with margin on every side, at the preview's shape")
    func centersOnCircle() {
        let crops = PreviewCrop.cropsByBadge(marks: [badge(1, x: 500, y: 400)], imageSize: image, margin: 300, aspectRatio: 1.5)
        // Half sizes: 12 + 300 = 312 both ways, widened to 468 for 1.5:1.
        #expect(crops[1] == FeedbackBox(x1: 32, y1: 88, x2: 968, y2: 712))
    }

    @Test("Includes the box the circle sits on and keeps the circle in the middle")
    func includesShape() {
        let marks = [
            badge(2, x: 900, y: 610),
            FeedbackMark(kind: .rectangle, box: FeedbackBox(x1: 860, y1: 580, x2: 1500, y2: 700)),
        ]
        let crop = PreviewCrop.cropsByBadge(marks: marks, imageSize: image, margin: 300, aspectRatio: 1.5)[2]
        // Half width 600 + 300 = 900, half height 900 / 1.5 = 600, around (900, 610).
        #expect(crop == FeedbackBox(x1: 0, y1: 10, x2: 1800, y2: 1210))
    }

    @Test("Includes the point a circle's arrow aims at")
    func includesTip() {
        let crop = PreviewCrop.cropsByBadge(
            marks: [badge(1, x: 500, y: 400, tip: FeedbackPoint(x: 900, y: 400))],
            imageSize: image, margin: 100, aspectRatio: 1.5
        )[1]
        #expect(crop.map { $0.x2 >= 1000 } == true)
    }

    @Test("Slides the crop inside the image near an edge")
    func staysInsideImage() {
        let crop = PreviewCrop.cropsByBadge(marks: [badge(1, x: 20, y: 20)], imageSize: image, margin: 300, aspectRatio: 1.5)[1]
        #expect(crop == FeedbackBox(x1: 0, y1: 0, x2: 936, y2: 624))
    }

    @Test("Uses the whole image when the image is smaller than the crop")
    func smallImage() {
        let crop = PreviewCrop.cropsByBadge(marks: [badge(1, x: 200, y: 150)], imageSize: PixelSize(width: 400, height: 300), margin: 300, aspectRatio: 1.5)[1]
        #expect(crop == FeedbackBox(x1: 0, y1: 0, x2: 400, y2: 300))
    }

    @Test("Gives one crop per circle")
    func oneCropPerCircle() {
        let crops = PreviewCrop.cropsByBadge(
            marks: [badge(1, x: 500, y: 400), badge(2, x: 1500, y: 1000), FeedbackMark(kind: .arrow, box: FeedbackBox(x1: 0, y1: 0, x2: 10, y2: 10))],
            imageSize: image, margin: 300, aspectRatio: 1.5
        )
        #expect(Set(crops.keys) == [1, 2])
    }
}
