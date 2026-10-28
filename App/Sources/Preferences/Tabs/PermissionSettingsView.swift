import SwiftUI
import SharedKit

struct PermissionSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Permissions")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button(action: refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .settingsVisibility(.permissionsRefresh)
            }

            SettingGroup(visibility: .permissionsPrivacySecurity, title: "Privacy & Security") {
                SettingCard {
                    permissionRow(
                        visibility: .permissionsPrivacySecurityScreenRecording,
                        kind: .screenRecording,
                        title: "Screen Recording",
                        subtitle: "Required for screenshots and recording",
                        isGranted: viewModel.screenRecordingGranted,
                        explanation: Self.screenRecordingExplanation
                    )
                    if Capabilities.current.translationTools {
                        permissionRow(
                            visibility: .permissionsPrivacySecurityAccessibility,
                            kind: .accessibility,
                            title: "Accessibility",
                            subtitle: "Required for selected text translation",
                            isGranted: viewModel.accessibilityGranted,
                            showDivider: true
                        )
                    }
                    if Capabilities.current.recordingTools {
                        permissionRow(
                            visibility: .permissionsPrivacySecurityInputMonitoring,
                            kind: .inputMonitoring,
                            title: "Input Monitoring",
                            subtitle: "Required to show key presses while recording",
                            isGranted: viewModel.inputMonitoringGranted,
                            showDivider: true
                        )
                    }
                    if Capabilities.current.recordingTools {
                        permissionRow(
                            visibility: .permissionsPrivacySecurityCamera,
                            kind: .camera,
                            title: "Camera",
                            subtitle: "Required for camera overlay",
                            isGranted: viewModel.cameraGranted,
                            showDivider: true
                        )
                    }
                    if Capabilities.current.recordingTools {
                        permissionRow(
                            visibility: .permissionsPrivacySecurityMicrophone,
                            kind: .microphone,
                            title: "Microphone",
                            subtitle: "Required for microphone recording",
                            isGranted: viewModel.microphoneGranted,
                            showDivider: true
                        )
                    }
                }
            }
        }
        .task {
            await viewModel.refreshPermissions()
        }
    }

    private static let screenRecordingExplanation = SettingsHelpContent(points: [
        SettingsHelpPoint(
            icon: "SettingsHelpScreen",
            title: "For screenshots, too",
            detail: "macOS grants access to the whole screen, including other apps."
        ),
        SettingsHelpPoint(
            icon: "SettingsHelpLocal",
            title: "Local by default",
            detail: "Captures save to your Mac. You choose what to share."
        ),
        SettingsHelpPoint(
            icon: "SettingsHelpControls",
            title: "You're in control",
            detail: "Turn access off in System Settings. Saved captures stay on your Mac."
        ),
    ])

    private func permissionRow(
        visibility: SettingsVisibilityFlag,
        kind: PermissionKind,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isGranted: Bool,
        showDivider: Bool = false,
        explanation: SettingsHelpContent? = nil
    ) -> some View {
        SettingRow(visibility: visibility, label: title, sublabel: subtitle, showDivider: showDivider, explanation: explanation) {
            HStack(spacing: 10) {
                statusBadge(isGranted)
                Button(action: { request(kind) }) {
                    Label(actionTitle(for: kind, isGranted: isGranted), systemImage: actionIcon(for: kind, isGranted: isGranted))
                }
                .controlSize(.small)
                Button(action: { viewModel.openPermissionSettings(kind) }) {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Open System Settings")
            }
        }
    }

    private func statusBadge(_ isGranted: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isGranted ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(isGranted ? "Allowed" : "Needs Access")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isGranted ? .secondary : .primary)
        }
        .frame(width: 96, alignment: .leading)
    }

    private func actionTitle(for kind: PermissionKind, isGranted: Bool) -> LocalizedStringKey {
        if isGranted { return "Open" }
        switch kind {
        case .camera, .microphone:
            return "Request"
        case .screenRecording, .accessibility, .inputMonitoring:
            return "Open"
        }
    }

    private func actionIcon(for kind: PermissionKind, isGranted: Bool) -> String {
        if isGranted { return "gearshape" }
        switch kind {
        case .camera, .microphone:
            return "hand.tap"
        case .screenRecording, .accessibility, .inputMonitoring:
            return "gearshape"
        }
    }

    private func request(_ kind: PermissionKind) {
        Task { await viewModel.requestPermission(kind) }
    }

    private func refresh() {
        Task { await viewModel.refreshPermissions() }
    }
}
