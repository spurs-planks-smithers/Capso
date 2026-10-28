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

    private static let screenRecordingExplanation = """
    macOS uses Screen Recording access for still screenshots too. It lets Nextshot read pixels across your screen, including other apps. The permission is broader than the area you select.

    When you start a capture, Nextshot freezes the screen so you can select an area. Anything visible may contain private information. Check the image before sharing.

    Captures stay on your Mac by default. Sharing, support uploads, and optional AI features have separate controls. This permission alone does not send images.

    Revoke access in System Settings > Privacy & Security > Screen & System Audio Recording. New screen captures then stop working. Saved captures remain.
    """

    private func permissionRow(
        visibility: SettingsVisibilityFlag,
        kind: PermissionKind,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isGranted: Bool,
        showDivider: Bool = false,
        explanation: String? = nil
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
