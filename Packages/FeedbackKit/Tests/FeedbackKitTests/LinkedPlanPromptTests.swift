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
        #expect(prompt.contains("1. Plan: Write a table with the columns item, place, and change. Then continue without waiting."))
        #expect(prompt.contains("2. Scope:"))
        #expect(prompt.contains("3. Questions:"))
        #expect(!prompt.contains("Links:"))
        #expect(!prompt.contains("Helpers:"))
    }
}
