import Foundation
import Testing
@testable import FeedbackKit

@Suite("FeedbackNaming")
struct FeedbackNamingTests {
    @Test("Builds a lowercase hyphenated slug from the session name")
    func slugFromName() {
        #expect(FeedbackNaming.slug(from: "Pricing Page!") == "pricing-page")
        #expect(FeedbackNaming.slug(from: "  Café   Menu ") == "cafe-menu")
        #expect(FeedbackNaming.slug(from: "Q3/Q4 deck v2") == "q3-q4-deck-v2")
    }

    @Test("Falls back to feedback when the name has no letters or digits")
    func slugFallback() {
        #expect(FeedbackNaming.slug(from: "") == "feedback")
        #expect(FeedbackNaming.slug(from: "***") == "feedback")
    }

    @Test("Caps the slug at 40 characters with no trailing hyphen")
    func slugLengthCap() {
        let slug = FeedbackNaming.slug(from: String(repeating: "abc ", count: 20))
        #expect(slug.count <= 40)
        #expect(!slug.hasSuffix("-"))
    }

    @Test("Names the folder with the local start time and the slug")
    func folderName() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone,
            year: 2026, month: 10, day: 20, hour: 19, minute: 12
        ).date)
        #expect(FeedbackNaming.folderName(startedAt: start, slug: "pricing-page", timeZone: timeZone) == "2026-10-20-1912-pricing-page")
    }

    @Test("Adds a numeric suffix when the folder name is taken")
    func collisionSuffix() {
        let taken: Set<String> = ["2026-10-20-1912-feedback", "2026-10-20-1912-feedback-2"]
        let name = FeedbackNaming.uniqueFolderName("2026-10-20-1912-feedback") { taken.contains($0) }
        #expect(name == "2026-10-20-1912-feedback-3")
        #expect(FeedbackNaming.uniqueFolderName("free") { _ in false } == "free")
    }

    @Test("Numbers capture files with three digits")
    func captureFileNames() {
        #expect(FeedbackNaming.imageFileName(index: 1) == "001.png")
        #expect(FeedbackNaming.cleanImageFileName(index: 1) == "001-clean.png")
        #expect(FeedbackNaming.imageFileName(index: 12) == "012.png")
    }
}
