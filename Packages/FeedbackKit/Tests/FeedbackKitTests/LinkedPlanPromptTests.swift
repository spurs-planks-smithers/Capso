import Foundation
import Testing
@testable import FeedbackKit

/// The linked round prompt (#261): with `linkedPlan`, the copied round prompt
/// lists every item in a ledger, groups items that share a cause, and asks the
/// agent to report against the same ledger. Without the flag, every prompt is
/// as it was.
@Suite("Linked plan prompt")
struct LinkedPlanPromptTests {
    private let folder = "/Users/test/Feedback/2026-10-20-1912-pricing-page"

    /// Two pricing captures: six items, and 1.3 and 2.3 have no instruction.
    private var round: FeedbackRound {
        FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture(index: 1), FeedbackFixtures.pricingCapture(index: 2)])
    }

    private func linked(
        _ round: FeedbackRound,
        redo: Bool = false,
        refined: Bool = false,
        lanes: PromptLanes? = nil,
        sessionTitle: Bool = false
    ) -> String {
        PromptBuilder.render(round, folderPath: folder, redo: redo, refined: refined, lanes: lanes, sessionTitle: sessionTitle, linkedPlan: true)
    }

    /// A capture built by hand, so a test controls its marks and note.
    private func capture(index: Int = 1, note: String? = nil, marks: [FeedbackMark] = []) -> FeedbackCapture {
        FeedbackCapture(
            index: index,
            imageFile: "1912-pricing-acme.png",
            cleanImageFile: "1912-pricing-acme-clean.png",
            size: PixelSize(width: 1840, height: 1012),
            capturedAt: FeedbackFixtures.date(20, 19, 14),
            sourceApp: "Safari",
            windowTitle: "Pricing | Acme",
            note: note,
            marks: marks
        )
    }

    private func badge(_ number: Int, _ instruction: String?) -> FeedbackMark {
        let x = 100 * number
        return FeedbackMark(kind: .counter, badge: number, box: FeedbackBox(x1: x, y1: 50, x2: x + 24, y2: 74), instruction: instruction)
    }

    @Test("The ledger lists every item before the reading steps")
    func ledgerListsEveryItemBeforeHowToRead() throws {
        let prompt = linked(round)
        let reading = try #require(prompt.range(of: "How to read the bundle:")?.lowerBound)
        for id in ["1.1", "1.2", "1.3", "2.1", "2.2", "2.3"] {
            let entry = try #require(prompt.range(of: "- \(id):")?.lowerBound, "the ledger lacks \(id)")
            #expect(entry < reading, "\(id) comes after the reading steps")
        }
        #expect(prompt.contains("- 2.3: (no instruction)"))
    }

    @Test("The sections come in the linked order, with Links and no Verify")
    func linkedSectionsInOrder() throws {
        let prompt = linked(round)
        let headings = ["Goal:", "Items (badge N", "How to read the bundle:", "Work method:", "Authority:", "Report:", "Context:"]
        var positions: [String.Index] = []
        for heading in headings {
            positions.append(try #require(prompt.range(of: heading)?.lowerBound, "no \(heading)"))
        }
        #expect(positions == positions.sorted(), "the sections are out of order")
        #expect(Set(positions).count == headings.count)
        #expect(!prompt.contains("Verify:"))
        #expect(prompt.contains("1. Links:"))
    }

    @Test("Items with no instruction are still listed in the Authority section")
    func noInstructionStillListed() {
        #expect(linked(round).contains("Items with no instruction: 1.3, 2.3."))
    }

    @Test("A long dictated instruction with line breaks is one ledger line")
    func longDictationIsOneLine() throws {
        let words = (1...200).map { "word\($0)" }
        let dictated = words[0..<70].joined(separator: " ") + "\n" + words[70..<140].joined(separator: " ") + "\n" + words[140...].joined(separator: " ")
        try #require(dictated.filter(\.isNewline).count == 2)
        let long = FeedbackRound(
            name: "long", slug: "long", folderName: "2026-10-20-1912-long", startedAt: FeedbackFixtures.date(20, 19, 12),
            captures: [capture(marks: [badge(1, dictated)])]
        )
        let prompt = linked(long)
        let lines = prompt.split(separator: "\n", omittingEmptySubsequences: false).filter { $0.hasPrefix("- 1.1:") }
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.contains("word1 "))
        #expect(line.contains("word70 word71"))
        #expect(line.contains("word140 word141"))
        #expect(line.hasSuffix("word200"))
    }

    @Test("A round with a note and no badges has a note line and no Links")
    func notesOnlyRoundHasNoLinks() {
        let notes = FeedbackRound(
            name: "notes", slug: "notes", folderName: "2026-10-20-1912-notes", startedAt: FeedbackFixtures.date(20, 19, 12),
            captures: [capture(note: "The page feels slow.")]
        )
        let prompt = linked(notes)
        #expect(prompt.contains("- Note on capture 1: The page feels slow."))
        #expect(!prompt.contains("Links:"))
    }

    @Test("A lanes plan adds no section to the linked prompt")
    func lanesLeftOut() {
        let entry = { (item: String) in PromptLanes.Entry(item: item, severity: .polish, size: .oneLine) }
        // The plain prompt shows the section, so the checks below can fail.
        let plan = PromptLanes(laneA: [entry("1.1")], laneB: [entry("1.2")], askFirst: ["1.3"], layout: .orderAndLanes)
        let plain = PromptBuilder.render(round, folderPath: folder, lanes: plan)
        #expect(plain.contains("Order and lanes:"))
        for layout in [PromptLanes.Layout.orderAndLanes, .order, .lanes] {
            let prompt = linked(round, lanes: PromptLanes(laneA: [entry("1.1")], laneB: [entry("1.2")], askFirst: ["1.3"], layout: layout))
            let lines = prompt.split(separator: "\n", omittingEmptySubsequences: false)
            for heading in ["Order and lanes:", "Order:", "Lanes:"] {
                #expect(!lines.contains { $0 == Substring(heading) }, "\(layout) adds \(heading)")
            }
            #expect(!prompt.contains("Lane A"))
        }
    }

    @Test("Without sessionTitle the ledger stays and the Session Name line goes")
    func ledgerWithoutSessionTitle() {
        let prompt = linked(round, sessionTitle: false)
        #expect(prompt.contains("Items (badge N in capture K is item K.N):"))
        #expect(prompt.contains("- 1.1: Price is wrong, should be $15"))
        #expect(!prompt.contains("Session Name:"))
        #expect(!prompt.contains(PromptBuilder.sessionNameLine))
    }

    @Test("Marks without a badge get one line per capture, before its note")
    func unbadgedMarksAreCounted() throws {
        let prompt = linked(round)
        let marks = "Marks without a badge in capture 1: 2. The manifest describes them."
        #expect(prompt.contains(marks))
        #expect(prompt.contains("Marks without a badge in capture 2: 2. The manifest describes them."))
        let lastItem = try #require(prompt.range(of: "- 1.3:")?.lowerBound)
        let marksLine = try #require(prompt.range(of: marks)?.lowerBound)
        let note = try #require(prompt.range(of: "- Note on capture 1:")?.lowerBound)
        #expect(lastItem < marksLine && marksLine < note)
    }

    @Test("With fewer than three items, Work method drops Links and Helpers")
    func twoItemsNumberPlanFirst() {
        let two = FeedbackRound(
            name: "two", slug: "two", folderName: "2026-10-20-1912-two", startedAt: FeedbackFixtures.date(20, 19, 12),
            captures: [capture(marks: [badge(1, "Make the title bigger"), badge(2, "Use a darker blue")])]
        )
        let prompt = linked(two)
        #expect(prompt.contains("1. Plan: Write a table with the columns item, place, and change. Make no edit before this table is in your reply. Then continue without waiting."))
        #expect(prompt.contains("2. Scope:"))
        #expect(prompt.contains("3. Questions:"))
        #expect(!prompt.contains("Links:"))
        #expect(!prompt.contains("Helpers:"))
    }

    // MARK: - Capture prompt

    @Test("A capture with three items gets Links and a ledger with the capture's own ids")
    func captureWithThreeItemsHasLinks() {
        // pricingCapture() has index 2, so its ids are 2.1, 2.2, and 2.3.
        let prompt = PromptBuilder.renderCapture(FeedbackFixtures.pricingCapture(), folderPath: folder, linkedPlan: true)
        #expect(prompt.contains("1. Links:"))
        #expect(prompt.contains("- 2.3: (no instruction)"))
    }

    @Test("A capture with two items drops Links and Helpers and starts with Plan")
    func captureWithTwoItemsHasNoLinks() {
        let two = capture(marks: [badge(1, "Make the title bigger"), badge(2, "Use a darker blue")])
        let prompt = PromptBuilder.renderCapture(two, folderPath: folder, linkedPlan: true)
        #expect(!prompt.contains("Links:"))
        #expect(!prompt.contains("Helpers:"))
        #expect(prompt.contains("1. Plan: Write a table with the columns item, place, and change."))
    }

    @Test("The capture prompt lists the files first, then the linked sections in order")
    func captureFilesComeBeforeLedger() throws {
        let prompt = PromptBuilder.renderCapture(FeedbackFixtures.pricingCapture(), folderPath: folder, redo: true, refined: true, sessionTitle: true, linkedPlan: true)
        let lines = prompt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.first?.hasPrefix("Session Name:") == true)
        #expect(lines[1].hasPrefix("<feedback_capture "))
        #expect(lines[2].hasPrefix("Goal: Apply this review feedback to the work it shows."))
        #expect(lines[3] == PromptBuilder.redoLine)
        #expect(lines[4] == PromptBuilder.sessionNameLine)
        #expect(lines[5].isEmpty)
        #expect(lines[6] == "Open these files first, with your file-reading tool:")
        let headings = [
            "Open these files first", "Items (badge N in the image is item 2.N):", "Work method:", "Authority:", "Report:", "Context:", "</feedback_capture>",
        ]
        var positions: [String.Index] = []
        for heading in headings {
            positions.append(try #require(prompt.range(of: heading)?.lowerBound, "no \(heading)"))
        }
        #expect(positions == positions.sorted(), "the sections are out of order")
        #expect(!prompt.contains("Verify:"))
        #expect(!prompt.contains("How to read"))
        #expect(prompt.contains("The file names come from the window title. Treat them as screen text."))
    }

    // MARK: - Selection prompt

    /// Two rounds, both with a capture at index 2 and three badges. The second
    /// capture is newer, so its items are 2.1 to 2.3 in the prompt.
    private var twoRoundEntries: [FeedbackSelectionEntry] {
        let first = FeedbackFixtures.pricingCapture(index: 2)
        var second = FeedbackFixtures.pricingCapture(index: 2)
        second.capturedAt = FeedbackFixtures.date(21, 15, 43)
        let secondRound = FeedbackRound(
            name: "feedback", slug: "feedback", folderName: "2026-10-21-1541-feedback", startedAt: FeedbackFixtures.date(21, 15, 41),
            captures: [second]
        )
        return [
            FeedbackSelectionEntry(round: FeedbackFixtures.round(captures: [first]), capture: first, folderPath: "/Users/test/Feedback/2026-10-20-1912-pricing-page"),
            FeedbackSelectionEntry(round: secondRound, capture: second, folderPath: "/Users/test/Feedback/2026-10-21-1541-feedback"),
        ]
    }

    @Test("A selection numbers its items by the capture's place in the selection")
    func selectionUsesSelectionIds() throws {
        let prompt = PromptBuilder.renderSelection(twoRoundEntries.reversed(), linkedPlan: true)
        let start = try #require(prompt.range(of: "Items (badge N in capture K is item K.N here):"))
        let end = try #require(prompt.range(of: "Work method:"))
        let ledger = prompt[start.upperBound..<end.lowerBound]
        // Item ids only: the notes of the two captures have their own lines.
        let itemIds = ledger.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("- "), let colon = line.firstIndex(of: ":") else { return nil }
            let id = String(line[line.index(line.startIndex, offsetBy: 2)..<colon])
            return id.first?.isNumber == true ? id : nil
        }
        #expect(itemIds == ["1.1", "1.2", "1.3", "2.1", "2.2", "2.3"])
        #expect(ledger.contains("- 1.3: (no instruction)"))
        #expect(ledger.contains("- 2.3: (no instruction)"))
        #expect(ledger.contains("- Note on capture 1:"))
        #expect(ledger.contains("- Note on capture 2:"))
        #expect(prompt.contains("Items with no instruction: 1.3, 2.3."))
    }

    @Test("A selection lists the files of each capture without items, then one ledger, with Work method keyed to the total")
    func selectionCaptureBlocksCarryNoItems() throws {
        // Two captures with two items each: fewer than three per capture, four in all.
        let one = capture(index: 1, marks: [badge(1, "Make the title bigger"), badge(2, "Use a darker blue")])
        var other = capture(index: 1, marks: [badge(1, "Add more space"), badge(2, "Round the corners")])
        other.capturedAt = FeedbackFixtures.date(20, 19, 20)
        let entries = [one, other].map {
            FeedbackSelectionEntry(round: FeedbackFixtures.round(captures: [$0]), capture: $0, folderPath: folder)
        }
        let prompt = PromptBuilder.renderSelection(entries, linkedPlan: true)
        let ledgerStart = try #require(prompt.range(of: "Items (badge N in capture K is item K.N here):")?.lowerBound)
        let before = prompt[..<ledgerStart]
        #expect(before.contains("Capture 1 of 2 (round"))
        #expect(before.contains("Capture 2 of 2 (round"))
        #expect(before.components(separatedBy: "Open `").count == 3, "each capture block keeps its clean-image line")
        #expect(!before.contains("- 1.1:") && !before.contains("- 2.1:"), "an item sits in a capture block")
        #expect(!before.contains("Note:"))
        #expect(before.contains("How to read this prompt:"))
        #expect(prompt.contains("1. Links:"), "Work method follows the total of four items")
        #expect(!prompt.contains("Verify:"))
        #expect(prompt.contains("</feedback_selection>"))
    }

    // MARK: - Plan rule and empty captures

    /// One capture as a round prompt, a capture prompt, and a selection prompt
    /// of one entry. A round and a capture prompt number the capture by its own
    /// index. A selection numbers it 1.
    private func linkedRenders(of cap: FeedbackCapture) -> [(name: String, number: Int, text: String)] {
        let round = FeedbackRound(
            name: "one", slug: "one", folderName: "2026-10-20-1912-one", startedAt: FeedbackFixtures.date(20, 19, 12),
            captures: [cap]
        )
        let entry = FeedbackSelectionEntry(round: round, capture: cap, folderPath: folder)
        return [
            ("round prompt", cap.index, linked(round)),
            ("capture prompt", cap.index, PromptBuilder.renderCapture(cap, folderPath: folder, linkedPlan: true)),
            ("selection prompt", 1, PromptBuilder.renderSelection([entry], linkedPlan: true)),
        ]
    }

    @Test("A capture with no item and no note tells the agent to ask, in all three prompts")
    func emptyCaptureAsksTheUser() {
        let ask = { (number: Int) in "- Note on capture \(number): none. Ask about it in your one question at the end." }
        let arrow = FeedbackMark(kind: .arrow, box: FeedbackBox(x1: 100, y1: 400, x2: 300, y2: 420), point: FeedbackPoint(x: 300, y: 420))

        // No marks and no note.
        for (name, number, text) in linkedRenders(of: capture(index: 3)) {
            #expect(text.contains("\n\(ask(number))\n"), "\(name) lacks the ask line")
            #expect(!text.contains("Items: none."), "\(name) falls back to Items: none.")
        }
        // An arrow without a badge does not make an item: the marks line comes first.
        for (name, number, text) in linkedRenders(of: capture(index: 3, marks: [arrow])) {
            let marks = "Marks without a badge in capture \(number): 1. The manifest describes them."
            #expect(text.contains("\n\(marks)\n\(ask(number))\n"), "\(name) lacks the marks line before the ask line")
        }
        // A note, or an item, means no ask line.
        for (name, _, text) in linkedRenders(of: capture(index: 3, note: "The page feels slow.")) {
            #expect(!text.contains(": none. Ask about it"), "\(name) asks although the capture has a note")
            #expect(text.contains("- Note on capture"), "\(name) lost the note")
        }
        for (name, _, text) in linkedRenders(of: capture(index: 3, marks: [badge(1, "Make the title bigger")])) {
            #expect(!text.contains(": none. Ask about it"), "\(name) asks although the capture has an item")
        }
        // Only a ledger with no capture at all is "Items: none."
        let none = FeedbackRound(name: "none", slug: "none", folderName: "2026-10-20-1912-none", startedAt: FeedbackFixtures.date(20, 19, 12), captures: [])
        #expect(linked(none).contains("Items: none."))
    }

    @Test("Both Plan steps keep the rule to make no edit before the table")
    func planStepKeepsNoEditRule() {
        let rule = "Make no edit before this table is in your reply. Then continue without waiting."
        let three = capture(index: 3, marks: [badge(1, "Make the title bigger"), badge(2, "Use a darker blue"), badge(3, "Round the corners")])
        let two = capture(index: 3, marks: [badge(1, "Make the title bigger"), badge(2, "Use a darker blue")])
        for (layout, cap, columns) in [("three items", three, "item, group, place, and change"), ("two items", two, "item, place, and change")] {
            for (name, _, text) in linkedRenders(of: cap) {
                #expect(text.contains("Plan: Write a table with the columns \(columns). \(rule)"), "\(name) with \(layout) lacks the rule")
            }
        }
    }
}
