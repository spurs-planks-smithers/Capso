import AppKit
import SwiftUI

/// Owns one local browser. Opening it starts no capture or optional service.
@MainActor
final class ScreenshotHistoryWindow {
    private let presentation = ScreenshotHistoryPresentation()
    private let onCopy: (ScreenshotHistoryItem, ScreenshotImageVariant) -> Void
    private let onPreview: (ScreenshotHistoryItem) -> Void
    private let onAnnotate: (ScreenshotHistoryItem) -> Void
    private var window: NSPanel?

    init(
        onCopy: @escaping (ScreenshotHistoryItem, ScreenshotImageVariant) -> Void,
        onPreview: @escaping (ScreenshotHistoryItem) -> Void,
        onAnnotate: @escaping (ScreenshotHistoryItem) -> Void
    ) {
        self.onCopy = onCopy
        self.onPreview = onPreview
        self.onAnnotate = onAnnotate
    }

    func update(items: [ScreenshotHistoryItem]) {
        presentation.items = items
    }

    func show(items: [ScreenshotHistoryItem]) {
        presentation.items = items
        if window == nil {
            let panel = ScreenshotHistoryPanel(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "Screenshot History"
            panel.minSize = NSSize(width: 800, height: 580)
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: ScreenshotHistoryView(
                presentation: presentation,
                onCopy: onCopy,
                onPreview: onPreview,
                onAnnotate: onAnnotate
            ))
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

private final class ScreenshotHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
