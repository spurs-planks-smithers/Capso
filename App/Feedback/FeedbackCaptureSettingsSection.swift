import SharedKit
import SwiftUI

/// The capture preferences shared by feedback rounds. Image copy stays
/// available even when an older profile stores File Path for ordinary captures.
struct FeedbackCaptureSettingsSection: View {
    @Bindable var viewModel: PreferencesViewModel

    var body: some View {
        SettingGroup(visibility: .screenshotsCapture, title: "Capture") {
            SettingCard {
                SettingRow(visibility: .screenshotsCaptureShowCursor, label: "Show Pointer", sublabel: "Include the mouse pointer in captures") {
                    Toggle("", isOn: $viewModel.screenshotShowsCursor)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingRow(visibility: .screenshotsCaptureClipboardFormat, label: "Clipboard Format", sublabel: clipboardFormatHelp, showDivider: true) {
                    Picker("", selection: $viewModel.screenshotClipboardFormat) {
                        Text("PNG").tag(ScreenshotClipboardFormat.png)
                        Text("JPEG").tag(ScreenshotClipboardFormat.jpeg)
                        Text("TIFF").tag(ScreenshotClipboardFormat.tiff)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var clipboardFormatHelp: LocalizedStringKey {
        Capabilities.current.screenshotCopy
            ? "Copy Screenshot copies a selected area in this format for pasting."
            : "Images copied with Escape use this format."
    }
}
