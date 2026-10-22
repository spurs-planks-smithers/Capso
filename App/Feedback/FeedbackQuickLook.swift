// App/Feedback/FeedbackQuickLook.swift
import AppKit
import QuickLookUI

/// Fork: shows one capture in the shared Quick Look panel, the same preview
/// Finder gives for the Space bar. The panel does not keep its data source
/// alive, so the controller holds this object. The panel asks for items on the
/// main thread, so the conformance is `@preconcurrency`.
@MainActor
final class FeedbackQuickLook: NSObject, @preconcurrency QLPreviewPanelDataSource {
    private var url: URL?

    /// Opens the Quick Look panel on `url`. The status menu is closed by now.
    /// If the panel does not show, the file opens in its default app instead.
    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else {
            NSWorkspace.shared.open(url)
            return
        }
        panel.dataSource = self
        panel.reloadData()
        // This is a menu bar app, so it is not active when the panel opens.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        if !panel.isVisible {
            NSWorkspace.shared.open(url)
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url as NSURL?
    }
}
