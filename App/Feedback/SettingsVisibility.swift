import FeedbackKit
import SwiftUI

typealias SettingsVisibilityFlag = FeedbackKit.SettingsVisibilityFlag

/// Visibility controls presentation only. Capability checks still apply.
@MainActor
enum SettingsVisibility {
    static func isVisible(_ flag: SettingsVisibilityFlag, instance: String? = nil) -> Bool {
        guard flag.isVisible(override: { UserDefaults.standard.string(forKey: $0) }) else { return false }
        guard let instance else { return true }
        let key = "\(flag.overrideKey).instance.\(instance)"
        return UserDefaults.standard.string(forKey: key) != "off"
    }

    /// Hide an empty section when every registered control in it is hidden.
    static func hasVisibleContent(_ flag: SettingsVisibilityFlag) -> Bool {
        guard isVisible(flag), isRelevant(flag) else { return false }
        let children = SettingsVisibilityFlag.allCases.filter { $0.parent == flag }
        return children.isEmpty || children.contains(where: hasVisibleContent)
    }

    /// Keep headings out when the launch policy removes every child.
    private static func isRelevant(_ flag: SettingsVisibilityFlag) -> Bool {
        switch flag {
        case .generalAutomation: Capabilities.current.automationURLs
        case .generalSound, .generalScreenshotHistory, .generalStartupShowCaptureMenu,
             .screenshotsAfterCapture, .screenshotsBeautify, .screenshotsSelfTimer,
             .screenshotsCaptureCaptureWindowShadow, .shortcutsCustomizable,
             .shortcutsSystem, .shortcutsContextual: Capabilities.current.standaloneCapture
        case .generalUpdates: Capabilities.current.automaticUpdates
        case .permissionsPrivacySecurityAccessibility, .ocrTranslation, .shortcutsTranslation:
            Capabilities.current.translationTools
        case .permissionsPrivacySecurityInputMonitoring, .permissionsPrivacySecurityCamera,
             .permissionsPrivacySecurityMicrophone, .shortcutsRecording, .exportQualityExportQuality:
            Capabilities.current.recordingTools
        case .shortcutsClipboardPinsCaptureAreaAndShare: Capabilities.current.cloudShare
        case .screenshotsCaptureClipboardFormat: !Capabilities.current.standaloneCapture
        default: true
        }
    }

}

extension View {
    @MainActor
    @ViewBuilder
    func settingsVisibility(_ flag: SettingsVisibilityFlag) -> some View {
        if SettingsVisibility.isVisible(flag) { self }
    }
}

/// Help opens with a hover or click. The button also supports keyboard focus.
struct SettingsInfoButton: View {
    let text: String
    @State private var showingHelp = false

    var body: some View {
        Button { showingHelp = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Learn about this permission")
        .help(text)
        .onHover { showingHelp = $0 }
        .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
            Text(verbatim: text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(width: 330, alignment: .leading)
        }
    }
}
