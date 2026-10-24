import Foundation
import Testing
@testable import FeedbackKit

@Suite("AnchorCandidates")
struct AnchorCandidatesTests {
    private func badge(_ number: Int, x: Int, y: Int, tip: FeedbackPoint? = nil) -> FeedbackMark {
        FeedbackMark(kind: .counter, badge: number, box: FeedbackBox(x1: x - 12, y1: y - 12, x2: x + 12, y2: y + 12), point: tip)
    }

    private func capture(
        marks: [FeedbackMark] = [],
        note: String? = nil,
        ocrText: String? = nil,
        size: PixelSize = PixelSize(width: 2000, height: 1500)
    ) -> FeedbackCapture {
        FeedbackCapture(
            index: 1,
            imageFile: "0627-claude.png",
            cleanImageFile: "0627-claude-clean.png",
            size: size,
            capturedAt: Date(timeIntervalSince1970: 0),
            note: note,
            ocrText: ocrText,
            marks: marks
        )
    }

    private func line(_ text: String, x: Int, y: Int, width: Int = 120, height: Int = 20) -> FeedbackTextLine {
        FeedbackTextLine(text: text, box: FeedbackBox(x1: x, y1: y, x2: x + width, y2: y + height))
    }

    private func texts(_ set: AnchorCandidateSet, _ ids: [String]) -> [String] {
        ids.compactMap { id in set.lines.first { $0.id == id }?.text }
    }

    private func numbered(_ prefix: String, _ count: Int) -> [String] {
        (0..<count).map { "\(prefix) \(String(format: "%03d", $0))" }
    }

    // MARK: Item candidates

    @Test("Keeps the 40 lines nearest the seed and leaves out lines beyond the window")
    func windowFilterAndCap() {
        var lines = (0..<50).map { line("Item \(String(format: "%02d", $0))", x: 520 + $0 * 3, y: 395, width: 100) }
        lines.append(line("Far away text", x: 1500, y: 1200))
        let set = AnchorCandidates.build(capture: capture(marks: [badge(1, x: 500, y: 400)]), lines: lines)

        let ids = set.itemCandidates[1] ?? []
        #expect(ids.count == 40)
        #expect(texts(set, ids) == (0..<40).map { "Item \(String(format: "%02d", $0))" })
        #expect(set.lines.count == 40)
        #expect(!set.lines.map(\.text).contains("Far away text"))
        #expect(set.captureCandidates == nil)
    }

    @Test("Lists the nearest line first")
    func nearestFirst() {
        let lines = [
            line("Third line", x: 300, y: 260),
            line("First line", x: 300, y: 200),
            line("Fourth line", x: 420, y: 260),
            line("Second line", x: 420, y: 200),
        ]
        let set = AnchorCandidates.build(capture: capture(marks: [badge(1, x: 500, y: 400)]), lines: lines)
        // Ids follow reading order. The item's list follows distance from the seed.
        #expect(set.lines.map(\.text) == ["First line", "Second line", "Third line", "Fourth line"])
        #expect(texts(set, set.itemCandidates[1] ?? []) == ["Fourth line", "Third line", "Second line", "First line"])
    }

    @Test("Adds every line under a mark, even when more than 40 lines are nearer")
    func marksForcedBeyondCap() {
        let marks = [
            badge(1, x: 320, y: 320),
            FeedbackMark(kind: .rectangle, box: FeedbackBox(x1: 300, y1: 300, x2: 1100, y2: 700)),
        ]
        // 50 lines with their centers inside the box: all at distance 0 from the seed.
        let names = numbered("Row", 50)
        let lines = names.enumerated().map { line($1, x: 320, y: 310 + $0 * 7, width: 200, height: 6) }
        let set = AnchorCandidates.build(capture: capture(marks: marks), lines: lines)

        let ids = set.itemCandidates[1] ?? []
        #expect(ids.count == 50)
        #expect(Set(texts(set, ids)) == Set(names))
        #expect(Set(ids).count == 50)
    }

    @Test("Caps an item at 250 options, so a Choice never passes 255")
    func capsOptions() {
        let marks = [
            badge(1, x: 20, y: 20),
            FeedbackMark(kind: .rectangle, box: FeedbackBox(x1: 0, y1: 0, x2: 2000, y2: 1500)),
        ]
        // 300 lines under one box that covers the whole capture.
        let lines = numbered("Row", 300).enumerated().map { line($1, x: 100 + ($0 % 10) * 180, y: 10 + ($0 / 10) * 45) }
        let set = AnchorCandidates.build(capture: capture(marks: marks), lines: lines)
        #expect(set.itemCandidates[1]?.count == AnchorCandidates.maxOptions)
    }

    @Test("Breaks a distance tie by reading order, not by input order")
    func tieBreaksByReadingOrder() {
        // Both line centers are 188 pixels from the badge, one on each side.
        let lines = [
            line("Right label", x: 640, y: 390),
            line("Left label", x: 240, y: 390),
        ]
        let set = AnchorCandidates.build(capture: capture(marks: [badge(1, x: 500, y: 400)]), lines: lines)
        #expect(texts(set, set.itemCandidates[1] ?? []) == ["Left label", "Right label"])
    }

    @Test("Drops a line under a Redact mark, even when the caller did not")
    func dropsRedactedLines() {
        let marks = [
            badge(1, x: 500, y: 400),
            FeedbackMark(kind: .pixelate, box: FeedbackBox(x1: 300, y1: 440, x2: 700, y2: 480)),
        ]
        let lines = [
            line("Visible label", x: 400, y: 360),
            line("Account 4417 1234", x: 400, y: 450),
        ]
        let set = AnchorCandidates.build(capture: capture(marks: marks), lines: lines)
        #expect(set.lines.map(\.text) == ["Visible label"])
    }

    @Test("A line's source stays its position in the input when a Redact mark drops an earlier line")
    func sourceCountsRedactedLines() {
        let marks = [
            badge(1, x: 500, y: 400),
            FeedbackMark(kind: .pixelate, box: FeedbackBox(x1: 300, y1: 440, x2: 700, y2: 480)),
        ]
        let lines = [
            line("Account 4417 1234", x: 400, y: 450),
            line("Visible label", x: 400, y: 360),
        ]
        let set = AnchorCandidates.build(capture: capture(marks: marks), lines: lines)
        #expect(set.lines == [AnchorLine(id: "L001", text: "Visible label", source: 1, box: lines[1].box)])
    }

    @Test("Drops the partial last line of a stored block that was cut")
    func dropsCutLastLine() {
        let filler = String(repeating: "Settings row label\n", count: 280)
        let block = filler + "Partial last li..."
        #expect(block.unicodeScalars.count > ScreenText.maxBlockLength)
        let set = AnchorCandidates.build(capture: capture(marks: [badge(1, x: 500, y: 400)], ocrText: block), lines: nil)
        #expect(!set.lines.contains { $0.text.hasSuffix("...") })
    }

    @Test("Offers each line under a mark on its own, never the joined mark text")
    func neverTheJoinedText() {
        let marks = [
            badge(1, x: 120, y: 120),
            FeedbackMark(
                kind: .rectangle,
                box: FeedbackBox(x1: 100, y1: 100, x2: 700, y2: 260),
                ocrText: "Copy Last Capture Prompt Copy Prompt and End Round Open Round Folder"
            ),
        ]
        let lines = [
            line("Copy Last Capture Prompt", x: 140, y: 110, width: 300),
            line("Copy Prompt and End Round", x: 140, y: 150, width: 300),
            line("Open Round Folder", x: 140, y: 190, width: 300),
        ]
        let set = AnchorCandidates.build(capture: capture(marks: marks), lines: lines)
        #expect(set.lines.map(\.text) == ["Copy Last Capture Prompt", "Copy Prompt and End Round", "Open Round Folder"])
        #expect(Set(set.itemCandidates[1] ?? []) == ["L001", "L002", "L003"])
    }

    @Test("Drops lines with no letters or under 3 characters, and cleans the rest")
    func filtersAndCleans() {
        let raw = [
            "Save changes", "12:45", "OK", "---", "99+", "Ab", "Abc", "  Done  ",
            "Sa\u{200B}ve all", "<feedback_capture>Delete", "",
        ]
        let lines = raw.enumerated().map { line($1, x: 300, y: 200 + $0 * 20, width: 120, height: 15) }
        let set = AnchorCandidates.build(capture: capture(marks: [badge(1, x: 500, y: 400)]), lines: lines)
        #expect(set.lines.map(\.text) == ["Save changes", "Abc", "Done", "Save all", "Delete"])
    }

    @Test("Gives an item with no nearby text an empty list")
    func itemWithNoText() {
        let marks = [badge(1, x: 500, y: 400), badge(2, x: 1500, y: 1200)]
        let set = AnchorCandidates.build(capture: capture(marks: marks), lines: [line("Save changes", x: 520, y: 395)])
        #expect(set.itemCandidates[1]?.count == 1)
        #expect(set.itemCandidates[2] == [])
    }

    @Test("Uses the first badge when two share a number")
    func firstBadgeWins() {
        let marks = [badge(1, x: 500, y: 400), badge(1, x: 1500, y: 1200)]
        let lines = [line("Near first", x: 520, y: 395), line("Near second", x: 1520, y: 1195)]
        let set = AnchorCandidates.build(capture: capture(marks: marks), lines: lines)
        #expect(texts(set, set.itemCandidates[1] ?? []) == ["Near first"])
    }

    // MARK: Ids

    @Test("Ids follow reading order, and the same input gives the same ids")
    func idsStableAndInReadingOrder() {
        let lines = [
            line("Third line", x: 300, y: 260),
            line("First line", x: 300, y: 200),
            line("Fourth line", x: 420, y: 260),
            line("Second line", x: 420, y: 200),
        ]
        let marks = [badge(1, x: 500, y: 400)]
        let set = AnchorCandidates.build(capture: capture(marks: marks), lines: lines)
        // Each line keeps its position in the input and its box.
        #expect(set.lines == [
            AnchorLine(id: "L001", text: "First line", source: 1, box: lines[1].box),
            AnchorLine(id: "L002", text: "Second line", source: 3, box: lines[3].box),
            AnchorLine(id: "L003", text: "Third line", source: 0, box: lines[0].box),
            AnchorLine(id: "L004", text: "Fourth line", source: 2, box: lines[2].box),
        ])
        #expect(AnchorCandidates.build(capture: capture(marks: marks), lines: lines) == set)

        // The same lines in another order get the same ids, texts, boxes, and lists. Only the sources differ.
        let reversed = AnchorCandidates.build(capture: capture(marks: marks), lines: lines.reversed())
        #expect(reversed.lines.map(\.id) == set.lines.map(\.id))
        #expect(reversed.lines.map(\.text) == set.lines.map(\.text))
        #expect(reversed.lines.map(\.box) == set.lines.map(\.box))
        #expect(reversed.lines.map(\.source) == [2, 0, 3, 1])
        #expect(reversed.itemCandidates == set.itemCandidates)
    }

    @Test("A line near two items has one id and appears in both lists")
    func sharedLineHasOneId() {
        let marks = [badge(1, x: 500, y: 400), badge(2, x: 560, y: 400)]
        let set = AnchorCandidates.build(capture: capture(marks: marks), lines: [line("Shared label", x: 520, y: 395)])
        #expect(set.lines.count == 1)
        #expect(set.itemCandidates[1] == ["L001"])
        #expect(set.itemCandidates[2] == ["L001"])
    }

    @Test("Ids grow past three digits when a capture has more than 999 lines")
    func idsPastThreeDigits() {
        var marks: [FeedbackMark] = []
        var lines: [FeedbackTextLine] = []
        for item in 0..<30 {
            let x = 300 + (item % 6) * 1000
            let y = 300 + (item / 6) * 1000
            marks.append(badge(item + 1, x: x, y: y))
            for row in 0..<40 {
                lines.append(line("Row \(item)-\(row)", x: x + 30, y: y - 150 + row * 8, width: 100, height: 6))
            }
        }
        let set = AnchorCandidates.build(capture: capture(marks: marks, size: PixelSize(width: 6200, height: 5200)), lines: lines)
        #expect(set.lines.count == 1200)
        #expect(set.lines.first?.id == "L001")
        #expect(set.lines[998].id == "L999")
        #expect(set.lines[999].id == "L1000")
        #expect(set.lines.last?.id == "L1200")
        #expect(Set(set.lines.map(\.id)).count == 1200)
    }

    // MARK: Fallback

    @Test("Falls back to the stored OCR block when there are no line boxes")
    func fallbackFromOCRText() {
        let ocr = "Save changes\n12:45\nOK\nCancel\n\nOpen Round Folder"
        let marks = [badge(1, x: 500, y: 400), badge(2, x: 900, y: 600)]
        for lines in [nil, []] as [[FeedbackTextLine]?] {
            let set = AnchorCandidates.build(capture: capture(marks: marks, ocrText: ocr), lines: lines)
            // The source is the row in the stored block, counting the dropped rows. There is no box.
            #expect(set.lines == [
                AnchorLine(id: "L001", text: "Save changes", source: 0),
                AnchorLine(id: "L002", text: "Cancel", source: 3),
                AnchorLine(id: "L003", text: "Open Round Folder", source: 5),
            ])
            #expect(set.itemCandidates[1] == ["L001", "L002", "L003"])
            #expect(set.itemCandidates[2] == ["L001", "L002", "L003"])
            #expect(set.captureCandidates == nil)
        }
    }

    @Test("The fallback keeps the first 120 lines in order")
    func fallbackCap() {
        let names = numbered("Line", 150)
        let set = AnchorCandidates.build(
            capture: capture(marks: [badge(1, x: 500, y: 400)], ocrText: names.joined(separator: "\n")),
            lines: nil
        )
        #expect(set.lines.count == 120)
        #expect(set.lines.first == AnchorLine(id: "L001", text: "Line 000", source: 0))
        #expect(set.lines.last == AnchorLine(id: "L120", text: "Line 119", source: 119))
        #expect(set.itemCandidates[1]?.count == 120)
    }

    @Test("Line boxes win over the stored OCR block")
    func boxesWinOverOCRText() {
        let set = AnchorCandidates.build(
            capture: capture(marks: [badge(1, x: 500, y: 400)], ocrText: "Stored only text"),
            lines: [line("Boxed text", x: 520, y: 395)]
        )
        #expect(set.lines.map(\.text) == ["Boxed text"])
    }

    @Test("Has no candidates when there are no boxes and no OCR block")
    func nothingToOffer() {
        let set = AnchorCandidates.build(capture: capture(marks: [badge(1, x: 500, y: 400)]), lines: nil)
        #expect(set.lines.isEmpty)
        #expect(set.itemCandidates[1] == [])
    }

    // MARK: Capture-level candidates

    @Test("A capture with no badges and a note gets capture-level candidates in reading order")
    func captureLevelCandidates() {
        let lines = [
            line("Beta text", x: 300, y: 400),
            line("12:45", x: 300, y: 300),
            line("Alpha text", x: 300, y: 100),
        ]
        let set = AnchorCandidates.build(capture: capture(note: "The header is wrong"), lines: lines)
        #expect(set.lines == [
            AnchorLine(id: "L001", text: "Alpha text", source: 2, box: lines[2].box),
            AnchorLine(id: "L002", text: "Beta text", source: 0, box: lines[0].box),
        ])
        #expect(set.captureCandidates == ["L001", "L002"])
        #expect(set.itemCandidates.isEmpty)
    }

    @Test("Capture-level candidates stop at 120 lines")
    func captureLevelCap() {
        let names = numbered("Line", 150)
        let lines = names.enumerated().map { line($1, x: 100, y: $0 * 10, width: 100, height: 8) }
        let set = AnchorCandidates.build(capture: capture(note: "Wrong header"), lines: lines.reversed())
        #expect(set.lines.count == 120)
        #expect(set.captureCandidates?.count == 120)
        #expect(set.lines.first?.text == "Line 000")
        #expect(set.lines.last?.text == "Line 119")
    }

    @Test("Capture-level candidates use the stored OCR block when there are no boxes")
    func captureLevelFallback() {
        let set = AnchorCandidates.build(capture: capture(note: "Wrong header", ocrText: "Alpha text\nBeta text"), lines: nil)
        #expect(set.captureCandidates == ["L001", "L002"])
        #expect(set.lines.map(\.text) == ["Alpha text", "Beta text"])
    }

    @Test("A capture with no badges and no note gets nothing")
    func noNoteNoCandidates() {
        let lines = [line("Alpha text", x: 300, y: 100)]
        for note in [nil, "", "  \n "] as [String?] {
            let set = AnchorCandidates.build(capture: capture(note: note, ocrText: "Alpha text"), lines: lines)
            #expect(set.captureCandidates == nil)
            #expect(set.lines.isEmpty)
            #expect(set.itemCandidates.isEmpty)
        }
    }

    @Test("A capture with badges never gets capture-level candidates")
    func badgesNoCaptureLevel() {
        let set = AnchorCandidates.build(
            capture: capture(marks: [badge(1, x: 500, y: 400)], note: "General note"),
            lines: [line("Save changes", x: 520, y: 395)]
        )
        #expect(set.captureCandidates == nil)
        #expect(set.itemCandidates[1]?.count == 1)
    }

    // MARK: Pick

    private let offered = ["L001", "L002"]
    private let lines = [
        AnchorLine(id: "L001", text: "Copy  Last Capture", source: 0),
        AnchorLine(id: "L002", text: "Open Round Folder", source: 1),
        AnchorLine(id: "L003", text: "Not offered", source: 2),
    ]

    private func pick(
        _ choice: String?,
        fits: Double = 0.9,
        confidence: Double = 0.8,
        fitsThreshold: Double = 0.5,
        confidenceThreshold: Double = 0.5
    ) -> AnchorPick {
        AnchorCandidates.pick(
            choice: choice, offered: offered, fits: fits, confidence: confidence,
            fitsThreshold: fitsThreshold, confidenceThreshold: confidenceThreshold, lines: lines
        )
    }

    @Test("Picks the offered line with its text unchanged")
    func pickReturnsExactText() {
        #expect(pick("L001") == .picked(id: "L001", text: "Copy  Last Capture"))
    }

    @Test("Rejects a choice that is missing, not offered, or unknown")
    func pickInvalidChoice() {
        #expect(pick(nil) == .invalid)
        #expect(pick("L003") == .invalid)
        #expect(pick("L999") == .invalid)
        #expect(pick("copy last capture") == .invalid)
        #expect(AnchorCandidates.pick(
            choice: "L004", offered: ["L004"], fits: 0.9, confidence: 0.9,
            fitsThreshold: 0.5, confidenceThreshold: 0.5, lines: lines
        ) == .invalid)
    }

    @Test("Rejects a score that is not finite or is outside 0 to 1")
    func pickInvalidScores() {
        #expect(pick("L001", fits: 1.2) == .invalid)
        #expect(pick("L001", fits: -0.1) == .invalid)
        #expect(pick("L001", confidence: 1.5) == .invalid)
        #expect(pick("L001", fits: .nan) == .invalid)
        #expect(pick("L001", confidence: .infinity) == .invalid)
    }

    @Test("Says none fit when either score is below its threshold")
    func pickNoneFit() {
        #expect(pick("L001", fits: 0.4) == .noneFit)
        #expect(pick("L001", confidence: 0.4) == .noneFit)
        #expect(pick("L001", fits: 0.1, confidence: 0.1) == .noneFit)
    }

    @Test("A score equal to its threshold passes")
    func pickAtThreshold() {
        #expect(pick("L002", fits: 0.5, confidence: 0.5) == .picked(id: "L002", text: "Open Round Folder"))
    }
}

@Suite("OCRMatcher matched lines")
struct OCRMatcherMatchedLinesTests {
    private let lines = [
        FeedbackTextLine(text: "Copy Prompt", box: FeedbackBox(x1: 120, y1: 150, x2: 300, y2: 170)),
        FeedbackTextLine(text: "Open Folder", box: FeedbackBox(x1: 120, y1: 190, x2: 300, y2: 210)),
        FeedbackTextLine(text: "Copy Last", box: FeedbackBox(x1: 120, y1: 110, x2: 300, y2: 130)),
        FeedbackTextLine(text: "Side label", box: FeedbackBox(x1: 320, y1: 110, x2: 440, y2: 130)),
        FeedbackTextLine(text: "Footer", box: FeedbackBox(x1: 10, y1: 1700, x2: 90, y2: 1720)),
    ]

    private func texts(_ mark: FeedbackMark, maxDistance: Int = OCRMatcher.defaultMaxDistance) -> [String] {
        OCRMatcher.matchedLines(for: mark, lines: lines, maxDistance: maxDistance).map(\.text)
    }

    @Test("A region mark returns each line inside it, in reading order")
    func regionLines() {
        let box = FeedbackMark(kind: .rectangle, box: FeedbackBox(x1: 100, y1: 100, x2: 460, y2: 220))
        #expect(texts(box) == ["Copy Last", "Side label", "Copy Prompt", "Open Folder"])
        let narrow = FeedbackMark(kind: .ellipse, box: FeedbackBox(x1: 100, y1: 100, x2: 310, y2: 220))
        #expect(texts(narrow) == ["Copy Last", "Copy Prompt", "Open Folder"])
    }

    @Test("An arrow returns the line at its head, else the nearest line in reach")
    func arrowLines() {
        let onLine = FeedbackMark(kind: .arrow, box: FeedbackBox(x1: 0, y1: 0, x2: 200, y2: 160), point: FeedbackPoint(x: 200, y: 160))
        #expect(texts(onLine) == ["Copy Prompt"])
        let nearLine = FeedbackMark(kind: .arrow, box: FeedbackBox(x1: 0, y1: 0, x2: 200, y2: 176), point: FeedbackPoint(x: 200, y: 176))
        #expect(texts(nearLine) == ["Copy Prompt"])
        #expect(texts(nearLine, maxDistance: 5).isEmpty)
        let noHead = FeedbackMark(kind: .arrow, box: FeedbackBox(x1: 0, y1: 0, x2: 200, y2: 160))
        #expect(texts(noHead).isEmpty)
    }

    @Test("A badge with a tip returns the line at the tip, not the lines it touches")
    func badgeWithTip() {
        let badge = FeedbackMark(
            kind: .counter, badge: 1,
            box: FeedbackBox(x1: 108, y1: 108, x2: 132, y2: 132),
            point: FeedbackPoint(x: 200, y: 200)
        )
        #expect(texts(badge) == ["Open Folder"])
    }

    @Test("A badge with no tip returns the lines it touches, else the nearest line")
    func badgeWithoutTip() {
        let touching = FeedbackMark(kind: .counter, badge: 1, box: FeedbackBox(x1: 280, y1: 120, x2: 330, y2: 160))
        #expect(texts(touching) == ["Copy Last", "Side label", "Copy Prompt"])
        let nearby = FeedbackMark(kind: .counter, badge: 2, box: FeedbackBox(x1: 60, y1: 190, x2: 84, y2: 214))
        #expect(texts(nearby) == ["Open Folder"])
        let alone = FeedbackMark(kind: .counter, badge: 3, box: FeedbackBox(x1: 1500, y1: 900, x2: 1524, y2: 924))
        #expect(texts(alone).isEmpty)
    }

    @Test("A text mark returns no lines")
    func textMark() {
        let text = FeedbackMark(kind: .text, box: FeedbackBox(x1: 100, y1: 100, x2: 460, y2: 220), textOnImage: "too tight")
        #expect(texts(text).isEmpty)
    }

}
