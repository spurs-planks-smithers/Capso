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

    /// Why the last key was refused (#24), shown under the card.
    @State private var refusal: String?

    var body: some View {
        SettingGroup(visibility: .shortcutsCore, title: "Round Controls") {
            SettingCard {
                row("Start Round or Capture Area", visibility: .shortcutsCoreFeedbackCapture, name: .feedbackCapture)
                row("Copy Last Capture Prompt", visibility: .shortcutsCoreFeedbackCopyLastCapture, name: .feedbackCopyLastCapture, roundOnly: true)
                row("Copy Prompt and End Round", visibility: .shortcutsCoreFeedbackCopyPromptAndEndRound, name: .feedbackCopyPromptAndEndRound, roundOnly: true)
                row("Open Round Folder", visibility: .shortcutsCoreFeedbackOpenRoundFolder, name: .feedbackOpenRoundFolder, roundOnly: true)
                row("End Round", visibility: .shortcutsCoreFeedbackEndRound, name: .feedbackEndRound, roundOnly: true)
            }
            if let refusal {
                Text(verbatim: refusal)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.leading, 2)
            }
        }
        // An old reason does not show again when the tab opens.
        .onAppear { refusal = nil }
    }

    /// The round keys work only while a round is active, and the sublabel
    /// says so. `FeedbackShortcutGuard` refuses a key that another action
    /// uses, and it asks the controller to remove a changed round key again
    /// when no round is active.
    private func row(_ label: String, visibility: SettingsVisibilityFlag, name: KeyboardShortcuts.Name, roundOnly: Bool = false) -> some View {
        SettingRow(
            visibility: visibility,
            label: LocalizedStringKey(label),
            sublabel: roundOnly ? LocalizedStringKey(Self.roundOnlyNote) : nil,
            showDivider: name != .feedbackCapture
        ) {
            KeyboardShortcuts.Recorder(for: name) { shortcut in
                refusal = FeedbackShortcutGuard.check(shortcut, for: name, label: label)
            }
            .controlSize(.small)
        }
    }
}
