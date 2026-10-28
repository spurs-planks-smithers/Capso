import Foundation
import Testing
@testable import FeedbackKit

/// The title of a round for the Recent menu (#164): reviewer words only.
@Suite("RoundTitle")
struct RoundTitleTests {
    /// A round whose captures hold the given instructions (one badge each) and notes.
    private func round(instructions: [String?] = [], notes: [String?] = [], windowTitle: String? = nil, ocr: String? = nil) -> FeedbackRound {
        var captures: [FeedbackCapture] = []
        let count = max(1, notes.count)
        for offset in 0..<count {
            let marks = (offset == 0 ? instructions : []).enumerated().map { index, text in
                FeedbackMark(
                    kind: .counter, badge: index + 1,
                    box: FeedbackBox(x1: 40 * index, y1: 10, x2: 40 * index + 24, y2: 34),
                    ocrText: ocr, instruction: text
                )
            }
            captures.append(FeedbackCapture(
                index: offset + 1,
                imageFile: "1900-a.png",
                cleanImageFile: "1900-a-clean.png",
                size: PixelSize(width: 100, height: 100),
                capturedAt: FeedbackFixtures.date(20, 19, 0),
                sourceApp: "Safari",
                windowTitle: windowTitle,
                note: notes.indices.contains(offset) ? notes[offset] : nil,
                ocrText: ocr,
                marks: marks
            ))
        }
        return FeedbackFixtures.round(captures: captures)
    }

    @Test("Uses the first instruction of the fixture round")
    func fixtureRound() {
        let fixture = FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture()])
        #expect(RoundTitle.title(for: fixture) == "Price is wrong, should be $15")
    }

    @Test("Strips lead-in words and the question mark")
    func leadIns() {
        #expect(RoundTitle.title(for: round(instructions: ["Please can you make this button bigger?"])) == "Make this button bigger")
        #expect(RoundTitle.title(for: round(instructions: ["I want to change the header color"])) == "Change the header color")
        #expect(RoundTitle.title(for: round(instructions: ["make sure to align the logo left"])) == "Align the logo left")
        #expect(RoundTitle.title(for: round(instructions: ["I\u{2019}d like to see a larger logo"])) == "See a larger logo")
    }

    @Test("Stops at the first sentence end and keeps decimals whole")
    func firstClause() {
        #expect(RoundTitle.title(for: round(instructions: ["Make the header sticky. Also fix the footer."])) == "Make the header sticky")
        #expect(RoundTitle.title(for: round(instructions: ["Change $19.99 to $15.99 on the card"])) == "Change $19.99 to $15.99 on the card")
    }

    @Test("Joins a dictated answer with line breaks into one line")
    func oneLine() {
        #expect(RoundTitle.title(for: round(instructions: ["Make this\n\nbigger   now"])) == "Make this bigger now")
    }

    @Test("Cuts a long answer at a word end with an ellipsis, within the limit")
    func longAnswer() throws {
        let long = "make the pricing table header sticky when the reader scrolls down the page on a small laptop screen"
        let title = try #require(RoundTitle.title(for: round(instructions: [long])))
        #expect(title.count <= RoundTitle.maxLength)
        #expect(title.hasSuffix("\u{2026}"))
        #expect(title.hasPrefix("Make the pricing table header sticky"))
        // The cut falls on a word end: the text before the ellipsis is a prefix of whole words.
        let body = String(title.dropLast())
        #expect(long.capitalizedFirst.hasPrefix(body))
        #expect(!body.hasSuffix(" "))
    }

    @Test("Skips an answer of under three words when a longer one exists")
    func prefersLongerAnswer() {
        #expect(RoundTitle.title(for: round(instructions: ["Bigger", "Move the price above the plan name"])) == "Move the price above the plan name")
        #expect(RoundTitle.title(for: round(instructions: ["Bigger", "Darker"])) == "Bigger")
    }

    @Test("Uses the first capture note when no item has an instruction")
    func fallsBackToNote() {
        #expect(RoundTitle.title(for: round(notes: ["Spacing looks off in the cards"])) == "Spacing looks off in the cards")
        #expect(RoundTitle.title(for: round(instructions: ["Bigger"], notes: ["Spacing looks off in the cards"])) == "Spacing looks off in the cards")
    }

    @Test("Returns nil when the round holds no reviewer words, and never uses screen text")
    func nilWithoutReviewerWords() {
        #expect(RoundTitle.title(for: round()) == nil)
        #expect(RoundTitle.title(for: round(notes: ["   \n "])) == nil)
        #expect(RoundTitle.title(for: round(instructions: ["please"])) == nil)
        // Window title, app name, and OCR text are screen text. They never become a title.
        #expect(RoundTitle.title(for: round(instructions: [nil], windowTitle: "Quarterly Revenue Report", ocr: "Confidential totals")) == nil)
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
