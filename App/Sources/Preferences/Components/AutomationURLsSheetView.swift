// App/Sources/Preferences/Components/AutomationURLsSheetView.swift
import SwiftUI
import AppKit
import SharedKit

struct AutomationCommandItem: Identifiable {
    let id: String
    let visibility: SettingsVisibilityFlag
    let name: LocalizedStringKey
    let urlString: String
}

struct AutomationCommandSection: Identifiable {
    let id: String
    let visibility: SettingsVisibilityFlag
    let title: LocalizedStringKey
    let items: [AutomationCommandItem]
}

struct AutomationURLsSheetView: View {
    @Binding var isPresented: Bool
    @State private var copiedURL: String? = nil
    @State private var copiedAll = false

    private let sections: [AutomationCommandSection] = [
        AutomationCommandSection(
            id: "screenshots",
            visibility: .generalAutomationCommandsSectionScreenshots,
            title: "Screenshots",
            items: [
                AutomationCommandItem(id: "all-in-one", visibility: .generalAutomationCommandsAllInOne, name: "All-in-One", urlString: "nextshot://grab/all-in-one"),
                AutomationCommandItem(id: "area", visibility: .generalAutomationCommandsArea, name: "Capture Area", urlString: "nextshot://grab/area"),
                AutomationCommandItem(id: "fullscreen", visibility: .generalAutomationCommandsFullscreen, name: "Capture Fullscreen", urlString: "nextshot://grab/fullscreen"),
                AutomationCommandItem(id: "window", visibility: .generalAutomationCommandsWindow, name: "Capture Window", urlString: "nextshot://grab/window"),
                AutomationCommandItem(id: "scrolling", visibility: .generalAutomationCommandsScrolling, name: "Scrolling Capture", urlString: "nextshot://grab/scrolling"),
                AutomationCommandItem(id: "self-timer", visibility: .generalAutomationCommandsSelfTimer, name: "Self-Timer", urlString: "nextshot://grab/self-timer"),
                AutomationCommandItem(id: "last-area", visibility: .generalAutomationCommandsLastArea, name: "Capture Previous Area", urlString: "nextshot://grab/last-area"),
                AutomationCommandItem(id: "clipboard", visibility: .generalAutomationCommandsClipboard, name: "Capture Area to Clipboard", urlString: "nextshot://grab/clipboard"),
                AutomationCommandItem(id: "share", visibility: .generalAutomationCommandsShare, name: "Capture and Share to Cloud", urlString: "nextshot://grab/share"),
                AutomationCommandItem(id: "annotate", visibility: .generalAutomationCommandsAnnotate, name: "Capture Area & Annotate", urlString: "nextshot://grab/annotate"),
                AutomationCommandItem(id: "area-and-pin", visibility: .generalAutomationCommandsAreaAndPin, name: "Capture Area & Pin", urlString: "nextshot://grab/area-and-pin")
            ]
        ),
        AutomationCommandSection(
            id: "clipboard",
            visibility: .generalAutomationCommandsSectionClipboard,
            title: "Clipboard",
            items: [
                AutomationCommandItem(id: "pin", visibility: .generalAutomationCommandsPin, name: "Pin from Clipboard", urlString: "nextshot://grab/pin"),
                AutomationCommandItem(id: "edit-clipboard", visibility: .generalAutomationCommandsEditClipboard, name: "Edit Clipboard Image", urlString: "nextshot://grab/edit-clipboard"),
                AutomationCommandItem(id: "open-image", visibility: .generalAutomationCommandsOpenImage, name: "Open Image File", urlString: "nextshot://grab/open-image")
            ]
        ),
        AutomationCommandSection(
            id: "ocr-translation",
            visibility: .generalAutomationCommandsSectionOcrTranslation,
            title: "Text & Translation",
            items: [
                AutomationCommandItem(id: "ocr", visibility: .generalAutomationCommandsOcr, name: "Capture Text (OCR)", urlString: "nextshot://grab/ocr"),
                AutomationCommandItem(id: "translate", visibility: .generalAutomationCommandsTranslate, name: "Capture & Translate", urlString: "nextshot://grab/translate"),
                AutomationCommandItem(id: "translate-selection", visibility: .generalAutomationCommandsTranslateSelection, name: "Translate Selected Text", urlString: "nextshot://grab/translate-selection"),
                AutomationCommandItem(id: "translate-text", visibility: .generalAutomationCommandsTranslateText, name: "Translate Typed Text", urlString: "nextshot://grab/translate-text")
            ]
        ),
        AutomationCommandSection(
            id: "recording",
            visibility: .generalAutomationCommandsSectionRecording,
            title: "Recording",
            items: [
                AutomationCommandItem(id: "record", visibility: .generalAutomationCommandsRecord, name: "Record Area", urlString: "nextshot://grab/record"),
                AutomationCommandItem(id: "record-fullscreen", visibility: .generalAutomationCommandsRecordFullscreen, name: "Record Full Screen", urlString: "nextshot://grab/record-fullscreen")
            ]
        ),
        AutomationCommandSection(
            id: "desktop",
            visibility: .generalAutomationCommandsSectionDesktop,
            title: "Desktop",
            items: [
                AutomationCommandItem(id: "hide-desktop-icons", visibility: .generalAutomationCommandsHideDesktopIcons, name: "Hide Desktop Icons", urlString: "nextshot://grab/hide-desktop-icons"),
                AutomationCommandItem(id: "show-desktop-icons", visibility: .generalAutomationCommandsShowDesktopIcons, name: "Show Desktop Icons", urlString: "nextshot://grab/show-desktop-icons"),
                AutomationCommandItem(id: "toggle-desktop-icons", visibility: .generalAutomationCommandsToggleDesktopIcons, name: "Toggle Desktop Icons", urlString: "nextshot://grab/toggle-desktop-icons")
            ]
        ),
        AutomationCommandSection(
            id: "app-history",
            visibility: .generalAutomationCommandsSectionAppHistory,
            title: "History & Settings",
            items: [
                AutomationCommandItem(id: "history", visibility: .generalAutomationCommandsHistory, name: "Screenshot History", urlString: "nextshot://grab/history"),
                AutomationCommandItem(id: "preferences", visibility: .generalAutomationCommandsPreferences, name: "Preferences", urlString: "nextshot://grab/preferences")
            ]
        )
    ]

    private func availableItems(_ section: AutomationCommandSection) -> [AutomationCommandItem] {
        guard SettingsVisibility.isVisible(section.visibility) else { return [] }
        return section.items.filter { item in
            SettingsVisibility.isVisible(item.visibility) && (URL(string: item.urlString).flatMap(AutomationURLAction.init(url:)).map(Capabilities.allowsAutomation) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automation URLs")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Trigger Capso actions from Raycast, Alfred, Shortcuts, or shell scripts.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(copiedAll ? "Copied All" : "Copy All") {
                    copyAllURLs()
                }
                .controlSize(.small)
                .settingsVisibility(.generalAutomationCommandsCopyAll)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections.filter { !availableItems($0).isEmpty }) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .padding(.leading, 2)

                            SettingCard {
                                ForEach(Array(availableItems(section).enumerated()), id: \.element.id) { index, item in
                                    commandRow(item: item, showDivider: index > 0)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 360)

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
                .settingsVisibility(.generalAutomationCommandsDone)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func commandRow(item: AutomationCommandItem, showDivider: Bool) -> some View {
        SettingRow(visibility: item.visibility, label: item.name, showDivider: showDivider) {
            Button {
                copyURL(item.urlString)
            } label: {
                HStack(spacing: 6) {
                    Text(item.urlString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(copiedURL == item.urlString ? Color.green : Color.secondary)

                    Image(systemName: copiedURL == item.urlString ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copiedURL == item.urlString ? Color.green : Color.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Color.primary.opacity(copiedURL == item.urlString ? 0.12 : 0.05),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .help("Click to copy URL")
        }
    }

    private func copyURL(_ urlString: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        copiedURL = urlString
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedURL == urlString {
                copiedURL = nil
            }
        }
    }

    private func copyAllURLs() {
        var lines: [String] = []
        for section in sections {
            for item in availableItems(section) {
                lines.append(item.urlString)
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        copiedAll = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedAll = false
        }
    }
}
