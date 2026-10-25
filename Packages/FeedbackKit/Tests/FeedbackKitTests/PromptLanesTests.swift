import Foundation
import Testing
@testable import FeedbackKit

/// The two level scales of the lanes feature (issue #69). Jev rates each
/// item on them, and the round plan sorts by them.
@Suite("Prompt lanes: level names")
struct PromptLanesTests {
    @Test("Each severity level has its name, from nit up to blocker")
    func severityNames() {
        #expect(PromptLanes.Severity.allCases.map(\.name) == ["nit", "polish", "bug", "blocker"])
        #expect(PromptLanes.Severity.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(PromptLanes.Severity(rawValue: 0) == .nit)
        #expect(PromptLanes.Severity(rawValue: 1) == .polish)
        #expect(PromptLanes.Severity(rawValue: 2) == .bug)
        #expect(PromptLanes.Severity(rawValue: 3) == .blocker)
        #expect(PromptLanes.Severity(rawValue: 4) == nil)
    }

    @Test("Each size level has its name, from one line up to many files")
    func sizeNames() {
        #expect(PromptLanes.Size.allCases.map(\.name) == ["one line", "one file", "several files", "many files"])
        #expect(PromptLanes.Size.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(PromptLanes.Size(rawValue: 0) == .oneLine)
        #expect(PromptLanes.Size(rawValue: 1) == .oneFile)
        #expect(PromptLanes.Size(rawValue: 2) == .severalFiles)
        #expect(PromptLanes.Size(rawValue: 3) == .manyFiles)
        #expect(PromptLanes.Size(rawValue: 4) == nil)
    }
}
