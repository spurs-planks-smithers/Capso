import Foundation
import Testing
@testable import FeedbackKit

/// The relative path mode that a zip export uses (#85): every file name is
/// relative to the export folder, so the text works on any Mac.
@Suite("Relative path mode")
struct RelativePathModeTests {
    static let exportFolder = "nextshot-round-2026-10-20-1912-1-capture"
    static let relative = BundlePathMode.relative(exportFolderName: exportFolder)

    /// The text inside each pair of backticks.
    static func backtickSpans(_ text: String) -> [String] {
        text.components(separatedBy: "`").enumerated().compactMap { $0.offset.isMultiple(of: 2) ? nil : $0.element }
    }

    @Test("A relative round prompt names files with no folder")
    func relativeRoundPromptHasNoAbsolutePath() throws {
        let round = FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture()])
        let prompt = PromptBuilder.render(round, paths: Self.relative)

        #expect(prompt.contains("1. Open `manifest.md`."))
        #expect(prompt.contains(#"<feedback_bundle captures="1""#))
        #expect(!prompt.contains("path="))
        let spans = Self.backtickSpans(prompt)
        try #require(!spans.isEmpty, "the prompt has no backtick span")
        #expect(spans.allSatisfy { !$0.contains("/") }, "a span holds a path: \(spans)")
    }

    @Test("A relative capture prompt names files with no folder")
    func relativeCapturePromptNamesFilesOnly() throws {
        let prompt = PromptBuilder.renderCapture(FeedbackFixtures.pricingCapture(), paths: Self.relative)

        #expect(prompt.contains("- `1914-pricing-acme.png` (annotated"))
        #expect(prompt.contains("- `manifest.md` (the section"))
        #expect(!prompt.contains("path="))
        let spans = Self.backtickSpans(prompt)
        try #require(spans.count >= 3, "the prompt names too few files")
        #expect(spans.allSatisfy { !$0.contains("/") }, "a span holds a path: \(spans)")
    }

    @Test("A relative manifest says paths are relative and gives a Codex command with Z")
    func relativeManifestFolderLine() {
        let round = FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture()])
        let manifest = ManifestWriter.render(round, paths: Self.relative, timeZone: FeedbackFixtures.timeZone)

        #expect(manifest.contains("Folder: the folder that holds this file. Every path in this folder is relative to it."))
        #expect(manifest.contains("Run it in the target repository. If you unzipped the folder somewhere else, change Z first."))
        #expect(manifest.contains(#"Z="$HOME/Downloads/nextshot-round-2026-10-20-1912-1-capture""#))
        #expect(manifest.contains(#"codex --image "$Z/1914-pricing-acme.png" "#))
        #expect(manifest.contains(#""$(printf 'The export folder is %s.\n\n' "$Z"; cat "$Z/README.md")""#))
        #expect(!manifest.contains("/Users/"))
        #expect(!manifest.contains("prompt.md\""))
    }

    @Test("Header lines go right after the Captures line")
    func manifestHeaderLines() {
        let round = FeedbackFixtures.round(captures: [FeedbackFixtures.pricingCapture()])
        let manifest = ManifestWriter.render(
            round,
            paths: Self.relative,
            timeZone: FeedbackFixtures.timeZone,
            headerLines: ["Source rounds:", "- 2026-10-20-1912-pricing-page: its capture 2, here 1"]
        )
        #expect(manifest.contains("Captures: 1. Items: 3.\nSource rounds:\n- 2026-10-20-1912-pricing-page: its capture 2, here 1\n"))
    }

    @Test("The absolute mode gives the same text as the folderPath versions")
    func absoluteOutputUnchanged() {
        let capture = FeedbackFixtures.pricingCapture()
        let round = FeedbackFixtures.round(captures: [capture])
        let folder = "/tmp/r"
        let absolute = BundlePathMode.absolute(folderPath: folder)

        #expect(PromptBuilder.render(round, folderPath: folder) == PromptBuilder.render(round, paths: absolute))
        #expect(PromptBuilder.render(round, folderPath: folder, redo: true, refined: true)
            == PromptBuilder.render(round, paths: absolute, redo: true, refined: true))
        #expect(PromptBuilder.renderCapture(capture, folderPath: folder, refined: true)
            == PromptBuilder.renderCapture(capture, paths: absolute, refined: true))
        #expect(ManifestWriter.render(round, folderPath: folder, timeZone: FeedbackFixtures.timeZone)
            == ManifestWriter.render(round, paths: absolute, timeZone: FeedbackFixtures.timeZone))
        #expect(PromptBuilder.render(round, paths: absolute).contains(#"<feedback_bundle path="/tmp/r" captures="1""#))
    }

    @Test("The prompt and refined file names drop a .jpg extension too")
    func promptFileDropsJpg() {
        var capture = FeedbackFixtures.pricingCapture()
        capture.imageFile = "1-0636-nextshot.jpg"
        #expect(capture.promptFile == "1-0636-nextshot-prompt.md")
        #expect(PromptBuilder.refinedFile(for: capture) == "1-0636-nextshot-refined.md")
        #expect(FeedbackFixtures.pricingCapture().promptFile == "1914-pricing-acme-prompt.md")
    }
}
