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

    /// The key each row holds, so a refused key can be set back (#24).
    @State private var accepted = Self.currentShortcuts()
    /// Why the last key was refused, shown under the card.
    @State private var refusal: String?

    var body: some View {
        SettingGroup(title: LocalizedStringKey(ForkBranding.name)) {
            SettingCard {
                row("Start Round or Capture Area", name: .feedbackCapture)
                row("Copy Last Capture Prompt", name: .feedbackCopyLastCapture, roundOnly: true)
                row("Copy Prompt and End Round", name: .feedbackCopyPromptAndEndRound, roundOnly: true)
                row("Open Round Folder", name: .feedbackOpenRoundFolder, roundOnly: true)
                row("End Round", name: .feedbackEndRound, roundOnly: true)
            }
            if let refusal {
                Text(verbatim: refusal)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.leading, 2)
            }
        }
        // The start key panel can change a key while this tab is closed.
        .onAppear { accepted = Self.currentShortcuts() }
    }

    /// The round keys work only while a round is active, and the sublabel
    /// says so. `FeedbackShortcutGuard` refuses a key that another action
    /// uses, and it asks the controller to remove a changed round key again
    /// when no round is active.
    private func row(_ label: String, name: KeyboardShortcuts.Name, roundOnly: Bool = false) -> some View {
        SettingRow(
            label: LocalizedStringKey(label),
            sublabel: roundOnly ? LocalizedStringKey(Self.roundOnlyNote) : nil,
            showDivider: name != .feedbackCapture
        ) {
            KeyboardShortcuts.Recorder(for: name) { shortcut in
                refusal = FeedbackShortcutGuard.check(shortcut, for: name, previous: accepted[name], label: label)
                accepted[name] = KeyboardShortcuts.getShortcut(for: name)
            }
            .controlSize(.small)
        }
    }

    private static func currentShortcuts() -> [KeyboardShortcuts.Name: KeyboardShortcuts.Shortcut] {
        var shortcuts: [KeyboardShortcuts.Name: KeyboardShortcuts.Shortcut] = [:]
        for name in KeyboardShortcuts.Name.nextshotKeys {
            shortcuts[name] = KeyboardShortcuts.getShortcut(for: name)
        }
        return shortcuts
    }
}
