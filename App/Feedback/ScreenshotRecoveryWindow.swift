import AppKit
import SwiftUI

/// Keeps captured pixels and the retry action available after an instant-copy failure.
@MainActor
final class ScreenshotRecoveryWindow: NSPanel {
    init(image: CGImage, error: Error, retry: @escaping () -> Void, discard: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Screenshot Recovery"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        minSize = NSSize(width: 440, height: 340)
        contentView = NSHostingView(rootView: ScreenshotRecoveryView(
            image: NSImage(cgImage: image, size: .zero),
            message: error.localizedDescription, retry: retry, discard: discard
        ))
        center()
    }

    override var canBecomeKey: Bool { true }
}

private struct ScreenshotRecoveryView: View {
    let image: NSImage
    let message: String
    let retry: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screenshot could not finish").font(.headline)
            Text(message).font(.callout)
            Text("Your screenshot stays here until you retry or discard it.")
                .font(.callout).foregroundStyle(.secondary)
            Image(nsImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Captured screenshot")
            HStack {
                Button("Discard Screenshot", action: discard)
                Spacer()
                Button("Try Copy Again", action: retry).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
