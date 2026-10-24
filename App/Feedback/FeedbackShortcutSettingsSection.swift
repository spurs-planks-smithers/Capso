// App/Feedback/FeedbackShortcutSettingsSection.swift
import KeyboardShortcuts
import SwiftUI

/// Fork: the Nextshot keys in Settings > Shortcuts (Drew, 2026-10-24).
/// Upstream's `ShortcutSettingsView` adds this view at one hook point
/// (`docs/FORK_NOTES.md`).
///
/// Labels are plain strings, so the build adds nothing to upstream's string
/// catalog.
struct FeedbackShortcutSettingsSection: View {
    private static let roundOnlyNote = "While a round is active"

    var body: some View {
        SettingGroup(title: LocalizedStringKey(ForkBranding.name)) {
            SettingCard {
                row("Start Round or Capture Area", name: .feedbackCapture)
                row("Copy Last Capture Prompt", name: .feedbackCopyLastCapture, roundOnly: true)
                row("Copy Prompt and End Round", name: .feedbackCopyPromptAndEndRound, roundOnly: true)
                row("Open Round Folder", name: .feedbackOpenRoundFolder, roundOnly: true)
                row("End Round", name: .feedbackEndRound, roundOnly: true)
            }
        }
    }

    /// The round keys work only while a round is active, and the sublabel
    /// says so. The library registers a changed key at once, so a change
    /// asks the controller to remove it again when no round is active.
    private func row(_ label: String, name: KeyboardShortcuts.Name, roundOnly: Bool = false) -> some View {
        SettingRow(
            label: LocalizedStringKey(label),
            sublabel: roundOnly ? LocalizedStringKey(Self.roundOnlyNote) : nil,
            showDivider: name != .feedbackCapture
        ) {
            KeyboardShortcuts.Recorder(for: name) { _ in
                FeedbackController.shared.updateRoundShortcuts()
            }
            .controlSize(.small)
        }
    }
}
