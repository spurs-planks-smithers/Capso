import Testing
@testable import FeedbackKit

@Suite("OCRMatcher")
struct OCRMatcherTests {
    private let lines = [
        FeedbackTextLine(text: "Starter $19/mo", box: FeedbackBox(x1: 480, y1: 225, x2: 640, y2: 255)),
        FeedbackTextLine(text: "Compare plans", box: FeedbackBox(x1: 900, y1: 620, x2: 1100, y2: 660)),
        FeedbackTextLine(text: "Billed annually", box: FeedbackBox(x1: 320, y1: 810, x2: 450, y2: 830)),
        FeedbackTextLine(text: "Footer", box: FeedbackBox(x1: 10, y1: 1700, x2: 90, y2: 1720)),
    ]

    private func match(_ mark: FeedbackMark) -> String? {
        OCRMatcher.assignText(to: [mark], lines: lines).first?.ocrText
    }

    @Test("Collects the text inside a box mark")
    func textInsideBox() {
        let box = FeedbackMark(kind: .rectangle, box: FeedbackBox(x1: 860, y1: 580, x2: 1500, y2: 700))
        #expect(match(box) == "Compare plans")
    }

    @Test("Reads the text at an arrow head")
    func textAtArrowHead() {
        let arrow = FeedbackMark(kind: .arrow, box: FeedbackBox(x1: 300, y1: 100, x2: 520, y2: 240), point: FeedbackPoint(x: 520, y: 240))
        #expect(match(arrow) == "Starter $19/mo")
    }

    @Test("Reads the text at a badge's arrow tip before the text next to the badge")
    func badgeTipWins() {
        let badge = FeedbackMark(
            kind: .counter, badge: 1,
            box: FeedbackBox(x1: 300, y1: 800, x2: 324, y2: 824),
            point: FeedbackPoint(x: 520, y: 240)
        )
        #expect(match(badge) == "Starter $19/mo")
    }

    @Test("Reads the nearest text next to a badge with no tip")
    func textNextToBadge() {
        let badge = FeedbackMark(kind: .counter, badge: 3, box: FeedbackBox(x1: 288, y1: 808, x2: 312, y2: 832))
        #expect(match(badge) == "Billed annually")
    }

    @Test("Leaves the OCR text empty when no text is near the mark")
    func nothingNearby() {
        let badge = FeedbackMark(kind: .counter, badge: 4, box: FeedbackBox(x1: 1500, y1: 1200, x2: 1524, y2: 1224))
        #expect(match(badge) == nil)
    }

    @Test("Drops OCR lines that a redaction touches")
    func dropsRedactedLines() {
        let redaction = FeedbackMark(kind: .pixelate, box: FeedbackBox(x1: 470, y1: 220, x2: 560, y2: 250))
        let visible = OCRMatcher.removingRedacted(lines, marks: [redaction])
        #expect(!visible.map(\.text).contains("Starter $19/mo"))
        #expect(visible.count == lines.count - 1)
    }

    @Test("Sets no OCR text on a text mark")
    func textMarkHasNoOCR() {
        let text = FeedbackMark(kind: .text, box: FeedbackBox(x1: 860, y1: 580, x2: 1500, y2: 700), textOnImage: "too much padding")
        #expect(match(text) == nil)
    }
}
