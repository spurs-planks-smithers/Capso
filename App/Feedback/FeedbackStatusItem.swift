// App/Feedback/FeedbackStatusItem.swift
import AppKit
import FeedbackKit
import KeyboardShortcuts

/// Fork: what the menu shows. The controller builds a fresh value each time
/// the menu opens, so the status item holds no session data of its own.
struct FeedbackMenuState {
    /// The session now being captured into, or nil.
    var active: FeedbackSession?
    /// Ended sessions, newest first.
    var recent: [FeedbackSession]
    var basket: FeedbackBasket
    /// The folder that holds every session folder.
    var rootURL: URL

    /// What the menu shows when no provider is set.
    static let empty = FeedbackMenuState(
        active: nil,
        recent: [],
        basket: FeedbackBasket(),
        rootURL: URL(fileURLWithPath: "/", isDirectory: true)
    )
}

/// Fork: a second menu bar item. It stays in the menu bar at all times.
/// With no session it shows the icon only. During a session its title is the
/// short product name and the capture count, for example "Nshot (2)".
///
/// The menu is rebuilt each time it opens. It lists the active session's
/// actions, the last ended sessions under "Recent", and a basket of checked
/// captures. The basket lines sit below the Recent rows, so checking a box
/// never moves a row above it and an open submenu stays lined up with its
/// parent row. Each session row opens a submenu. A submenu fills when it
/// opens, so thumbnails decode only for the session being looked at.
@MainActor
final class FeedbackStatusItem: NSObject, NSMenuDelegate {
    var stateProvider: (() -> FeedbackMenuState)?

    var onCopyPrompt: (() -> Void)?
    var onCopyLastCapture: (() -> Void)?
    var onOpenFolder: (() -> Void)?
    var onEndSession: (() -> Void)?
    var onShowShortcut: (() -> Void)?
    var onShowSettings: (() -> Void)?

    var onStartSession: (() -> Void)?
    var onOpenAllSessions: (() -> Void)?
    var onCopySelected: (() -> Void)?
    var onClearSelection: (() -> Void)?
    var onToggleCapture: ((FeedbackBasketKey) -> Void)?
    var onQuickLook: ((FeedbackBasketKey) -> Void)?
    var onCopyRecentSession: ((FeedbackSession) -> Void)?
    var onOpenRecentFolder: ((FeedbackSession) -> Void)?
    var onResumeSession: ((FeedbackSession) -> Void)?

    /// One session line in the open menu.
    private struct SessionRow {
        var item: NSMenuItem
        var menu: NSMenu
        var session: FeedbackSession
    }

    private var item: NSStatusItem?
    private var topMenu: NSMenu?
    private var sessionRows: [SessionRow] = []
    private var copySelectedItem: NSMenuItem?
    private var clearSelectionItem: NSMenuItem?
    private var basketSeparator: NSMenuItem?
    private var allSessionsItem: NSMenuItem?

    /// Made once and added again on each rebuild. `setShortcut(for:)` adds a
    /// notification observer that nothing removes, so a new item on every menu
    /// open would leave one more observer and one more item behind.
    private lazy var startSessionItem: NSMenuItem = {
        let item = menuItem("Start Session", action: #selector(startSession))
        // The same call the main menu uses, so a changed shortcut shows here.
        item.setShortcut(for: .feedbackCapture)
        return item
    }()

    /// Never removes the item. The title shows only during a session.
    func update(session: FeedbackSession?) {
        let item = self.item ?? makeItem()
        self.item = item
        if let session {
            item.button?.title = " \(ForkBranding.shortName) (\(session.captures.count))"
            item.button?.imagePosition = .imageLeading
        } else {
            item.button?.title = ""
            item.button?.imagePosition = .imageOnly
        }
    }

    /// The basket changed while the menu may be open. Adds, retitles, or
    /// removes the basket lines and refreshes the "N selected" subtitles. It
    /// uses the basket it is given and never asks the state provider, so a
    /// checkbox click reads nothing from disk.
    func basketDidChange(_ basket: FeedbackBasket) {
        guard let menu = topMenu else { return }
        let count = basket.count
        if count == 0 {
            removeBasketItems(from: menu)
        } else if let copySelectedItem {
            copySelectedItem.title = Self.copySelectedTitle(count)
        } else {
            insertBasketItems(into: menu, count: count)
        }
        for row in sessionRows {
            row.item.subtitle = FeedbackLibrary.subtitle(
                for: row.session,
                selectedCount: basket.count(inFolder: row.session.folderName)
            )
        }
    }

    private func currentState() -> FeedbackMenuState {
        stateProvider?() ?? .empty
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = ForkBranding.menuBarMark(
            description: "\(ForkBranding.name) feedback session",
            fallbackSymbol: "text.bubble"
        )

        let menu = NSMenu()
        // Items are enabled by hand: a line with no action stays gray, and a
        // row with a custom view still gets its clicks.
        menu.autoenablesItems = false
        menu.delegate = self
        topMenu = menu
        // Fill it once so it is never empty. It is rebuilt on each open.
        rebuildMenu(menu)
        item.menu = menu
        return item
    }

    // MARK: - Top menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === topMenu {
            rebuildMenu(menu)
        } else if let row = sessionRows.first(where: { $0.menu === menu }) {
            fillSubmenu(row.menu, for: row.session)
        }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        let state = currentState()
        menu.removeAllItems()
        sessionRows = []
        copySelectedItem = nil
        clearSelectionItem = nil
        basketSeparator = nil
        allSessionsItem = nil

        // The running build comes first, so anyone can tell builds apart.
        menu.addItem(grayLine(ForkBranding.versionLine))
        menu.addItem(.separator())

        if let active = state.active {
            menu.addItem(grayLine("Session: \(active.slug)"))
            menu.addItem(.separator())
            menu.addItem(menuItem("Copy Last Capture", action: #selector(copyLastCapture)))
            menu.addItem(menuItem("Copy Session Prompt", action: #selector(copyPrompt)))
            menu.addItem(menuItem("Open Folder", action: #selector(openFolder)))
            menu.addItem(menuItem("End Session", action: #selector(endSession)))
        } else {
            menu.addItem(grayLine("No active session"))
            // An item can sit in one menu only, so take it out of the old one.
            startSessionItem.menu?.removeItem(startSessionItem)
            menu.addItem(startSessionItem)
        }
        menu.addItem(.separator())

        // The active session has no end time, so Recent should never hold it.
        // The check keeps it out if the provider ever lists it.
        let recent = state.recent.filter { $0.folderName != state.active?.folderName }
        if !recent.isEmpty {
            menu.addItem(.sectionHeader(title: "Recent"))
            let now = Date()
            for session in recent {
                let row = makeSessionRow(session, now: now, basket: state.basket)
                sessionRows.append(row)
                menu.addItem(row.item)
            }
            menu.addItem(.separator())
        }

        let allSessions = menuItem("All Sessions...", action: #selector(openAllSessions))
        allSessionsItem = allSessions
        menu.addItem(allSessions)
        menu.addItem(menuItem("Feedback Shortcut...", action: #selector(showShortcut)))
        // The capture menu's icon is hidden by default (`ForkDefaults`), so
        // this menu carries Settings and Quit.
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings...", action: #selector(showSettings)))
        menu.addItem(menuItem("Quit \(ForkBranding.name)", action: #selector(quit)))

        // Last, so the lines go in below the Recent rows.
        if state.basket.count > 0 {
            insertBasketItems(into: menu, count: state.basket.count)
        }
    }

    private func makeSessionRow(_ session: FeedbackSession, now: Date, basket: FeedbackBasket) -> SessionRow {
        let title = FeedbackLibrary.title(startedAt: session.startedAt, now: now, timeZone: .current)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.subtitle = FeedbackLibrary.subtitle(
            for: session,
            selectedCount: basket.count(inFolder: session.folderName)
        )

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self
        // A placeholder, so the submenu is never empty before it first opens.
        // menuNeedsUpdate replaces it before anything shows.
        submenu.addItem(grayLine("Loading..."))
        item.submenu = submenu
        return SessionRow(item: item, menu: submenu, session: session)
    }

    // MARK: - Basket lines

    private static func copySelectedTitle(_ count: Int) -> String {
        "Copy \(count) Selected"
    }

    /// The basket lines sit below the Recent rows: a separator, Copy N
    /// Selected, and Clear Selection, in front of the separator that comes
    /// before "All Sessions...". Nothing above that point moves, so a session
    /// submenu that is open stays lined up with its parent row. With no Recent
    /// rows (a basket entry can outlive the Recent list), the lines sit in
    /// front of that same separator, under the session actions.
    private func insertBasketItems(into menu: NSMenu, count: Int) {
        guard let allSessionsItem, allSessionsItem.menu === menu else { return }
        let anchor = menu.index(of: allSessionsItem) - 1
        guard anchor >= 0 else { return }
        let copy = menuItem(Self.copySelectedTitle(count), action: #selector(copySelected))
        let clear = menuItem("Clear Selection", action: #selector(clearSelection))
        let separator = NSMenuItem.separator()
        menu.insertItem(separator, at: anchor)
        menu.insertItem(copy, at: anchor + 1)
        menu.insertItem(clear, at: anchor + 2)
        copySelectedItem = copy
        clearSelectionItem = clear
        basketSeparator = separator
    }

    private func removeBasketItems(from menu: NSMenu) {
        for item in [copySelectedItem, clearSelectionItem, basketSeparator] {
            if let item, item.menu === menu {
                menu.removeItem(item)
            }
        }
        copySelectedItem = nil
        clearSelectionItem = nil
        basketSeparator = nil
    }

    // MARK: - Session submenu

    /// Runs each time the submenu opens. Rows are new each time, so a row
    /// always starts with the current basket state.
    private func fillSubmenu(_ menu: NSMenu, for listed: FeedbackSession) {
        let state = currentState()
        // Prefer the freshly read session. Fall back to the one the row was built from.
        let session = state.recent.first { $0.folderName == listed.folderName } ?? listed
        let folderURL = state.rootURL.appendingPathComponent(session.folderName, isDirectory: true)

        menu.removeAllItems()
        menu.addItem(menuItem("Copy Session Prompt", action: #selector(copyRecentSession(_:)), session: session))
        menu.addItem(.separator())

        for capture in session.captures {
            let key = FeedbackBasketKey(folderName: session.folderName, captureIndex: capture.index)
            let title = FeedbackLibrary.captureRowTitle(capture, timeZone: .current)
            let rowView = FeedbackCaptureRowView(
                key: key,
                title: title,
                subtitle: FeedbackLibrary.itemCountText(capture),
                thumbnail: FeedbackThumbnails.image(for: folderURL.appendingPathComponent(capture.imageFile)),
                checked: state.basket.contains(key),
                onToggle: { [weak self] key in self?.onToggleCapture?(key) },
                onQuickLook: { [weak self] key in self?.closeMenuThenQuickLook(key) }
            )
            let rowItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            rowItem.view = rowView
            menu.addItem(rowItem)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Open Folder", action: #selector(openRecentFolder(_:)), session: session))
        // Only one session can be active, so Resume waits until it ends.
        if state.active == nil {
            menu.addItem(menuItem("Resume Session", action: #selector(resumeSession(_:)), session: session))
        }
    }

    /// Option-click on a capture row. The menu closes first, so the Quick Look
    /// panel does not open behind it and Space and Esc reach the panel, not the
    /// menu. The panel opens once the run loop is back in its default mode,
    /// which happens after menu tracking has ended.
    private func closeMenuThenQuickLook(_ key: FeedbackBasketKey) {
        topMenu?.cancelTracking()
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.onQuickLook?(key) }
        }
    }

    // MARK: - Items

    private func menuItem(_ title: String, action: Selector, session: FeedbackSession? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = session
        return item
    }

    /// No action and not enabled, so the menu shows it gray and it cannot be chosen.
    private func grayLine(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func copyPrompt() { onCopyPrompt?() }
    @objc private func copyLastCapture() { onCopyLastCapture?() }
    @objc private func openFolder() { onOpenFolder?() }
    @objc private func endSession() { onEndSession?() }
    @objc private func showShortcut() { onShowShortcut?() }
    @objc private func showSettings() { onShowSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func startSession() { onStartSession?() }
    @objc private func openAllSessions() { onOpenAllSessions?() }
    @objc private func copySelected() { onCopySelected?() }
    @objc private func clearSelection() { onClearSelection?() }

    @objc private func copyRecentSession(_ sender: NSMenuItem) {
        if let session = sender.representedObject as? FeedbackSession { onCopyRecentSession?(session) }
    }

    @objc private func openRecentFolder(_ sender: NSMenuItem) {
        if let session = sender.representedObject as? FeedbackSession { onOpenRecentFolder?(session) }
    }

    @objc private func resumeSession(_ sender: NSMenuItem) {
        if let session = sender.representedObject as? FeedbackSession { onResumeSession?(session) }
    }
}
