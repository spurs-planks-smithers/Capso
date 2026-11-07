import Foundation
import Testing
@testable import FeedbackKit

/// One naming rule for a round row, a capture row, and the session name line
/// (Drew, 2026-11-02): five words at most, articles not counted. A stored
/// summary leads, and the reviewer's cut title is the fallback for a round.
@Suite("Round and capture names")
struct RoundNamesTests {
    private var capture: FeedbackCapture { FeedbackFixtures.pricingCapture(index: 1) }

    private func summaries(_ name: String, for captures: [FeedbackCapture]) throws -> SummaryNames {
        var names = SummaryNames()
        names.set(name, forInput: try #require(SummaryNames.input(of: captures)))
        return names
    }

    @Test("limitWords keeps five words and does not count articles")
    func limitWords() {
        #expect(RoundTitle.limitWords("Pricing table header sticky") == "Pricing table header sticky")
        #expect(RoundTitle.limitWords("Fix the price on a pricing card") == "Fix the price on a pricing card")
        #expect(RoundTitle.limitWords("Fix the price on the pricing card header") == "Fix the price on the pricing card\u{2026}")
        #expect(RoundTitle.limitWords("One two three four five six") == "One two three four five\u{2026}")
    }

    @Test("limitWords drops an article and a mark that end the cut")
    func limitWordsTrailing() {
        #expect(RoundTitle.limitWords("One two three four five the six") == "One two three four five\u{2026}")
        #expect(RoundTitle.limitWords("One two three four five, six") == "One two three four five\u{2026}")
    }

    @Test("The model reply is cut to five words")
    func replyIsCut() {
        #expect(SummaryNames.cleaned("Pricing page header and footer spacing issues") == "Pricing page header and footer\u{2026}")
    }

    @Test("A round row uses the stored summary, and the cut title without one")
    func roundName() throws {
        let round = FeedbackFixtures.round(captures: [capture])
        let stored = try summaries("Pricing page layout", for: round.captures)
        #expect(SessionName.displayName(for: round, summaries: stored) == "Pricing page layout")
        #expect(SessionName.displayName(for: round, summaries: .none) == RoundTitle.title(for: round))
    }

    @Test("A stored summary longer than five words is cut on the way out")
    func storedSummaryIsCut() throws {
        let round = FeedbackFixtures.round(captures: [capture])
        let stored = try summaries("Pricing page header and footer spacing issues", for: round.captures)
        #expect(SessionName.displayName(for: round, summaries: stored) == "Pricing page header and footer\u{2026}")
    }

    @Test("A capture row has a summary name only when one is stored")
    func captureName() throws {
        let stored = try summaries("Price on pricing card", for: [capture])
        #expect(SessionName.summaryName(for: [capture], summaries: stored) == "Price on pricing card")
        #expect(SessionName.summaryName(for: [capture], summaries: .none) == nil)
    }

    @Test("The capture row title prefers the summary, then the page name")
    func captureRowTitle() {
        var capture = capture
        capture.windowTitle = "Pricing - Example"
        let zone = FeedbackFixtures.timeZone
        let locale = Locale(identifier: "en_US")
        let withName = FeedbackLibrary.captureRowTitle(capture, summaryName: "Price on pricing card", timeZone: zone, locale: locale)
        let without = FeedbackLibrary.captureRowTitle(capture, summaryName: nil, timeZone: zone, locale: locale)
        #expect(withName.hasSuffix(" Price on pricing card"))
        #expect(without.hasSuffix(" Pricing - Example"))
    }

    @Test("The session name line shows the same name as the round row")
    func sameMethod() throws {
        let round = FeedbackFixtures.round(captures: [capture])
        let stored = try summaries("Pricing page layout", for: round.captures)
        let line = SessionName.line(for: round, summaries: stored)
        #expect(line.hasSuffix(" - Pricing page layout"))
    }
}
