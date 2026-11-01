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
/// text (OCR text, window titles) never reaches the model. The instruction is
/// `SummaryNames.instruction`. Only `SystemLanguageModel.default` runs here:
/// never `PrivateCloudComputeLanguageModel`, which calls a server.
enum FeedbackSummaryModel {
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

    /// Why the model can or cannot run now, as a short word for the local use
    /// counter (`SummaryUseCounter`). It holds no text from the user.
    static var stateName: String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return model.supportsLocale() ? "available" : "unsupportedLocale"
            case .unavailable(.deviceNotEligible):
                return "deviceNotEligible"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "appleIntelligenceNotEnabled"
            case .unavailable(.modelNotReady):
                return "modelNotReady"
            case .unavailable:
                return "otherReason"
            }
        }
        #endif
        return "osTooOld"
    }

    /// The model's name for the input, cleaned (`SummaryNames.cleaned`). Nil
    /// when the model is unavailable or its reply cannot pass for a name (a
    /// refusal, an empty reply). It throws what the model throws, for the
    /// caller to log. Greedy sampling gives the same name for the same input.
    static func name(forInput input: String) async throws -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), isAvailable else { return nil }
        let session = LanguageModelSession(model: .default, instructions: SummaryNames.instruction)
        // `sampling:` is deprecated in the macOS 27 SDK (`samplingMode:`), but
        // it is the only spelling on macOS 26 and on older SDKs. The warning stays.
        let reply = try await session.respond(to: input, options: GenerationOptions(sampling: .greedy))
        return SummaryNames.cleaned(reply.content)
        #else
        return nil
        #endif
    }
}
