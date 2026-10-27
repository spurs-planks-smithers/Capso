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
        if name == .captureText, screenshotShortcutConflicts(with: name) { return false }
        return switch name {
        case .screenshotCapture, .screenshotAnnotate: current.screenshotCopy
        case .recordScreen, .recordFullscreen: current.recordingTools
        case .captureAndTranslate, .translateSelectedText, .translateTypedText: current.translationTools
        case .captureAreaAndShare: current.cloudShare
        default: current.standaloneCapture
        }
    }

    static func screenshotShortcutConflicts(with name: KeyboardShortcuts.Name) -> Bool {
        guard current.screenshotCopy, let key = KeyboardShortcuts.getShortcut(for: name) else { return false }
        return [KeyboardShortcuts.Name.screenshotCapture, .screenshotAnnotate].contains {
            KeyboardShortcuts.getShortcut(for: $0) == key
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
