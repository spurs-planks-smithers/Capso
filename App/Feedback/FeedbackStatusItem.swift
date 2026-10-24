// App/Feedback/FeedbackStatusItem.swift
import AppKit
import FeedbackKit
import KeyboardShortcuts

/// Fork: what the menu shows. The controller builds a fresh value each time
/// the menu opens, so the status item holds no round data of its own.
struct FeedbackMenuState {
    /// The round now being captured into, or nil.
    var active: FeedbackRound?
    /// Ended rounds, newest first.
    var recent: [FeedbackRound]
    var basket: FeedbackBasket
    /// The folder that holds every round folder.
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
/// With no round it shows the icon only. During a round its title is the
/// short product name and the capture count, for example "Nshot (2)".
///
/// The menu is rebuilt each time it opens. It lists the active round's
/// actions, the active round and the last ended rounds under "Recent", and a basket of checked
/// captures. The basket lines sit below the Recent rows, so checking a box
/// never moves a row above it and an open submenu stays lined up with its
/// parent row. Each round row opens a submenu. A submenu fills when it
/// opens, so thumbnails decode only for the round being looked at.
@MainActor
final class FeedbackStatusItem: NSObject, NSMenuDelegate {
    var stateProvider: (() -> FeedbackMenuState)?

    var onCopyPromptAndEndRound: (() -> Void)?
    var onCopyLastCapture: (() -> Void)?
    var onOpenFolder: (() -> Void)?
    var onEndRound: (() -> Void)?
    var onShowShortcut: (() -> Void)?
    var onShowSettings: (() -> Void)?

    var onStartRound: (() -> Void)?
    var onOpenAllRounds: (() -> Void)?
    var onCopySelected: (() -> Void)?
    var onClearSelection: (() -> Void)?
    var onToggleCapture: ((FeedbackBasketKey) -> Void)?
    var onQuickLook: ((FeedbackBasketKey) -> Void)?
    var onCopyRecentRound: ((FeedbackRound) -> Void)?
    var onOpenRecentFolder: ((FeedbackRound) -> Void)?
    var onResumeRound: ((FeedbackRound) -> Void)?

    /// One round line in the open menu.
    private struct RoundRow {
        var item: NSMenuItem
        var menu: NSMenu
        var round: FeedbackRound
    }

    private var item: NSStatusItem?
    private var topMenu: NSMenu?
    private var roundRows: [RoundRow] = []
    private var copySelectedItem: NSMenuItem?
    private var clearSelectionItem: NSMenuItem?
    private var basketSeparator: NSMenuItem?
    private var allRoundsItem: NSMenuItem?

    /// Made once and added again on each rebuild. `setShortcut(for:)` adds a
    /// notification observer that nothing removes, so a new item on every menu
    /// open would leave one more observer and one more item behind.
    private lazy var startRoundItem: NSMenuItem = shortcutItem(
        "Start Round", action: #selector(startRound), name: .feedbackCapture
    )

    /// The active round's rows, made once for the same reason. Each shows its
    /// hotkey on the right (Drew, 2026-10-24).
    private lazy var copyLastCaptureItem: NSMenuItem = shortcutItem(
        "Copy Last Capture Prompt", action: #selector(copyLastCapture), name: .feedbackCopyLastCapture
    )
    private lazy var copyPromptAndEndRoundItem: NSMenuItem = shortcutItem(
        "Copy Prompt and End Round", action: #selector(copyPromptAndEndRound), name: .feedbackCopyPromptAndEndRound
    )
    private lazy var openRoundFolderItem: NSMenuItem = shortcutItem(
        "Open Round Folder", action: #selector(openFolder), name: .feedbackOpenRoundFolder
    )
    private lazy var endRoundItem: NSMenuItem = shortcutItem(
        "End Round", action: #selector(endRound), name: .feedbackEndRound
    )

    /// Never removes the item. The title and the green dot on the mark show
    /// only during a round, and both go in the same update.
    func update(round: FeedbackRound?) {
        let item = self.item ?? makeItem()
        self.item = item
        guard let button = item.button else { return }
        if let round {
            let count = round.captures.count
            button.title = " \(ForkBranding.shortName) (\(count))"
            button.imagePosition = .imageLeading
            // The dot is a picture, so say in words that a round is active.
            button.setAccessibilityLabel(
                "\(ForkBranding.name) feedback, round active, \(count) \(count == 1 ? "capture" : "captures")"
            )
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(nil)
        }
        FeedbackRoundDot.setActive(round != nil, on: button)
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
        for row in roundRows {
            row.item.subtitle = FeedbackLibrary.subtitle(
                for: row.round,
                selectedCount: basket.count(inFolder: row.round.folderName)
            )
        }
    }

    private func currentState() -> FeedbackMenuState {
        stateProvider?() ?? .empty
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = ForkBranding.menuBarMark(
            description: "\(ForkBranding.name) feedback round",
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
        } else if let row = roundRows.first(where: { $0.menu === menu }) {
            fillSubmenu(row.menu, for: row.round)
        }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        let state = currentState()
        menu.removeAllItems()
        roundRows = []
        copySelectedItem = nil
        clearSelectionItem = nil
        basketSeparator = nil
        allRoundsItem = nil

        // The running build comes first, so anyone can tell builds apart.
        menu.addItem(grayLine(ForkBranding.versionLine))
        menu.addItem(.separator())

        if let active = state.active {
            menu.addItem(grayLine("Round: \(active.slug)"))
            menu.addItem(.separator())
            for item in [copyLastCaptureItem, copyPromptAndEndRoundItem, openRoundFolderItem, endRoundItem] {
                addReused(item, to: menu)
            }
        } else {
            menu.addItem(grayLine("No active round"))
            addReused(startRoundItem, to: menu)
        }
        menu.addItem(.separator())

        // The active round leads Recent, with the same row and submenu as an
        // ended round, so its captures can be checked and copied mid-round
        // (Drew, 2026-10-24). A round with no capture yet has nothing to list.
        // The filter keeps it from showing twice if the provider ever lists it.
        var recent: [FeedbackRound] = []
        if let active = state.active, !active.captures.isEmpty {
            recent.append(active)
        }
        recent += state.recent.filter { $0.folderName != state.active?.folderName }
        if !recent.isEmpty {
            menu.addItem(.sectionHeader(title: "Recent"))
            let now = Date()
            for round in recent {
                let row = makeRoundRow(round, now: now, basket: state.basket)
                roundRows.append(row)
                menu.addItem(row.item)
            }
            menu.addItem(.separator())
        }

        let allRounds = menuItem("All Rounds...", action: #selector(openAllRounds))
        allRoundsItem = allRounds
        menu.addItem(allRounds)
        menu.addItem(menuItem("Change Start Round Shortcut...", action: #selector(showShortcut)))
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

    private func makeRoundRow(_ round: FeedbackRound, now: Date, basket: FeedbackBasket) -> RoundRow {
        let title = FeedbackLibrary.title(startedAt: round.startedAt, now: now, timeZone: .current)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.subtitle = FeedbackLibrary.subtitle(
            for: round,
            selectedCount: basket.count(inFolder: round.folderName)
        )

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self
        // A placeholder, so the submenu is never empty before it first opens.
        // menuNeedsUpdate replaces it before anything shows.
        submenu.addItem(grayLine("Loading..."))
        item.submenu = submenu
        return RoundRow(item: item, menu: submenu, round: round)
    }

    // MARK: - Basket lines

    private static func copySelectedTitle(_ count: Int) -> String {
        "Copy \(count) Selected"
    }

    /// The basket lines sit below the Recent rows: a separator, Copy N
    /// Selected, and Clear Selection, in front of the separator that comes
    /// before "All Rounds...". Nothing above that point moves, so a round
    /// submenu that is open stays lined up with its parent row. With no Recent
    /// rows (a basket entry can outlive the Recent list), the lines sit in
    /// front of that same separator, under the round actions.
    private func insertBasketItems(into menu: NSMenu, count: Int) {
        guard let allRoundsItem, allRoundsItem.menu === menu else { return }
        let anchor = menu.index(of: allRoundsItem) - 1
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

    // MARK: - Round submenu

    /// Runs each time the submenu opens. Rows are new each time, so a row
    /// always starts with the current basket state.
    private func fillSubmenu(_ menu: NSMenu, for listed: FeedbackRound) {
        let state = currentState()
        // Prefer the freshly read round, so the active round shows a capture
        // saved since the menu opened. Fall back to the one the row was built from.
        let fresh = (state.active.map { [$0] } ?? []) + state.recent
        let round = fresh.first { $0.folderName == listed.folderName } ?? listed
        let folderURL = state.rootURL.appendingPathComponent(round.folderName, isDirectory: true)

        menu.removeAllItems()
        menu.addItem(menuItem("Copy Round Prompt", action: #selector(copyRecentRound(_:)), round: round))
        menu.addItem(.separator())

        for capture in round.captures {
            let key = FeedbackBasketKey(folderName: round.folderName, captureIndex: capture.index)
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
        menu.addItem(menuItem("Open Folder", action: #selector(openRecentFolder(_:)), round: round))
        // Only one round can be active, so Resume waits until it ends.
        if state.active == nil {
            menu.addItem(menuItem("Resume Round", action: #selector(resumeRound(_:)), round: round))
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

    private func menuItem(_ title: String, action: Selector, round: FeedbackRound? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = round
        return item
    }

    /// No action and not enabled, so the menu shows it gray and it cannot be chosen.
    private func grayLine(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A row that shows its hotkey on the right, in the standard gray. It is
    /// the same call the main menu uses, so a changed shortcut shows here.
    private func shortcutItem(_ title: String, action: Selector, name: KeyboardShortcuts.Name) -> NSMenuItem {
        let item = menuItem(title, action: action)
        item.setShortcut(for: name)
        return item
    }

    /// Adds an item that is made once. An item can sit in one menu only, so
    /// take it out of the old one.
    private func addReused(_ item: NSMenuItem, to menu: NSMenu) {
        item.menu?.removeItem(item)
        menu.addItem(item)
    }

    @objc private func copyPromptAndEndRound() { onCopyPromptAndEndRound?() }
    @objc private func copyLastCapture() { onCopyLastCapture?() }
    @objc private func openFolder() { onOpenFolder?() }
    @objc private func endRound() { onEndRound?() }
    @objc private func showShortcut() { onShowShortcut?() }
    @objc private func showSettings() { onShowSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func startRound() { onStartRound?() }
    @objc private func openAllRounds() { onOpenAllRounds?() }
    @objc private func copySelected() { onCopySelected?() }
    @objc private func clearSelection() { onClearSelection?() }

    @objc private func copyRecentRound(_ sender: NSMenuItem) {
        if let round = sender.representedObject as? FeedbackRound { onCopyRecentRound?(round) }
    }

    @objc private func openRecentFolder(_ sender: NSMenuItem) {
        if let round = sender.representedObject as? FeedbackRound { onOpenRecentFolder?(round) }
    }

    @objc private func resumeRound(_ sender: NSMenuItem) {
        if let round = sender.representedObject as? FeedbackRound { onResumeRound?(round) }
    }
}
