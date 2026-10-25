// Packages/FeedbackKit/Sources/FeedbackKit/PromptLanes.swift
import Foundation

/// Lanes and priority (issue #69): the round plan that sorts a round's items
/// into exact edits and judgment calls, and orders them by severity. The plan
/// itself comes later. For now this type holds the two level scales that Jev
/// rates each item on. See `docs/superpowers/specs/2026-10-24-prompt-lanes-design.md`.
public struct PromptLanes: Equatable, Sendable {
    /// How serious the problem in an item's note is. The raw value is Jev's
    /// level number, nit first.
    public enum Severity: Int, CaseIterable, Sendable {
        /// A small taste preference.
        case nit = 0
        /// The change improves the look, the wording, or the layout.
        case polish
        /// Something is broken, inconsistent, or cut off, but the screen works.
        case bug
        /// The feature fails, shows wrong data, or blocks a task.
        case blocker

        public var name: String {
            switch self {
            case .nit: "nit"
            case .polish: "polish"
            case .bug: "bug"
            case .blocker: "blocker"
            }
        }
    }

    /// How much code a developer will likely change for an item. The raw
    /// value is Jev's level number, smallest first.
    public enum Size: Int, CaseIterable, Sendable {
        /// One value, word, or sentence in one place.
        case oneLine = 0
        /// A few related edits in one place.
        case oneFile
        /// Edits in a few files or places.
        case severalFiles
        /// A change across the app, the repository, or every page.
        case manyFiles

        public var name: String {
            switch self {
            case .oneLine: "one line"
            case .oneFile: "one file"
            case .severalFiles: "several files"
            case .manyFiles: "many files"
            }
        }
    }
}
