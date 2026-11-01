// App/Feedback/FeedbackSummaryModel.swift
import FeedbackKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Fork: the one call to Apple's on-device model, for the session summary name
/// (#200, Drew, 2026-10-31). The model runs on this Mac and sends nothing out:
/// there is no network code here, and `NetworkSourceScanTests` covers the file.
/// It needs macOS 26 or newer and Apple Intelligence. On any other Mac it is
/// unavailable, and the prompt keeps the name that `RoundTitle` cuts.
///
/// The input is `SummaryNames.input(of:)`: the reviewer's words only. Screen
/// text (OCR text, window titles) never reaches the model.
enum FeedbackSummaryModel {
    /// Tuned on 47 local rounds (2026-10-31). Words such as "screen" and "app"
    /// in the instruction came back as generic names ("Screen control"), so the
    /// instruction bans them. A vague note set gets NONE, which
    /// `SummaryNames.cleaned` turns into no name, so the prompt keeps the
    /// reviewer's own words. Change it only with a new `SummaryNames.revision`,
    /// so names written under the old text are not found.
    static let instructions = """
    You name a work session from a reviewer's notes. \
    The notes arrive in groups, one group per image. \
    Name the subject of all the work in one noun phrase of two to six words. \
    Keep the specific names the notes use for the page, the control, the label, or the feature, \
    and put the most important one first. \
    Never use the generic words app, screen, screenshot, image, review, feedback, notes, changes, update, or issues. \
    When the groups cover different areas, name the two main areas. \
    When the notes are too short or too vague to name a subject, reply NONE. \
    Reply with the name only. No quotes, no period, no label.
    """

    /// True when this Mac can run the model now: macOS 26 or newer, Apple
    /// Intelligence on, the model ready, and the system language supported.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let model = SystemLanguageModel.default
            return model.availability == .available && model.supportsLocale()
        }
        #endif
        return false
    }

    /// The model's name for the input, cleaned (`SummaryNames.cleaned`). Nil
    /// when the model is unavailable or its reply cannot pass for a name (a
    /// refusal, an empty reply). It throws what the model throws, for the
    /// caller to log. Greedy sampling gives the same name for the same input.
    static func name(forInput input: String) async throws -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), isAvailable else { return nil }
        let session = LanguageModelSession(model: .default, instructions: instructions)
        let reply = try await session.respond(to: input, options: GenerationOptions(sampling: .greedy))
        return SummaryNames.cleaned(reply.content)
        #else
        return nil
        #endif
    }
}
