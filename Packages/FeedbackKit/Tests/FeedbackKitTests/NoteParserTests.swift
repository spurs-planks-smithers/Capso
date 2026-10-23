import Testing
@testable import FeedbackKit

@Suite("NoteParser")
struct NoteParserTests {
    @Test("Turns text that starts with a badge number into that badge's instruction")
    func badgeLineBecomesInstruction() {
        let result = NoteParser.parse("1: fix price", badges: [1, 2])
        #expect(result.instructions == [1: "fix price"])
        #expect(result.note == nil)
    }

    @Test("Keeps other lines as the capture note")
    func otherLinesStayInNote() {
        let result = NoteParser.parse("The plan cards feel cramped.\n2: Make this the primary button", badges: [1, 2])
        #expect(result.instructions == [2: "Make this the primary button"])
        #expect(result.note == "The plan cards feel cramped.")
    }

    @Test("Splits a one-line note at semicolons")
    func splitsAtSemicolons() {
        let result = NoteParser.parse("1: fix price; 2: make primary; cards feel cramped", badges: [1, 2])
        #expect(result.instructions == [1: "fix price", 2: "make primary"])
        #expect(result.note == "cards feel cramped")
    }

    @Test("Keeps a number that is not a badge in the note")
    func unknownNumberStaysInNote() {
        let result = NoteParser.parse("10:30 meeting; 5: check this", badges: [1])
        #expect(result.instructions.isEmpty)
        #expect(result.note == "10:30 meeting; 5: check this")
    }

    @Test("Keeps a badge number with no text in the note")
    func emptyInstructionStaysInNote() {
        let result = NoteParser.parse("1:", badges: [1])
        #expect(result.instructions.isEmpty)
        #expect(result.note == "1:")
    }

    @Test("Joins two instructions for the same badge")
    func repeatedBadgeJoinsInstructions() {
        let result = NoteParser.parse("1: fix price; 1: use bold", badges: [1])
        #expect(result.instructions == [1: "fix price; use bold"])
    }

    @Test("Returns no note for blank text")
    func blankTextHasNoNote() {
        let result = NoteParser.parse("   \n ", badges: [1])
        #expect(result.note == nil)
        #expect(result.instructions.isEmpty)
    }
}
