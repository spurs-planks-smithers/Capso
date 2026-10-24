// App/Feedback/FeedbackShortcuts.swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Fork: capture an area into the active feedback session. Starts a
    /// session named "feedback" when none is active. Not in `allCapso`. The
    /// Nextshot section of Settings > Shortcuts lists it
    /// (`FeedbackShortcutSettingsSection`), and so does the Nshot menu.
    static let feedbackCapture = Self("feedbackCapture", default: .init(.f, modifiers: [.option, .shift]))

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
}
