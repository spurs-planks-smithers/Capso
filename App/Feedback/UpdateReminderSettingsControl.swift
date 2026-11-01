// App/Feedback/UpdateReminderSettingsControl.swift
import FeedbackKit
import SwiftUI

/// Fork: the Settings toggle for the update reminder (#203). Settings > General
/// > About shows it beside the version. The key and its default (on) come
/// from `UpdateReminder`, so the toggle and the reminder always agree.
struct UpdateReminderSettingsControl: View {
    @AppStorage(UpdateReminder.enabledKey) private var enabled = true

    var body: some View {
        Toggle("Remind me about new versions", isOn: $enabled)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}
