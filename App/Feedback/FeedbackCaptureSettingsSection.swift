import SharedKit
import SwiftUI

/// The capture preferences shared by feedback rounds. Image copy stays
/// available even when an older profile stores File Path for ordinary captures.
struct FeedbackCaptureSettingsSection: View {
    @Bindable var viewModel: PreferencesViewModel

    var body: some View {
        SettingGroup(title: "Capture") {
            SettingCard {
                SettingRow(label: "Show Cursor", sublabel: "Include the mouse pointer in captures") {
                    Toggle("", isOn: $viewModel.screenshotShowsCursor)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingRow(label: "Clipboard Format", sublabel: "Image copied with Escape before adding marks", showDivider: true) {
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
}
