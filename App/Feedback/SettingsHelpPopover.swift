import SwiftUI

struct SettingsHelpPoint {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
}

struct SettingsHelpContent {
    let points: [SettingsHelpPoint]
}

/// One native popover supplies both hover and keyboard-accessible help.
struct SettingsInfoButton: View {
    let content: SettingsHelpContent
    @State private var showingHelp = false

    var body: some View {
        Button { showingHelp = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show setting details")
        .onHover { showingHelp = $0 }
        .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(content.points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: 12) {
                        Image(point.icon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 1)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(point.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(width: 280, alignment: .leading)
            .padding(16)
        }
    }
}
