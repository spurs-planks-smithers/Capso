// App/Feedback/FeedbackStatusItem.swift
import AppKit
import FeedbackKit

/// Fork: a second menu bar item, shown only while a feedback session is active.
/// Its title is the short product name and the capture count, for example
/// "Nshot (2)". The menu's first line names the session.
@MainActor
final class FeedbackStatusItem: NSObject {
    var onCopyPrompt: (() -> Void)?
    var onCopyLastCapture: (() -> Void)?
    var onOpenFolder: (() -> Void)?
    var onEndSession: (() -> Void)?
    var onShowShortcut: (() -> Void)?

    private var item: NSStatusItem?
    private var sessionLine: NSMenuItem?

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
        item.button?.title = " \(ForkBranding.shortName) (\(session.captures.count))"
        sessionLine?.title = "Session: \(session.slug)"
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "\(ForkBranding.name) feedback session")
        item.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        // No action, so the menu shows it gray and it cannot be chosen. A new
        // line for each item: a menu item can be in only one menu.
        let sessionLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        self.sessionLine = sessionLine
        menu.addItem(sessionLine)
        menu.addItem(.separator())
        menu.addItem(menuItem("Copy Last Capture", action: #selector(copyLastCapture)))
        menu.addItem(menuItem("Copy Session Prompt", action: #selector(copyPrompt)))
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
    @objc private func copyLastCapture() { onCopyLastCapture?() }
    @objc private func openFolder() { onOpenFolder?() }
    @objc private func endSession() { onEndSession?() }
    @objc private func showShortcut() { onShowShortcut?() }
}
