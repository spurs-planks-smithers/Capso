// App/Feedback/FeedbackShortcuts.swift
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Fork: capture an area into the active feedback round. Starts a
    /// round named "feedback" when none is active. Not in `allCapso`. The
    /// Nextshot section of Settings > Shortcuts lists it
    /// (`FeedbackShortcutSettingsSection`), and so does the Nshot menu.
    static let feedbackCapture = Self("feedbackCapture", default: .init(.f, modifiers: [.option, .shift]))

    static let screenshotCapture = Self("screenshotCapture", default: .init(.four, modifiers: [.option, .shift]))
    static let screenshotAnnotate = Self("screenshotAnnotate", default: .init(.a, modifiers: [.option, .shift]))

    /// Fork: the round keys (Drew, 2026-10-24). Each runs the same path as
    /// its row in the Nshot menu.
    static let feedbackCopyLastCapture = Self("feedbackCopyLastCapture", default: .init(.c, modifiers: [.option, .shift]))
    static let feedbackCopyPromptAndEndRound = Self("feedbackCopyPromptAndEndRound", default: .init(.r, modifiers: [.option, .shift]))
    static let feedbackOpenRoundFolder = Self("feedbackOpenRoundFolder", default: .init(.o, modifiers: [.option, .shift]))
    static let feedbackEndRound = Self("feedbackEndRound", default: .init(.e, modifiers: [.option, .shift]))

    /// The round keys work only while a round is active
    /// (`FeedbackController.updateRoundShortcuts()`). An Option+Shift+letter
    /// key types a character in other apps, so a key that is always on would
    /// block that character everywhere.
    static let feedbackRoundKeys: [Self] = [
        .feedbackCopyLastCapture, .feedbackCopyPromptAndEndRound, .feedbackOpenRoundFolder, .feedbackEndRound,
    ]

    /// The fork's five keys: the start key and the round keys.
    @MainActor static var nextshotKeys: [Self] {
        [.feedbackCapture] + feedbackRoundKeys + (Capabilities.current.screenshotCopy ? [.screenshotCapture, .screenshotAnnotate] : [])
    }
}

/// Fork: keeps each Nextshot key apart from every other action's key (#24).
/// The library removes a hotkey by its key combination, so a round key that
/// shared a combination with another action would turn that action off
/// between rounds.
@MainActor
enum FeedbackShortcutGuard {
    /// Each Nextshot key as last accepted. The library stores a new key
    /// before it calls back, so this is the only copy of the old key. One
    /// copy serves Settings and the start key panel, so a change in one never
    /// leaves the other with an old value. Only the fork's recorders change
    /// these keys, and each goes through `check`.
    private static var accepted: [KeyboardShortcuts.Name: KeyboardShortcuts.Shortcut] = [:]

    /// Call once at launch, before any recorder can change a key.
    static func rememberCurrentKeys() {
        for name in KeyboardShortcuts.Name.allCapso + KeyboardShortcuts.Name.nextshotKeys {
            accepted[name] = KeyboardShortcuts.getShortcut(for: name)
        }
    }

    static func isAvailable(_ name: KeyboardShortcuts.Name) -> Bool {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return true }
        let others = (KeyboardShortcuts.Name.allCapso.filter { Capabilities.allowsShortcut($0) } + KeyboardShortcuts.Name.nextshotKeys).filter { $0 != name }
        return !others.contains { KeyboardShortcuts.getShortcut(for: $0) == shortcut }
    }

    /// Call from a recorder's `onChange`. A key that another action uses is
    /// set back to the last accepted key, with a beep. Returns the reason to
    /// show, or nil when the new key stays. `label` names the key in the
    /// reason.
    static func check(_ shortcut: KeyboardShortcuts.Shortcut?, for name: KeyboardShortcuts.Name, label: String) -> String? {
        defer {
            accepted[name] = KeyboardShortcuts.getShortcut(for: name)
            FeedbackController.shared.updateRoundShortcuts()
            FeedbackController.shared.updateScreenshotShortcuts()
        }
        let others = (KeyboardShortcuts.Name.allCapso.filter { Capabilities.allowsShortcut($0) } + KeyboardShortcuts.Name.nextshotKeys).filter { $0 != name }
        guard let shortcut, others.contains(where: { KeyboardShortcuts.getShortcut(for: $0) == shortcut }) else {
            return nil
        }
        let previous = accepted[name]
        KeyboardShortcuts.setShortcut(previous, for: name)
        NSSound.beep()
        return "\(shortcut) is in use by another action. \(label) stays \(previous?.description ?? "off")."
    }
}
