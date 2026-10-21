// App/Feedback/FeedbackStatusItem.swift
import AppKit
import FeedbackKit

/// Fork: a second menu bar item, shown only while a feedback session is active.
/// Its title is the session slug and the capture count.
@MainActor
final class FeedbackStatusItem: NSObject {
    var onCopyPrompt: (() -> Void)?
    var onOpenFolder: (() -> Void)?
    var onEndSession: (() -> Void)?
    var onShowShortcut: (() -> Void)?

    private var item: NSStatusItem?

    func update(session: FeedbackSession?) {
        guard let session else {
            if let item {
                NSStatusBar.system.removeStatusItem(item)
            }
            item = nil
            return
        }
        let item = self.item ?? makeItem()
        self.item = item
        item.button?.title = " \(session.slug) (\(session.captures.count))"
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Feedback session")
        item.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.addItem(menuItem("Copy Prompt", action: #selector(copyPrompt)))
        menu.addItem(menuItem("Open Folder", action: #selector(openFolder)))
        menu.addItem(menuItem("End Session", action: #selector(endSession)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Feedback Shortcut...", action: #selector(showShortcut)))
        item.menu = menu
        return item
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func copyPrompt() { onCopyPrompt?() }
    @objc private func openFolder() { onOpenFolder?() }
    @objc private func endSession() { onEndSession?() }
    @objc private func showShortcut() { onShowShortcut?() }
}
