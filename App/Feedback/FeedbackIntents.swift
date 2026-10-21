// App/Feedback/FeedbackIntents.swift
import AppIntents
import FeedbackKit

/// Fork: Shortcuts actions for feedback sessions. They run in-process and
/// make no network calls.

struct StartFeedbackSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Feedback Session"
    static let description = IntentDescription("Starts a Capso feedback session. Captures go into a new folder under ~/Library/Application Support/CapsoFeedback.")

    @Parameter(title: "Name")
    var name: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let session = try await FeedbackController.shared.startSession(name: name)
            return .result(value: session.folderName)
        } catch FeedbackSessionStore.StoreError.sessionAlreadyActive {
            throw FeedbackIntentError.sessionAlreadyActive
        }
    }
}

struct CaptureFeedbackIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Feedback"
    static let description = IntentDescription("Captures an area into the active feedback session. Saving the first capture starts a session when none is active.")
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
    static let description = IntentDescription("Copies the active feedback session's prompt to the clipboard and returns it.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let prompt = await FeedbackController.shared.copyPrompt() else {
            throw FeedbackIntentError.noActiveSession
        }
        return .result(value: prompt)
    }
}

struct EndFeedbackSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "End Feedback Session"
    static let description = IntentDescription("Ends the active feedback session. The folder stays in ~/Library/Application Support/CapsoFeedback.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        do {
            let session = try await FeedbackController.shared.endSession()
            return .result(value: session.folderName)
        } catch FeedbackSessionStore.StoreError.noActiveSession {
            throw FeedbackIntentError.noActiveSession
        }
    }
}

enum FeedbackIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noActiveSession
    case sessionAlreadyActive

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noActiveSession: "No feedback session is active."
        case .sessionAlreadyActive: "A feedback session is already active. End it first."
        }
    }
}

struct FeedbackAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFeedbackSessionIntent(),
            phrases: ["Start a feedback session in \(.applicationName)"],
            shortTitle: "Start Feedback Session",
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
            intent: EndFeedbackSessionIntent(),
            phrases: ["End the feedback session in \(.applicationName)"],
            shortTitle: "End Feedback Session",
            systemImageName: "stop.circle"
        )
    }
}
