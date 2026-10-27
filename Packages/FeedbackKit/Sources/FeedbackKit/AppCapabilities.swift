import Foundation

/// Available optional tools for one app launch. Preferences remain stored
/// when a capability is off. Shared feedback-round services stay available.
public struct AppCapabilities: Sendable, Equatable {
    public let standaloneCapture: Bool
    public let recordingTools: Bool
    public let translationTools: Bool
    public let cloudShare: Bool
    public let automationURLs: Bool
    public let automaticUpdates: Bool

    public var recordingCloudShare: Bool { recordingTools && cloudShare }

    public init(state: (FeatureFlag) -> FlagState) {
        let standalone = state(.standaloneCapture) == .on
        standaloneCapture = standalone
        recordingTools = standalone && state(.recordingTools) == .on
        translationTools = standalone && state(.translationTools) == .on
        cloudShare = standalone && state(.cloudShare) == .on
        automationURLs = standalone && state(.automationURLs) == .on
        automaticUpdates = state(.automaticUpdates) == .on
    }
}
