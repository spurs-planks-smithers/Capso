import FeedbackKit
import Foundation
import KeyboardShortcuts
import SharedKit

/// One policy for Settings, commands, and startup work. A flag change takes
/// effect after a normal quit and reopen, never halfway through a capture.
@MainActor
enum Capabilities {
    static let current = AppCapabilities(state: Flags.state)

    static func allowsShortcut(_ name: KeyboardShortcuts.Name) -> Bool {
        switch name {
        case .recordScreen, .recordFullscreen: current.recordingTools
        case .captureAndTranslate, .translateSelectedText, .translateTypedText: current.translationTools
        case .captureAreaAndShare: current.cloudShare
        default: current.standaloneCapture
        }
    }

    static func allowsAutomation(_ action: AutomationURLAction) -> Bool {
        guard current.automationURLs else { return false }
        switch action {
        case .recordArea, .recordFullscreen: return current.recordingTools
        case .captureAndTranslate, .translateSelectedText, .translateTypedText: return current.translationTools
        case .captureAreaAndShare: return current.cloudShare
        default: return true
        }
    }
}
