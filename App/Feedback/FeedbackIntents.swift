// App/Feedback/FeedbackIntents.swift
import AppIntents
import FeedbackKit

/// Fork: Shortcuts actions for feedback rounds. They run in-process and
/// make no network calls.

struct StartFeedbackRoundIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Feedback Round"
    static let description = IntentDescription("Starts a Nextshot feedback round. Captures go into a new folder under ~/Library/Application Support/Nextshot.")

    @Parameter(title: "Name")
    var name: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let round = try await FeedbackController.shared.startRound(name: name)
            return .result(value: round.folderName)
        } catch FeedbackRoundStore.StoreError.roundAlreadyActive {
            throw FeedbackIntentError.roundAlreadyActive
        }
    }
}

struct CaptureFeedbackIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Feedback"
    static let description = IntentDescription("Captures an area into the active feedback round. Saving the first capture starts a round when none is active.")
    // `openAppWhenRun` is deprecated only from macOS 26. The app targets macOS 15.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        FeedbackController.shared.capture()
        return .result()
    }
}

struct CopyFeedbackPromptIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Feedback Prompt"
    static let description = IntentDescription("Copies the active round's prompt to the clipboard, ends the round, and returns the prompt. Resume in the Nshot menu's Recent list reopens the round.")

    /// The same path as Copy Prompt and End Round in the Nshot menu.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let prompt = try await FeedbackController.shared.copyPromptAndEndRound()
            return .result(value: prompt)
        } catch FeedbackRoundStore.StoreError.noActiveRound {
            throw FeedbackIntentError.noActiveRound
        }
    }
}

struct EndFeedbackRoundIntent: AppIntent {
    static let title: LocalizedStringResource = "End Feedback Round"
    static let description = IntentDescription("Ends the active feedback round. The folder stays in ~/Library/Application Support/Nextshot.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let round = try await FeedbackController.shared.endRound()
            return .result(value: round.folderName)
        } catch FeedbackRoundStore.StoreError.noActiveRound {
            throw FeedbackIntentError.noActiveRound
        }
    }
}

// MARK: - Actions saved before the rename to round (2026-10-24)

// An App Intent's identifier comes from its type name. A Shortcut that Drew
// or a colleague saved before the rename still names the old types. These
// two keep that name, forward to the round actions, and stay out of the
// Shortcuts action list (`isDiscoverable`). Their titles use the new words,
// so a saved Shortcut reads like the new action. They are not in
// `FeedbackAppShortcuts`.

struct StartFeedbackSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Feedback Round"
    static let isDiscoverable = false

    @Parameter(title: "Name")
    var name: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var forwarded = StartFeedbackRoundIntent()
        forwarded.name = name
        return try await forwarded.perform()
    }
}

struct EndFeedbackSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "End Feedback Round"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        try await EndFeedbackRoundIntent().perform()
    }
}

enum FeedbackIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noActiveRound
    case roundAlreadyActive

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noActiveRound: "No feedback round is active."
        case .roundAlreadyActive: "A feedback round is already active. End it first."
        }
    }
}

struct FeedbackAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFeedbackRoundIntent(),
            phrases: ["Start a feedback round in \(.applicationName)"],
            shortTitle: "Start Feedback Round",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: CaptureFeedbackIntent(),
            phrases: ["Capture feedback with \(.applicationName)"],
            shortTitle: "Capture Feedback",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: CopyFeedbackPromptIntent(),
            phrases: ["Copy the feedback prompt from \(.applicationName)"],
            shortTitle: "Copy Feedback Prompt",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: EndFeedbackRoundIntent(),
            phrases: ["End the feedback round in \(.applicationName)"],
            shortTitle: "End Feedback Round",
            systemImageName: "stop.circle"
        )
    }
}
