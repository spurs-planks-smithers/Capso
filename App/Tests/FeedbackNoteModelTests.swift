import XCTest
@testable import Capso

/// Ending the round while the note panel is open keeps the text typed in
/// the current step (#266). `commitInProgress()` is what the panel calls
/// when it closes.
@MainActor
final class FeedbackNoteModelTests: XCTestCase {
    private func makeModel(_ log: Log) -> FeedbackNoteModel {
        FeedbackNoteModel(
            steps: [.circle(1), .circle(2), .note],
            onAnswer: { step, text in log.answers.append((step, text)) },
            onFinish: { log.finished = true }
        )
    }

    private final class Log {
        var answers: [(FeedbackNoteStep, String)] = []
        var finished = false
    }

    func testCommitSendsTypedTextOfTheCurrentStep() {
        let log = Log()
        let model = makeModel(log)
        model.text = "  make the price bigger \n"
        model.commitInProgress()
        XCTAssertEqual(log.answers.count, 1)
        XCTAssertEqual(log.answers.first?.0, .circle(1))
        XCTAssertEqual(log.answers.first?.1, "make the price bigger")
        XCTAssertFalse(log.finished)
    }

    func testCommitWithNothingTypedSendsNothing() {
        let log = Log()
        let model = makeModel(log)
        model.commitInProgress()
        XCTAssertTrue(log.answers.isEmpty)
    }

    func testCommitDoesNotSendAnAnswerAlreadySaved() {
        let log = Log()
        let model = makeModel(log)
        model.text = "first"
        model.submit()
        XCTAssertEqual(log.answers.count, 1)
        // Now on step 2 with an empty field: nothing new to save.
        model.commitInProgress()
        XCTAssertEqual(log.answers.count, 1)
    }

    func testCommitAfterTheLastStepWasSkippedKeepsTheSkip() {
        let log = Log()
        let model = makeModel(log)
        model.skip()
        model.skip()
        model.text = "typed, then Esc"
        model.skip()
        XCTAssertTrue(log.finished)
        model.commitInProgress()
        XCTAssertTrue(log.answers.isEmpty)
    }

    func testCommitLeavesLaterStepsEmpty() {
        let log = Log()
        let model = makeModel(log)
        model.text = "one"
        model.submit()
        model.skip()
        model.text = "general"
        model.commitInProgress()
        XCTAssertEqual(log.answers.map(\.0), [.circle(1), .note])
        XCTAssertEqual(log.answers.map(\.1), ["one", "general"])
    }
}
