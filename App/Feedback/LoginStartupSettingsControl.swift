import AppKit
import SwiftUI

/// Fork: a compact initial choice, followed by the real macOS login state.
struct LoginStartupSettingsControl: View {
    @State private var startup = LoginStartupController.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                if startup.firstUsePending {
                    Button("Done") { startup.confirmFirstUse() }
                        .controlSize(.small)
                }
                Toggle("Launch at Login", isOn: Binding(
                    get: { startup.firstUsePending ? startup.initialChoice : startup.status == .on },
                    set: { value in
                        if startup.firstUsePending { startup.initialChoice = value }
                        else { startup.setEnabled(value) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!startup.canControl)
            }
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 225, alignment: .trailing)
            }
            if startup.status == .approvalRequired {
                Button("Open Login Items") { startup.openLoginItems() }
                    .controlSize(.small)
            }
        }
        .onAppear { startup.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            startup.refresh()
        }
    }

    private var message: String? {
        if !startup.canControl { return "Install in Applications to enable startup." }
        if startup.lastChangeFailed { return "Could not change startup. Try again." }
        if startup.firstUsePending { return "Choose Done to save this setting." }
        if startup.status == .approvalRequired { return "Allow this app in macOS Login Items." }
        if startup.status == .unavailable { return "Startup is unavailable. Reopen the installed app." }
        return nil
    }
}
