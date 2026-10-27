// App/Sources/Preferences/Tabs/ShortcutSettingsView.swift
import SwiftUI
import AppKit
import KeyboardShortcuts
import SharedKit

extension KeyboardShortcuts.Name {
    static let captureAllInOne = Self("captureAllInOne")
    static let captureArea = Self("captureArea", default: .init(.one, modifiers: [.option, .shift]))
    static let captureFullscreen = Self("captureFullscreen", default: .init(.two, modifiers: [.option, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.three, modifiers: [.option, .shift]))
    static let captureText = Self("captureText", default: .init(.four, modifiers: [.option, .shift]))
    /// Keep the existing storage key so current users retain their recording shortcut.
    static let recordScreen = Self("recordScreen", default: .init(.five, modifiers: [.option, .shift]))
    /// Opt-in to avoid adding another default global shortcut.
    static let recordFullscreen = Self("recordFullscreen")
    static let captureScrolling = Self("captureScrolling", default: .init(.six, modifiers: [.option, .shift]))
    static let captureAreaToClipboard = Self("captureAreaToClipboard", default: .init(.seven, modifiers: [.option, .shift]))
    static let captureAreaAndShare = Self("captureAreaAndShare", default: .init(.zero, modifiers: [.option, .shift]))
    static let captureAreaAndAnnotate = Self("captureAreaAndAnnotate", default: .init(.eight, modifiers: [.option, .shift]))
    static let captureAreaAndPin = Self("captureAreaAndPin")
    static let pinFromClipboard = Self("pinFromClipboard")
    static let editClipboardImage = Self("editClipboardImage")
    static let screenshotHistory = Self("screenshotHistory", default: .init(.nine, modifiers: [.option, .shift]))
    static let captureAndTranslate = Self("captureAndTranslate", default: .init(.t, modifiers: [.option, .shift]))
    static let translateSelectedText = Self("translateSelectedText", default: .init(.y, modifiers: [.option, .shift]))
    static let translateTypedText = Self("translateTypedText")
    /// No default binding — opt-in. Self-Timer is discoverable from the
    /// menu bar; shipping a default risks colliding with whatever the user
    /// has already bound in macOS or third-party apps.
    static let selfTimerCapture = Self("selfTimerCapture")
    /// Replays the last capture (area / window / fullscreen) without showing
    /// the selection overlay. Unbound by default — user must assign a key.
    static let captureLastArea = Self("captureLastArea")
    /// Unbound by default.
    static let togglePins = Self("togglePins")

    static let allCapso: [Self] = [
        .captureAllInOne, .captureArea, .captureFullscreen, .captureWindow, .captureText, .recordScreen,
        .recordFullscreen, .captureScrolling, .captureAreaToClipboard, .captureAreaAndShare,
        .captureAreaAndAnnotate, .captureAreaAndPin, .pinFromClipboard, .editClipboardImage, .screenshotHistory,
        .captureAndTranslate, .translateSelectedText, .translateTypedText, .selfTimerCapture, .captureLastArea, .togglePins,
    ]
}

struct ShortcutSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    private struct ContextualShortcut: Identifiable {
        let id: String
        let visibility: SettingsVisibilityFlag
        let scope: LocalizedStringKey
        let action: LocalizedStringKey
        /// One or more keycaps to render for this action. `.copy` in
        /// All-in-One lists all three bindings (⌘C, Return, ⌘⇧C) so users
        /// discover Return and ⌘⇧C alongside ⌘C — see issue #237.
        let shortcuts: [String]
    }

    private let contextualShortcuts: [ContextualShortcut] = [
        ContextualShortcut(id: "all-in-one-copy", visibility: .shortcutsContextualAllInOneCopy, scope: "All-in-One", action: "Copy selected area", shortcuts: ["⌘C", "⏎", "⌘⇧C"]),
        ContextualShortcut(id: "all-in-one-save", visibility: .shortcutsContextualAllInOneSave, scope: "All-in-One", action: "Save selected area", shortcuts: ["⌘S"]),
        ContextualShortcut(id: "all-in-one-pin", visibility: .shortcutsContextualAllInOnePin, scope: "All-in-One", action: "Pin selected area", shortcuts: ["⌘P"]),
        ContextualShortcut(id: "all-in-one-cancel", visibility: .shortcutsContextualAllInOneCancel, scope: "All-in-One", action: "Cancel", shortcuts: ["Esc"]),
        ContextualShortcut(id: "window-multi-select", visibility: .shortcutsContextualWindowMultiSelect, scope: "Window Capture", action: "Select multiple windows", shortcuts: ["⇧ + click"]),
        ContextualShortcut(id: "window-multi-confirm", visibility: .shortcutsContextualWindowMultiConfirm, scope: "Window Capture", action: "Capture selected windows", shortcuts: ["Release ⇧"]),
        ContextualShortcut(id: "quick-access-copy", visibility: .shortcutsContextualQuickAccessCopy, scope: "Quick Access", action: "Copy", shortcuts: ["⌘C"]),
        ContextualShortcut(id: "quick-access-save", visibility: .shortcutsContextualQuickAccessSave, scope: "Quick Access", action: "Save", shortcuts: ["⌘S"]),
        ContextualShortcut(id: "quick-access-annotate", visibility: .shortcutsContextualQuickAccessAnnotate, scope: "Quick Access", action: "Annotate", shortcuts: ["⌘E"]),
        ContextualShortcut(id: "quick-access-pin", visibility: .shortcutsContextualQuickAccessPin, scope: "Quick Access", action: "Pin", shortcuts: ["⌘P"])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shortcuts")
                .font(.system(size: 20, weight: .bold))

            // Info banner
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("Select a shortcut, then press new keys. Escape cancels. Delete clears its keys. The action stays available but inactive.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
            )
            .settingsVisibility(.shortcutsInstructions)

            FeedbackShortcutSettingsSection()

            if Capabilities.current.standaloneCapture {
                SystemScreenshotShortcutsCard()
                    .settingsVisibility(.shortcutsSystem)
            }

            if Capabilities.current.standaloneCapture {
                SettingGroup(visibility: .shortcutsCustomizable, title: "Customizable Shortcuts") {
                    SettingCard {
                        shortcutRow("All-in-One", visibility: .shortcutsCaptureCaptureAllInOne, name: .captureAllInOne)
                        shortcutRow("Capture Area", visibility: .shortcutsCaptureCaptureArea, name: .captureArea, showDivider: true)
                        shortcutRow("Capture Fullscreen", visibility: .shortcutsCaptureCaptureFullscreen, name: .captureFullscreen, showDivider: true)
                        shortcutRow("Capture Window", visibility: .shortcutsCaptureCaptureWindow, name: .captureWindow, showDivider: true)
                        shortcutRow("Capture Text (OCR)", visibility: .shortcutsCaptureCaptureText, name: .captureText, showDivider: true)
                        shortcutRow("Scrolling Capture", visibility: .shortcutsCaptureCaptureScrolling, name: .captureScrolling, showDivider: true)
                        shortcutRow("Self-Timer", visibility: .shortcutsCaptureSelfTimerCapture, name: .selfTimerCapture, showDivider: true)
                        shortcutRow("Capture Area to Clipboard", visibility: .shortcutsClipboardPinsCaptureAreaToClipboard, name: .captureAreaToClipboard, showDivider: true)
                        if Capabilities.current.cloudShare {
                            shortcutRow("Capture and Share to Cloud", visibility: .shortcutsClipboardPinsCaptureAreaAndShare, name: .captureAreaAndShare, showDivider: true)
                        }
                        shortcutRow("Capture Area & Annotate", visibility: .shortcutsClipboardPinsCaptureAreaAndAnnotate, name: .captureAreaAndAnnotate, showDivider: true)
                        shortcutRow("Capture Area & Pin", visibility: .shortcutsClipboardPinsCaptureAreaAndPin, name: .captureAreaAndPin, showDivider: true)
                        shortcutRow(
                            "Pin from Clipboard",
                            visibility: .shortcutsClipboardPinsPinFromClipboard, name: .pinFromClipboard,
                            showDivider: true,
                            help: "Float copied images, text, colors, or files above other windows"
                        )
                        shortcutRow(
                            "Edit Clipboard Image",
                            visibility: .shortcutsClipboardPinsEditClipboardImage, name: .editClipboardImage,
                            showDivider: true,
                            help: "Open the image currently copied to the clipboard in Annotate"
                        )
                        shortcutRow("Hide / Show All Pins", visibility: .shortcutsClipboardPinsTogglePins, name: .togglePins, showDivider: true)
                        if Capabilities.current.translationTools {
                            shortcutRow("Capture & Translate", visibility: .shortcutsTranslationCaptureAndTranslate, name: .captureAndTranslate, showDivider: true)
                        }
                        if Capabilities.current.translationTools {
                            shortcutRow("Translate Selected Text", visibility: .shortcutsTranslationTranslateSelectedText, name: .translateSelectedText, showDivider: true)
                        }
                        if Capabilities.current.translationTools {
                            shortcutRow("Translate Typed Text", visibility: .shortcutsTranslationTranslateTypedText, name: .translateTypedText, showDivider: true)
                        }
                        shortcutRow("Capture Previous Area", visibility: .shortcutsCaptureCaptureLastArea, name: .captureLastArea, showDivider: true)
                        if Capabilities.current.recordingTools {
                            shortcutRow("Record Area", visibility: .shortcutsRecordingRecordScreen, name: .recordScreen, showDivider: true)
                        }
                        if Capabilities.current.recordingTools {
                            shortcutRow("Record Full Screen", visibility: .shortcutsRecordingRecordFullscreen, name: .recordFullscreen, showDivider: true)
                        }
                        shortcutRow("Screenshot History", visibility: .shortcutsHistoryScreenshotHistory, name: .screenshotHistory, showDivider: true)
                    }
                }
            }

            if Capabilities.current.standaloneCapture {
                SettingGroup(visibility: .shortcutsContextual, title: "Contextual Shortcuts") {
                    SettingCard {
                        centerLockRow
                        ForEach(Array(contextualShortcuts.enumerated()).filter { SettingsVisibility.isVisible($0.element.visibility) }, id: \.element.id) { _, item in
                            contextualShortcutRow(item, showDivider: true)
                        }
                    }
                }
            }
            if !Capabilities.current.standaloneCapture {
                DisclosureGroup("Advanced") {
                    SettingCard { centerLockRow }
                        .padding(.top, 8)
                }
            }
        }
    }

    private var centerLockRow: some View {
        SettingRow(
            visibility: .shortcutsSelectionCenterFromClick,
            label: "Center 1:1 from click",
            sublabel: "Selection",
            showDivider: false
        ) {
            HStack(spacing: 6) {
                ShortcutKeycap(text: "⇧")
                Text("+")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                SquareCenterLockKeyRecorder(shortcut: $viewModel.squareCenterLockShortcut)
            }
        }
        .help("Hold Shift for 1:1, then this extra key to grow from the click as the center. Shift cannot be changed.")
    }

    @ViewBuilder
    private func shortcutRow(
        _ label: LocalizedStringKey,
        visibility: SettingsVisibilityFlag,
        name: KeyboardShortcuts.Name,
        showDivider: Bool = false,
        help: LocalizedStringKey? = nil
    ) -> some View {
        let row = SettingRow(visibility: visibility, label: label, showDivider: showDivider) {
            KeyboardShortcuts.Recorder(for: name)
                .controlSize(.small)
        }

        if let help {
            row.help(help)
        } else {
            row
        }
    }

    private func contextualShortcutRow(_ item: ContextualShortcut, showDivider: Bool = false) -> some View {
        SettingRow(visibility: item.visibility, label: item.action, sublabel: item.scope, showDivider: showDivider) {
            HStack(spacing: 6) {
                ForEach(Array(item.shortcuts.enumerated()), id: \.offset) { _, shortcut in
                    ShortcutKeycap(text: shortcut)
                }
            }
        }
    }
}

private struct SquareCenterLockKeyRecorder: View {
    @Binding var shortcut: SquareCenterLockShortcut
    @State private var isRecording = false

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            Text(isRecording ? "…" : shortcut.displayCharacter)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    Color.primary.opacity(isRecording ? 0.12 : 0.08),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isRecording ? Color.accentColor : Color.primary.opacity(0.10),
                            lineWidth: isRecording ? 1.5 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Extra key for centered 1:1")
        .accessibilityValue(shortcut.displayCharacter)
        .help("Click to record a different extra key")
        .background {
            if isRecording {
                CenterLockKeyCapture { event in
                    if event.keyCode == 53 {
                        isRecording = false
                        return
                    }
                    if let recorded = SquareCenterLockShortcut(event: event) {
                        shortcut = recorded
                        isRecording = false
                    }
                }
            }
        }
    }
}

/// Local key-down monitor used only while the extra-key recorder is listening.
private struct CenterLockKeyCapture: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var onKeyDown: (NSEvent) -> Void
        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Void) {
            self.onKeyDown = onKeyDown
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.onKeyDown(event)
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private struct ShortcutKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}

/// Helps hand ⇧⌘3 / ⇧⌘4 / ⇧⌘5 over from the macOS screenshot tool to Capso.
private struct SystemScreenshotShortcutsCard: View {
    @State private var systemShortcutsOn = SystemScreenshotShortcuts.areEnabled
    @State private var capsoUsesAny = Self.capsoUsesAnySystemKey

    private static let assignments: [(KeyboardShortcuts.Name, KeyboardShortcuts.Key)] = [
        (.captureFullscreen, .three), (.captureArea, .four), (.captureAllInOne, .five),
    ]

    /// Once any Capso action uses one of these keys, the user has set them up themselves.
    private static var capsoUsesAnySystemKey: Bool {
        let systemKeys = assignments.map { KeyboardShortcuts.Shortcut($0.1, modifiers: [.command, .shift]) }
        return KeyboardShortcuts.Name.allCapso.contains { name in
            KeyboardShortcuts.getShortcut(for: name).map(systemKeys.contains) ?? false
        }
    }

    var body: some View {
        Group {
            if systemShortcutsOn {
                banner(
                    icon: "exclamationmark.triangle",
                    tint: .orange,
                    text: "macOS still uses ⇧⌘3, ⇧⌘4 and ⇧⌘5 for its own screenshots. To use them for Capso, turn off the shortcuts under Keyboard Shortcuts → Screenshots."
                ) {
                    Button("Open Keyboard Settings") { NSWorkspace.shared.open(SystemScreenshotShortcuts.settingsURL) }
                        .settingsVisibility(.shortcutsSystemOpenSettings)
                }
            } else if !capsoUsesAny {
                banner(
                    icon: "keyboard",
                    tint: .blue,
                    text: "The macOS screenshot shortcuts are off. Capso can take them over: ⇧⌘3 Capture Fullscreen, ⇧⌘4 Capture Area, ⇧⌘5 All-in-One."
                ) {
                    Button("Use ⇧⌘3 / ⇧⌘4 / ⇧⌘5") {
                        for (name, key) in Self.assignments {
                            KeyboardShortcuts.setShortcut(.init(key, modifiers: [.command, .shift]), for: name)
                        }
                        capsoUsesAny = true
                    }
                    .settingsVisibility(.shortcutsSystemUseKeys)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            systemShortcutsOn = SystemScreenshotShortcuts.areEnabled
            capsoUsesAny = Self.capsoUsesAnySystemKey
        }
    }

    private func banner(icon: String, tint: Color, text: LocalizedStringKey, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.2), lineWidth: 0.5))
    }
}
