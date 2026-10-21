// Packages/FeedbackKit/Sources/FeedbackKit/PromptBuilder.swift
import Foundation

/// Renders `prompt.md`, the text that Copy Prompt puts on the clipboard.
///
/// The structure follows the bundle-format decision
/// (`docs/decisions/2026-10-20-feedback-bundle-format.md`): a bundle tag, how
/// to read, an authority rule, a work method, a verify step, a report, and a
/// context note.
public enum PromptBuilder {
    public static func render(_ session: FeedbackSession, folderPath: String) -> String {
        let missingInstructions = session.captures
            .flatMap { FeedbackItems.split($0).items }
            .filter { $0.badge.instruction == nil }
            .map(\.id)

        var lines = [
            #"<feedback_bundle path="\#(folderPath)" captures="\#(session.captures.count)" items="\#(session.itemCount)">"#,
            "Goal: Apply the review feedback in this bundle to the code in the current repository.",
            "",
            "How to read the bundle:",
            "1. Open \(folderPath)/manifest.md.",
            "2. For each capture, open its annotated PNG first, then read its section in manifest.md.",
            "3. Open the -clean.png copy only when a mark hides content.",
            "4. Badge N in image K is item K.N.",
            "5. Coordinates are pixels in that PNG, origin top-left. A box is x1 y1 x2 y2.",
            "",
            "Authority:",
            "- The written instruction wins. The image shows where the item is and how it looks now.",
            "- If the text and the image conflict, or an item has no instruction, ask before you change it.",
        ]
        if !missingInstructions.isEmpty {
            lines.append("- Items with no instruction: \(missingInstructions.joined(separator: ", ")).")
        }
        lines += [
            "",
            "Work method:",
            "1. Locate each item in the code. Search the repository for its OCR text and labels.",
            "2. Before any edit, show a table with the columns item, file, and planned change.",
            "3. Change only the listed items. Leave everything else as it is.",
            "",
            "Verify:",
            "- At the end, re-check every item against its capture, not only the last one.",
            "- Where the UI can render, take a screenshot of the same region and compare it with the capture.",
            "",
            "Report:",
            "- One line per item: done, not done, or needs input, with evidence.",
            "",
            "Context:",
            "- Read each image only when you work on its items. Each image costs up to \(ImageSizing.Limits.feedbackExport.maxTokens) tokens.",
            "</feedback_bundle>",
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}
