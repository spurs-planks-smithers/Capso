import Foundation
import Testing
@testable import FeedbackKit

/// The data guard (#70) writes `<stem>-covered.png` beside a capture: the same
/// badges and marks, over a solid box on each place it found private data. A
/// copied prompt must name that copy, because the annotated PNG still shows
/// the data the reviewer was told was covered (#81).
///
/// Both flags that can reach the guard (`dataGuard`, `cropsAnchors`) are
/// dev-only, and `FlagResolver.resolve` reads every dev-only flag as off in a
/// release build, so a release bundle never holds a covered copy. These tests
/// still run against a bundle built by hand, because the naming rule is the
/// guard's contract, not its caller's.
@Suite("Covered copy naming")
struct CoveredCopyTests {
    let capture = FeedbackFixtures.pricingCapture(index: 2)
    var round: FeedbackRound { FeedbackFixtures.round(captures: [capture]) }

    /// A bundle folder that holds a covered copy when `covered` is true.
    private func bundle(covered: Bool) throws -> String {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoveredCopyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if covered {
            let file = folder.appendingPathComponent(PromptBuilder.coveredFile(for: capture))
            try Data([0]).write(to: file)
        }
        return folder.path
    }

    @Test("The covered file name follows the capture's file stem")
    func coveredFileName() {
        #expect(PromptBuilder.coveredFile(for: capture) == "1914-pricing-acme-covered.png")
        var other = capture
        other.imageFile = "1028-claude.png"
        #expect(PromptBuilder.coveredFile(for: other) == "1028-claude-covered.png")
    }

    @Test("The capture prompt names the covered copy instead of the annotated PNG")
    func capturePromptNamesCovered() throws {
        let folder = try bundle(covered: true)
        let text = PromptBuilder.renderCapture(capture, folderPath: folder)
        #expect(text.contains("- `\(folder)/1914-pricing-acme-covered.png` (annotated: the numbered badges and marks, over a solid box"))
        #expect(!text.contains("- `\(folder)/1914-pricing-acme.png`"))
        // The plain line the agent used to get, which sent it to the image
        // that still shows the data the guard covered.
        #expect(!text.contains("- `\(folder)/1914-pricing-acme.png` (annotated: the numbered badges and marks)"))
        // The clean copy is still named, so the agent can still reach it.
        #expect(text.contains("-clean.png"))
    }

    @Test("The linked capture prompt names the covered copy too")
    func linkedCapturePromptNamesCovered() throws {
        let folder = try bundle(covered: true)
        let text = PromptBuilder.renderCapture(capture, folderPath: folder, linkedPlan: true)
        #expect(text.contains("1914-pricing-acme-covered.png"))
        #expect(!text.contains("- `\(folder)/1914-pricing-acme.png` ("))
    }

    @Test("The selection prompt names the covered copy too")
    func selectionPromptNamesCovered() throws {
        let folder = try bundle(covered: true)
        let entry = FeedbackSelectionEntry(round: round, capture: capture, folderPath: folder)
        let text = PromptBuilder.renderSelection([entry])
        #expect(text.contains("- `\(folder)/1914-pricing-acme-covered.png` (annotated: the numbered badges and marks, over a solid box"))
        #expect(!text.contains("- `\(folder)/1914-pricing-acme.png` (annotated:"))
        let linked = PromptBuilder.renderSelection([entry], linkedPlan: true)
        #expect(linked.contains("1914-pricing-acme-covered.png"))
    }

    @Test("The manifest names the covered copy in its Images list, its section, and its table")
    func manifestNamesCovered() throws {
        let folder = try bundle(covered: true)
        let text = ManifestWriter.render(round, folderPath: folder, timeZone: FeedbackFixtures.timeZone)
        #expect(text.contains("- `\(folder)/1914-pricing-acme-covered.png`"))
        #expect(!text.contains("- `\(folder)/1914-pricing-acme.png`"))
        #expect(text.contains("Image: 1914-pricing-acme-covered.png (annotated), 1914-pricing-acme-clean.png (no marks)"))
        #expect(text.contains("| Item | Where in 1914-pricing-acme-covered.png (px, x1 y1 x2 y2) |"))
    }

    @Test("The round prompts point at the covered copy through the manifest")
    func roundPromptMentionsCovered() throws {
        let folder = try bundle(covered: true)
        let steps = "A capture with a covered copy lists that copy under Images in manifest.md. Open it instead of the annotated PNG: it holds the same badges and marks, over a solid box on each place private data was covered."
        #expect(PromptBuilder.render(round, folderPath: folder).contains(steps))
        #expect(PromptBuilder.render(round, folderPath: folder, linkedPlan: true).contains(steps))
    }

    @Test("Without a covered copy every prompt is byte-identical to today's output")
    func noCoveredCopyIsUnchanged() throws {
        let folder = try bundle(covered: false)
        let entry = FeedbackSelectionEntry(round: round, capture: capture, folderPath: folder)

        let texts = [
            PromptBuilder.render(round, folderPath: folder),
            PromptBuilder.render(round, folderPath: folder, linkedPlan: true),
            PromptBuilder.renderCapture(capture, folderPath: folder),
            PromptBuilder.renderCapture(capture, folderPath: folder, linkedPlan: true),
            PromptBuilder.renderSelection([entry]),
            PromptBuilder.renderSelection([entry], linkedPlan: true),
            ManifestWriter.render(round, folderPath: folder, timeZone: FeedbackFixtures.timeZone),
        ]
        for text in texts {
            #expect(!text.contains("covered"))
        }
        #expect(PromptBuilder.renderCapture(capture, folderPath: folder).contains("- `\(folder)/1914-pricing-acme.png` (annotated: the numbered badges and marks)"))
        #expect(PromptBuilder.renderSelection([entry]).contains("- `\(folder)/1914-pricing-acme.png` (annotated: the numbered badges and marks)"))
        #expect(ManifestWriter.render(round, folderPath: folder, timeZone: FeedbackFixtures.timeZone).contains("- `\(folder)/1914-pricing-acme.png`"))
    }

    @Test("A cover is named even when a mark covers the item it was cut from")
    func coverIsNamedPerCapture() throws {
        let folder = try bundle(covered: true)
        var uncovered = FeedbackFixtures.pricingCapture(index: 3)
        uncovered.marks = []
        let mixed = FeedbackFixtures.round(captures: [capture, uncovered])
        let text = ManifestWriter.render(mixed, folderPath: folder, timeZone: FeedbackFixtures.timeZone)
        // Capture 2 has a covered copy; capture 3 does not, so it keeps its own name.
        #expect(text.contains("- `\(folder)/1914-pricing-acme-covered.png`"))
        #expect(text.contains("- `\(folder)/1915-pricing-acme.png`"))
    }

    @Test("A zip export never names a covered copy: it holds no Jev file")
    func relativeModeNeverNamesCovered() throws {
        let folder = try bundle(covered: true)
        let paths = BundlePathMode.relative(exportFolderName: "nextshot-round-x")
        // A zip renders the round and capture prompts and the manifest in
        // relative mode. It never renders a selection prompt, which always
        // takes its paths from the folders it read.
        let texts = [
            PromptBuilder.render(round, paths: paths),
            PromptBuilder.renderCapture(capture, paths: paths),
            PromptBuilder.renderCapture(capture, paths: paths, linkedPlan: true),
            ManifestWriter.render(round, paths: paths, timeZone: FeedbackFixtures.timeZone),
        ]
        for text in texts {
            #expect(!text.contains("covered"))
        }
        #expect(PromptBuilder.renderCapture(capture, paths: paths).contains("- `1914-pricing-acme.png` (annotated: the numbered badges and marks)"))
        #expect(ManifestWriter.render(round, paths: paths, timeZone: FeedbackFixtures.timeZone).contains("- `1914-pricing-acme.png`"))
    }
}
