import Testing
@testable import FeedbackKit

@Suite("OneBreathSplitter")
struct OneBreathSplitterTests {
    static let wisprList = "1. Make the title brighter.\n2. Remove the line under it.\n3. Move the button left."
    static let spokenList = "One, make the title brighter. Two, remove the line under it. Three, move the button left."
    static let keywordList = "Circle two, remove the line. Circle three: move it left."
    static let oneLine = "1. Brighter. 2. Remove the line."
    static let leadText = "Here are my notes.\n1. Brighter.\n2. Remove."
    static let leadingSpaces = "  1. Brighter.\n2. Remove."
    static let repeatedCircle = "1. Brighter.\n2. Remove.\n1. Also bold."
    static let cueList = "1. Make it blue, no, gray.\n2. Actually, remove the line."
    static let upperCase = "ONE: brighter. TWO: remove."

    /// Every one-breath answer above, plus a few harder shapes, split with circles 1 to 3.
    static let oneBreathAnswers = [
        wisprList, spokenList, keywordList, oneLine, leadText, leadingSpaces,
        repeatedCircle, cueList, upperCase,
        "1. Brighter.\r\n2. Remove.\r\n",
        "1. Brighter.\n\n\n2. Remove.   \n",
        "Item 1 brighter. Badge two: remove it.",
        "1. 2. Remove.",
        "1. Café title brighter 👍.\n2. Remove the line.",
    ]

    // MARK: - Finding mentions

    @Test("Splits a numbered list from Wispr Flow into one part for each circle")
    func splitsNumberedList() {
        let result = OneBreathSplitter.split(Self.wisprList, circles: [1, 2, 3])
        #expect(result.isOneBreath)
        #expect(result.parts.map(\.circle) == [1, 2, 3])
        #expect(result.mentions.map(\.strength) == [.strong, .strong, .strong])
        #expect(result.parts.map(\.text) == [
            "1. Make the title brighter.\n",
            "2. Remove the line under it.\n",
            "3. Move the button left.",
        ])
        #expect(result.startsAtOne)
        #expect(result.coversAllCircles)
    }

    @Test("Splits a spoken list that uses number words as medium mentions")
    func splitsSpokenList() {
        let result = OneBreathSplitter.split(Self.spokenList, circles: [1, 2, 3])
        #expect(result.isOneBreath)
        #expect(result.parts.map(\.circle) == [1, 2, 3])
        #expect(result.mentions.map(\.strength) == [.medium, .medium, .medium])
        #expect(result.parts.map(\.text) == [
            "One, make the title brighter. ",
            "Two, remove the line under it. ",
            "Three, move the button left.",
        ])
    }

    @Test("Splits circle keyword mentions as strong and reports a list that does not start at 1")
    func splitsKeywordMentions() {
        let result = OneBreathSplitter.split(Self.keywordList, circles: [1, 2, 3])
        #expect(result.isOneBreath)
        #expect(result.parts.map(\.circle) == [2, 3])
        #expect(result.mentions.map(\.strength) == [.strong, .strong])
        #expect(result.mentions.map { Self.keywordList[$0.range] } == ["Circle two,", "Circle three:"])
        #expect(!result.startsAtOne)
        #expect(!result.coversAllCircles)
    }

    @Test("Marks a list mention after a sentence end on the same line as medium")
    func midLineMentionIsMedium() {
        let result = OneBreathSplitter.split(Self.oneLine, circles: [1, 2])
        #expect(result.isOneBreath)
        #expect(result.parts.map(\.circle) == [1, 2])
        #expect(result.mentions.map(\.strength) == [.strong, .medium])
        #expect(result.parts.map(\.text) == ["1. Brighter. ", "2. Remove the line."])
    }

    @Test("Keeps the mention token range on the number and its mark only")
    func mentionRangeCoversToken() {
        let result = OneBreathSplitter.split(Self.wisprList, circles: [1, 2, 3])
        #expect(result.mentions.map { Self.wisprList[$0.range] } == ["1.", "2.", "3."])
        #expect(result.parts.map { $0.mention?.circle } == [1, 2, 3])
    }

    @Test("Ignores a number that is not a mention", arguments: [
        "In footnote number one, restate the text.",
        "This number on page 3 does not match page 2.",
        "Show the hotkey where the 2 is, next to the 1.",
        "When we say 3 out of 5, show a Harvey ball.",
        "I can see now that invoices 1 and 2 are for the billing period.",
    ])
    func numberInsideSentenceIsNotMention(answer: String) {
        let result = OneBreathSplitter.split(answer, circles: [1, 2, 3, 4, 5])
        #expect(result.mentions.isEmpty)
        #expect(!result.isOneBreath)
        #expect(result.parts.isEmpty)
    }

    @Test("Does not split when only one circle is named")
    func oneCircleIsNotOneBreath() {
        let result = OneBreathSplitter.split("2. Remove the line.", circles: [1, 2])
        #expect(!result.isOneBreath)
        #expect(result.parts.isEmpty)
        #expect(result.mentions.map(\.circle) == [2])
    }

    @Test("Ignores a number that is not a circle of the capture")
    func nonCircleNumberIsNotMention() {
        let result = OneBreathSplitter.split("1. Brighter.\n3. Remove.", circles: [1, 2])
        #expect(result.mentions.map(\.circle) == [1])
        #expect(!result.isOneBreath)
        #expect(result.parts.isEmpty)
    }

    @Test("Ignores ordinal words and bullets")
    func ordinalsAndBulletsAreNotMentions() {
        let ordinals = OneBreathSplitter.split("First, rename it. Second, make it bold.", circles: [1, 2])
        #expect(ordinals.mentions.isEmpty)
        let bullets = OneBreathSplitter.split("- Rename it.\n- Make it bold.", circles: [1, 2])
        #expect(bullets.mentions.isEmpty)
    }

    @Test("Ignores decimals and clock times that start with a circle number")
    func decimalsAndTimesAreNotMentions() {
        let answer = "1. Pause for 3.5 seconds.\n2. Meet at 10:30 today."
        let result = OneBreathSplitter.split(answer, circles: [1, 2, 3, 10])
        #expect(result.mentions.map(\.circle) == [1, 2])
        #expect(result.isOneBreath)
    }

    @Test("Ignores a decimal or time at the start of a line")
    func decimalAtLineStartIsNotMention() {
        let result = OneBreathSplitter.split("3.5 seconds is too long.\n10:30 is wrong.", circles: [3, 10])
        #expect(result.mentions.isEmpty)
    }

    @Test("Matches mention words and keywords in any case")
    func mentionsIgnoreCase() {
        let result = OneBreathSplitter.split(Self.upperCase, circles: [1, 2])
        #expect(result.isOneBreath)
        #expect(result.parts.map(\.circle) == [1, 2])
        let keywords = OneBreathSplitter.split("BADGE 1 brighter. item two: remove.", circles: [1, 2])
        #expect(keywords.parts.map(\.circle) == [1, 2])
    }

    @Test("Returns no mentions for an empty answer")
    func emptyAnswer() {
        let result = OneBreathSplitter.split("", circles: [1, 2])
        #expect(result.mentions.isEmpty)
        #expect(!result.isOneBreath)
        #expect(result.parts.isEmpty)
        #expect(!result.startsAtOne)
        #expect(!result.coversAllCircles)
    }

    // MARK: - Parts

    @Test("Keeps text before the first mention as a lead part with no circle")
    func leadPart() {
        let result = OneBreathSplitter.split(Self.leadText, circles: [1, 2])
        #expect(result.parts.count == 3)
        #expect(result.parts.map(\.circle) == [nil, 1, 2])
        #expect(result.parts[0].mention == nil)
        #expect(result.parts[0].text == "Here are my notes.\n")
    }

    @Test("Keeps leading spaces in the first part instead of making a lead part")
    func leadingSpacesJoinFirstPart() {
        let answer = Self.leadingSpaces
        let result = OneBreathSplitter.split(answer, circles: [1, 2])
        #expect(result.parts.count == 2)
        #expect(result.parts[0].circle == 1)
        #expect(result.parts[0].range.lowerBound == answer.startIndex)
        #expect(result.parts[0].text == "  1. Brighter.\n")
        #expect(result.mentions[0].range.lowerBound == answer.index(answer.startIndex, offsetBy: 2))
    }

    @Test("Gives a repeated circle a part for each mention")
    func repeatedCircleGetsSeveralParts() {
        let result = OneBreathSplitter.split(Self.repeatedCircle, circles: [1, 2])
        #expect(result.parts.map(\.circle) == [1, 2, 1])
    }

    @Test("Joins the parts back into the exact answer", arguments: oneBreathAnswers)
    func partsJoinToAnswer(answer: String) {
        let result = OneBreathSplitter.split(answer, circles: [1, 2, 3])
        #expect(result.isOneBreath)
        #expect(result.parts.map(\.text).joined() == answer)
        #expect(result.parts.first?.range.lowerBound == answer.startIndex)
        #expect(result.parts.last?.range.upperBound == answer.endIndex)
        for (part, next) in zip(result.parts, result.parts.dropFirst()) {
            #expect(part.range.upperBound == next.range.lowerBound)
        }
        #expect(result.parts.allSatisfy { answer[$0.range] == $0.text })
    }

    // MARK: - Correction cues

    @Test("Reports correction cues in each part in lowercase")
    func correctionCues() {
        let result = OneBreathSplitter.split(Self.cueList, circles: [1, 2])
        #expect(result.parts.map(\.correctionCues) == [["no,"], ["actually"]])
    }

    @Test("Finds the other cues as whole words and phrases")
    func otherCues() {
        let answer = "1. Make it blue, I mean gray, wait, scratch that, sorry.\n2. Waiting is fine."
        let result = OneBreathSplitter.split(answer, circles: [1, 2])
        #expect(result.parts.map(\.correctionCues) == [["i mean", "wait", "scratch that", "sorry"], []])
    }

    @Test("Does not report no without a comma as a cue")
    func noWithoutCommaIsNotCue() {
        let result = OneBreathSplitter.split("1. No usage audit here.\n2. Remove the line.", circles: [1, 2])
        #expect(result.parts.map(\.correctionCues) == [[], []])
    }

    // MARK: - Clauses

    @Test("Splits a self-correction at commas and before a cue word")
    func clausesSplitAtCommasAndCues() {
        #expect(OneBreathSplitter.clauses(in: "Make it blue, no, gray.") == ["Make it blue,", " no,", " gray."])
        #expect(OneBreathSplitter.clauses(in: "Use gray actually.") == ["Use gray", " actually."])
        #expect(OneBreathSplitter.clauses(in: "Make it blue; I mean gray") == ["Make it blue;", " I mean gray"])
    }

    @Test("Returns one clause when the text has no comma or cue")
    func clausesWithoutBoundary() {
        #expect(OneBreathSplitter.clauses(in: "Make the title brighter.") == ["Make the title brighter."])
    }

    @Test("Returns no clauses for empty text")
    func clausesOfEmptyText() {
        #expect(OneBreathSplitter.clauses(in: "").isEmpty)
    }

    @Test("Never makes an empty clause when a cue starts the text", arguments: ["Actually, make it blue", "  wait, no", ",x"])
    func clausesHaveNoEmptyClause(text: String) {
        let clauses = OneBreathSplitter.clauses(in: text)
        #expect(clauses.allSatisfy { !$0.isEmpty })
        #expect(clauses.joined() == text)
    }

    @Test("Joins the clauses back into the exact text", arguments: oneBreathAnswers + [
        "Make it blue, no, gray.",
        "Use gray actually.",
        "No usage audit here.",
        "Sorry; wait, scratch that, I mean it.",
        "",
    ])
    func clausesJoinToText(text: String) {
        #expect(OneBreathSplitter.clauses(in: text).joined() == text)
    }
}
