// App/Sources/Preferences/Tabs/GeneralSettingsView.swift
import SwiftUI
import LaunchAtLogin
import AppKit
import KeyboardShortcuts
import SharedKit

struct GeneralSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    let updateManager: UpdateManager?
    @State private var showHideMenuBarConfirmation = false
    @State private var showingAutomationURLs = false

    private var menuBarToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showMenuBarIcon },
            set: { newValue in
                if newValue {
                    viewModel.showMenuBarIcon = true
                } else {
                    showHideMenuBarConfirmation = true
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(.system(size: 20, weight: .bold))

            SettingGroup(visibility: .generalStartup, title: "Startup") {
                SettingCard {
                    SettingRow(visibility: .generalStartupLaunchAtLogin, label: "Launch at Login", sublabel: "Start Capso when you log in") {
                        LaunchAtLogin.Toggle { Text("") }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    if Capabilities.current.standaloneCapture {
                        SettingRow(visibility: .generalStartupShowCaptureMenu, label: "Show Capture Menu", sublabel: "Show the extra menu for standalone capture tools", showDivider: true) {
                            Toggle("", isOn: menuBarToggleBinding)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                }
            }

            if Capabilities.current.automationURLs {
                SettingGroup(visibility: .generalAutomation, title: "Automation") {
                    SettingCard {
                        SettingRow(visibility: .generalAutomationAutomationURLs,
                            label: "Automation URLs",
                            sublabel: "Allow Alfred, Raycast, Shortcuts, and other apps to trigger captures"
                        ) {
                            Toggle("", isOn: $viewModel.automationURLsEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        SettingRow(visibility: .generalAutomationSupportedURLs,
                            label: "Supported URLs",
                            sublabel: "View all commands for Raycast, Alfred, and Shortcuts",
                            showDivider: true
                        ) {
                            Button("View Commands…") {
                                showingAutomationURLs = true
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            if Capabilities.current.standaloneCapture {
                SettingGroup(visibility: .generalSound, title: "Sound") {
                    SettingCard {
                        SettingRow(visibility: .generalSoundShutterSound, label: "Shutter Sound", sublabel: "Play sound after capture") {
                            Toggle("", isOn: $viewModel.playShutterSound)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                }
            }

            if let updateManager {
                UpdatesSettingsSection(updateManager: updateManager)
            }

            if Capabilities.current.standaloneCapture {
                SettingGroup(visibility: .generalScreenshotHistory, title: "Screenshot History") {
                    SettingCard {
                        SettingRow(visibility: .generalScreenshotHistorySaveToHistory, label: "Save to History", sublabel: "Automatically save all captures") {
                            Toggle("", isOn: $viewModel.historyEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        SettingRow(visibility: .generalScreenshotHistoryKeepHistory, label: "Keep History", sublabel: "Auto-delete older captures", showDivider: true) {
                            Picker("", selection: $viewModel.historyRetention) {
                                Text("1 Week").tag("oneWeek")
                                Text("2 Weeks").tag("twoWeeks")
                                Text("1 Month").tag("oneMonth")
                                Text("Unlimited").tag("unlimited")
                            }
                            .frame(width: 130)
                        }
                    }
                }
            }

            SettingGroup(visibility: .generalAbout, title: "About") {
                SettingCard {
                    SettingRow(visibility: .generalAboutVersion, label: "Version") {
                        Text(viewModel.appVersion)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .fontDesign(.monospaced)
                    }
                    SettingRow(visibility: .generalAboutReportABug, label: "Report a Bug", sublabel: "Found something broken?", showDivider: true) {
                        ExternalLinkButton(title: "Report", icon: "ladybug") {
                            openURL("https://feedback.nextshot.dev")
                        }
                    }
                    SettingRow(visibility: .generalAboutRequestAFeature, label: "Request a Feature", sublabel: "Have an idea?", showDivider: true) {
                        ExternalLinkButton(title: "Request", icon: "lightbulb") {
                            openURL("https://feedback.nextshot.dev") // Fork: Nextshot's feature feedback
                        }
                    }
                    SettingRow(visibility: .generalAboutSourceCode, label: "Source Code", sublabel: "View on GitHub", showDivider: true) {
                        ExternalLinkButton(title: "Open", icon: "chevron.left.forwardslash.chevron.right") {
                            openURL("https://github.com/spurs-planks-smithers/Capso") // Fork: Nextshot's source
                        }
                    }

                }
            }

            if SettingsVisibility.hasVisibleContent(.generalDiagnostics) {
                DisclosureGroup("Diagnostics") {
                    SettingGroup(visibility: .generalDiagnostics, title: "Diagnostics") {
                        SettingCard {
                            SettingRow(visibility: .generalDiagnosticsDiagnosticLogging, label: "Diagnostic Logging", sublabel: "Write local troubleshooting logs when enabled") {
                                Toggle("", isOn: $viewModel.diagnosticLoggingEnabled)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }
                            SettingRow(visibility: .generalDiagnosticsDiagnosticLogs, label: "Diagnostic Logs", sublabel: "Open Capso's local log folder", showDivider: true) {
                                ExternalLinkButton(title: "Open", icon: "folder") {
                                    openDiagnosticLogs()
                                }
                            }
                            SettingRow(visibility: .generalDiagnosticsCrashReports, label: "Crash Reports", sublabel: "Open macOS DiagnosticReports", showDivider: true) {
                                ExternalLinkButton(title: "Open", icon: "doc.text.magnifyingglass") {
                                    openCrashReports()
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAutomationURLs) {
            AutomationURLsSheetView(isPresented: $showingAutomationURLs)
        }
        .alert("Hide menu bar icon?", isPresented: $showHideMenuBarConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Hide Icon", role: .destructive) {
                viewModel.showMenuBarIcon = false
            }
        } message: {
            Text(hideMenuBarMessage)
        }
    }

    private var hideMenuBarMessage: String {
        let captureArea = shortcutDescription(for: .captureArea) ?? String(localized: "not set")
        let recordScreen = shortcutDescription(for: .recordScreen) ?? String(localized: "not set")
        let history = shortcutDescription(for: .screenshotHistory) ?? String(localized: "not set")
        return String(
            format: String(localized: "Capso will keep running, and your global shortcuts still work:\n\n• Capture Area: %@\n• Record Screen: %@\n• Screenshot History: %@\n\nTo open Preferences again, launch Capso from Spotlight, Launchpad, or Finder — even while it's still running."),
            captureArea, recordScreen, history
        )
    }

    private func shortcutDescription(for name: KeyboardShortcuts.Name) -> String? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return nil }
        return shortcut.description
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openDiagnosticLogs() {
        let logFileURL = DiagnosticLogger.prepareLogFile()
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    private func openCrashReports() {
        let directory = DiagnosticLogger.diagnosticReportDirectories.first!
        NSWorkspace.shared.open(directory)
    }
}

private struct ExternalLinkButton: View {
    let title: LocalizedStringKey
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 12))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .preferencesGlassActionBackground(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovered = $0 }
    }
}
