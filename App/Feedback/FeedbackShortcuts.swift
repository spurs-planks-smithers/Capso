// App/Feedback/FeedbackShortcuts.swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Fork: capture an area into the active feedback session. Starts a
    /// session named "feedback" when none is active. Not in `allCapso`, so the
    /// Shortcuts settings tab does not list it; the feedback status menu does.
    static let feedbackCapture = Self("feedbackCapture", default: .init(.f, modifiers: [.option, .shift]))
}
