import SwiftUI

struct SettingRow<Control: View>: View {
    let visibility: SettingsVisibilityFlag
    var visibilityInstance: String? = nil
    let label: LocalizedStringKey
    var sublabel: LocalizedStringKey? = nil
    var showDivider: Bool = false
    var explanation: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        if SettingsVisibility.hasVisibleContent(visibility),
           SettingsVisibility.isVisible(visibility, instance: visibilityInstance) {
            VStack(spacing: 0) {
                if showDivider {
                    Divider()
                        .background(Color.white.opacity(0.06))
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(label)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            if let explanation { SettingsInfoButton(text: explanation) }
                        }
                        if let sublabel {
                            Text(sublabel)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    control
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 40)
            }
        }
    }
}
