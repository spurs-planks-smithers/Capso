import Foundation
@testable import FeedbackKit

/// Shared test data: the plan's sample capture 2 ("Pricing | Acme").
enum FeedbackFixtures {
    static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    static func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone,
            year: 2026, month: 10, day: day, hour: hour, minute: minute
        ).date!
    }

    static let pricingMarks: [FeedbackMark] = [
        FeedbackMark(
            kind: .counter, badge: 1,
            box: FeedbackBox(x1: 400, y1: 176, x2: 424, y2: 200),
            point: FeedbackPoint(x: 520, y: 240),
            ocrText: "Starter $19/mo",
            instruction: "Price is wrong, should be $15"
        ),
        FeedbackMark(
            kind: .counter, badge: 2,
            box: FeedbackBox(x1: 888, y1: 598, x2: 912, y2: 622),
            ocrText: "Badge-side text",
            instruction: "Make this the primary button"
        ),
        FeedbackMark(kind: .rectangle, box: FeedbackBox(x1: 860, y1: 580, x2: 1500, y2: 700), ocrText: "Compare plans"),
        FeedbackMark(kind: .counter, badge: 3, box: FeedbackBox(x1: 288, y1: 808, x2: 312, y2: 832), ocrText: "Billed annually"),
        FeedbackMark(kind: .arrow, box: FeedbackBox(x1: 100, y1: 400, x2: 300, y2: 420), point: FeedbackPoint(x: 300, y: 420)),
        FeedbackMark(kind: .text, box: FeedbackBox(x1: 640, y1: 300, x2: 900, y2: 340), textOnImage: "too much padding"),
    ]

    static func pricingCapture(index: Int = 2) -> FeedbackCapture {
        FeedbackCapture(
            index: index,
            imageFile: FeedbackNaming.imageFileName(index: index),
            cleanImageFile: FeedbackNaming.cleanImageFileName(index: index),
            size: PixelSize(width: 1840, height: 1012),
            capturedAt: date(20, 19, 14),
            sourceApp: "Safari",
            windowTitle: "Pricing | Acme",
            note: "The plan cards feel cramped on this page.",
            marks: pricingMarks
        )
    }

    static func session(captures: [FeedbackCapture]) -> FeedbackSession {
        FeedbackSession(
            name: "pricing page",
            slug: "pricing-page",
            folderName: "2026-10-20-1912-pricing-page",
            startedAt: date(20, 19, 12),
            captures: captures
        )
    }
}
