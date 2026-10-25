import CoreGraphics
import Foundation
import Testing
@testable import FeedbackKit

/// The zip's name, its size ladder, and its own round (#85).
@Suite("Zip plan")
struct ZipPlanTests {
    static let sourceRoot = "/Users/someone.else/Library/Application Support/Nextshot"

    static func entries(_ round: FeedbackRound) -> [FeedbackSelectionEntry] {
        round.captures.map {
            FeedbackSelectionEntry(round: round, capture: $0, folderPath: "\(sourceRoot)/\(round.folderName)")
        }
    }

    /// Badge number and the index of its shape in `marks`, per item.
    static func pairs(_ capture: FeedbackCapture) -> [String] {
        FeedbackItems.split(capture).items.map { item in
            let shape = item.shape.flatMap { capture.marks.firstIndex(of: $0) }.map(String.init) ?? "none"
            return "\(item.badge.badge ?? 0):\(shape)"
        }
    }

    static func box(_ b: FeedbackBox) -> CGRect {
        CGRect(x: b.x1, y: b.y1, width: b.x2 - b.x1, height: b.y2 - b.y1)
    }

    @Test("Names a round zip and a selection zip by kind, time, and count")
    func roundName() {
        let time = FeedbackFixtures.date(25, 6, 37)
        let zone = FeedbackFixtures.timeZone
        #expect(ZipName.base(kind: .round, time: time, captureCount: 3, timeZone: zone) == "nextshot-round-2026-10-25-0637-3-captures")
        #expect(ZipName.base(kind: .round, time: time, captureCount: 1, timeZone: zone) == "nextshot-round-2026-10-25-0637-1-capture")
        #expect(ZipName.base(kind: .selection, time: time, captureCount: 5, timeZone: zone) == "nextshot-selection-2026-10-25-0637-5-captures")
    }

    @Test("The ladder lowers quality first, then pixels")
    func ladderSteps() {
        #expect(ZipLadder.step(0) == ZipStep(annotatedQuality: 0.75, cleanQuality: 0.75, pixelScale: 1))
        #expect(ZipLadder.step(1) == ZipStep(annotatedQuality: 0.75, cleanQuality: 0.50, pixelScale: 1))
        #expect(ZipLadder.step(2) == ZipStep(annotatedQuality: 0.60, cleanQuality: 0.50, pixelScale: 1))
        #expect(ZipLadder.step(3) == ZipStep(annotatedQuality: 0.60, cleanQuality: 0.50, pixelScale: 0.85))
        #expect(abs(ZipLadder.step(4).pixelScale - 0.85 * 0.85) < 1e-9)
        #expect(ZipLadder.budgetBytes == 5_000_000)
        #expect(ZipLadder.floorLongEdge == 1000)
    }

    @Test("A target size is the standard tier size and never larger than the source")
    func targetSizeNeverEnlarges() {
        let small = PixelSize(width: 932, height: 591)
        #expect(ZipLadder.targetSize(small, pixelScale: 1) == small)
        let large = PixelSize(width: 1988, height: 1134)
        #expect(ZipLadder.targetSize(large, pixelScale: 1) == ImageSizing.resizedSize(large, limits: .standard))
        let scaled = ZipLadder.targetSize(large, pixelScale: 0.85)
        #expect(scaled.width < ImageSizing.resizedSize(large, limits: .standard).width)
    }

    @Test("A tall, narrow capture keeps the floor on its long edge")
    func tallCaptureKeepsFloor() {
        let tall = PixelSize(width: 900, height: 6000)
        let base = ImageSizing.resizedSize(tall, limits: .standard)
        let floored = ZipLadder.targetSize(tall, pixelScale: 0.01)
        #expect(max(floored.width, floored.height) == min(1000, max(base.width, base.height)))

        var capture = FeedbackFixtures.pricingCapture()
        capture.size = tall
        capture.marks = []
        let round = FeedbackFixtures.round(captures: [capture])
        let plan = ZipPlanner.plan(kind: .round, entries: Self.entries(round), folderName: "z", zipTime: FeedbackFixtures.date(25, 7, 0), pixelScale: 0.01)
        #expect(plan.atFloor)
        let unscaled = ZipPlanner.plan(kind: .round, entries: Self.entries(round), folderName: "z", zipTime: FeedbackFixtures.date(25, 7, 0), pixelScale: 1)
        #expect(!unscaled.atFloor)
    }

    @Test("A round zip keeps each capture's index and renames its files")
    func roundPlanKeepsIndexAndRenames() throws {
        let round = FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture(index: 2), FeedbackFixtures.pricingCapture(index: 3)])
        let plan = ZipPlanner.plan(kind: .round, entries: Self.entries(round), folderName: "nextshot-round-x", zipTime: FeedbackFixtures.date(25, 7, 0), pixelScale: 1)

        #expect(plan.round.captures.map(\.index) == [2, 3])
        #expect(plan.round.captures.map(\.imageFile) == ["2-1914-pricing-acme.jpg", "3-1915-pricing-acme.jpg"])
        #expect(plan.round.captures.map(\.cleanImageFile) == ["2-1914-pricing-acme-clean.jpg", "3-1915-pricing-acme-clean.jpg"])
        #expect(plan.round.captures.map(\.promptFile) == ["2-1914-pricing-acme-prompt.md", "3-1915-pricing-acme-prompt.md"])
        #expect(plan.round.folderName == "nextshot-round-x")
        #expect(plan.round.name == round.name)
        #expect(plan.sourceRoundLines.isEmpty)

        try #require(plan.images.count == 4)
        #expect(plan.images[0].fileName == "2-1914-pricing-acme.jpg")
        #expect(plan.images[0].isClean == false)
        #expect(plan.images[0].sourceURL.path == "\(Self.sourceRoot)/2026-10-20-1912-pricing-page/1914-pricing-acme.png")
        #expect(plan.images[1].fileName == "2-1914-pricing-acme-clean.jpg")
        #expect(plan.images[1].isClean)
        #expect(plan.images[1].sourceURL.lastPathComponent == "1914-pricing-acme-clean.png")
    }

    @Test("A selection zip numbers captures 1 to N by time and lists its source rounds")
    func selectionPlanRenumbersByTime() {
        let roundA = FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture(index: 2), FeedbackFixtures.pricingCapture(index: 3)])
        var later = FeedbackFixtures.pricingCapture(index: 1)
        later.capturedAt = FeedbackFixtures.date(21, 9, 5)
        // The same stem as round A's capture 2, so only K keeps the names apart.
        later.imageFile = "1914-pricing-acme.png"
        later.cleanImageFile = "1914-pricing-acme-clean.png"
        let roundB = FeedbackRound(name: "other", slug: "other", folderName: "2026-10-21-0900-other", startedAt: FeedbackFixtures.date(21, 9, 0), captures: [later])
        // Passed out of order on purpose.
        let entries = Self.entries(roundB) + Self.entries(roundA).reversed()
        let zipTime = FeedbackFixtures.date(25, 7, 2)
        let plan = ZipPlanner.plan(kind: .selection, entries: entries, folderName: "nextshot-selection-x", zipTime: zipTime, pixelScale: 1)

        #expect(plan.round.captures.map(\.index) == [1, 2, 3])
        #expect(plan.round.captures.map(\.imageFile) == ["1-1914-pricing-acme.jpg", "2-1915-pricing-acme.jpg", "3-1914-pricing-acme.jpg"])
        #expect(plan.round.name == "selection")
        #expect(plan.round.slug == "selection")
        #expect(plan.round.startedAt == FeedbackFixtures.date(20, 19, 14))
        #expect(plan.round.endedAt == zipTime)
        #expect(plan.sourceRoundLines == [
            "- 2026-10-20-1912-pricing-page: its captures 2 and 3, here 1 and 2",
            "- 2026-10-21-0900-other: its capture 1, here 3",
        ])
    }

    @Test("Every box and point is scaled to the zip image")
    func marksScaleToImage() throws {
        let source = FeedbackFixtures.pricingCapture()
        let round = FeedbackFixtures.round(captures: [source])
        let plan = ZipPlanner.plan(kind: .round, entries: Self.entries(round), folderName: "z", zipTime: FeedbackFixtures.date(25, 7, 0), pixelScale: 1)
        let capture = try #require(plan.round.captures.first)

        #expect(capture.size == ImageSizing.resizedSize(source.size, limits: .standard))
        #expect(plan.images.map(\.size) == [capture.size, capture.size])
        try #require(capture.marks.count == source.marks.count)
        for (scaled, original) in zip(capture.marks, source.marks) {
            #expect(scaled.box == ImageSizing.scale(Self.box(original.box), from: source.size, to: capture.size))
            if let point = original.point {
                #expect(scaled.point == ImageSizing.scale(CGPoint(x: point.x, y: point.y), from: source.size, to: capture.size))
            }
            #expect(scaled.kind == original.kind)
            #expect(scaled.instruction == original.instruction)
            #expect(scaled.ocrText == original.ocrText)
        }
    }

    @Test("Badge and shape pairs stay the same after scaling")
    func pairingSurvivesScaling() throws {
        let fixture = FeedbackFixtures.pricingCapture()
        let fixturePlan = ZipPlanner.plan(kind: .round, entries: Self.entries(FeedbackFixtures.round(captures: [fixture])), folderName: "z", zipTime: FeedbackFixtures.date(25, 7, 0), pixelScale: 1)
        #expect(Self.pairs(try #require(fixturePlan.round.captures.first)) == Self.pairs(fixture))

        // Find a column where a 1 px gap closes after rounding at the target size.
        let size = PixelSize(width: 3000, height: 1700)
        let target = ZipLadder.targetSize(size, pixelScale: 1)
        let ratio = Double(target.width) / Double(size.width)
        let gap = try #require((200..<2800).first { x in
            (Double(x - 1) * ratio).rounded() == (Double(x) * ratio).rounded()
        })
        var capture = FeedbackFixtures.pricingCapture()
        capture.size = size
        capture.marks = [
            FeedbackMark(kind: .counter, badge: 1, box: FeedbackBox(x1: gap, y1: 400, x2: gap + 40, y2: 440), instruction: "Fix this"),
            FeedbackMark(kind: .rectangle, box: FeedbackBox(x1: gap - 300, y1: 380, x2: gap - 1, y2: 460)),
        ]
        #expect(Self.pairs(capture) == ["1:none"])
        // Without the repair, plain scaling to the target pairs them.
        var naive = capture
        naive.size = target
        naive.marks = capture.marks.map { mark in
            var mark = mark
            mark.box = ImageSizing.scale(Self.box(mark.box), from: size, to: target)
            return mark
        }
        #expect(Self.pairs(naive) == ["1:1"], "the fixture no longer closes the gap")
        let plan = ZipPlanner.plan(kind: .round, entries: Self.entries(FeedbackFixtures.round(captures: [capture])), folderName: "z", zipTime: FeedbackFixtures.date(25, 7, 0), pixelScale: 1)
        #expect(Self.pairs(try #require(plan.round.captures.first)) == ["1:none"])
    }

    @Test("A capture with no badges stays in the plan")
    func captureWithNoBadges() throws {
        var capture = FeedbackFixtures.pricingCapture()
        capture.marks = []
        capture.note = nil
        let plan = ZipPlanner.plan(kind: .round, entries: Self.entries(FeedbackFixtures.round(captures: [capture])), folderName: "z", zipTime: FeedbackFixtures.date(25, 7, 0), pixelScale: 1)
        let planned = try #require(plan.round.captures.first)
        #expect(PromptBuilder.renderCapture(planned, paths: .relative(exportFolderName: "x")).contains("Items: none."))
    }
}
