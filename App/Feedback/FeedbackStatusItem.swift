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
    /// Shows Zip Round and Zip N Selected (`zipHandoff` flag, #85).
    var zipEnabled = false
    var supportSubmissionEnabled = false
    /// Rounds that another copy of Nextshot saved under a newer schema. This
    /// copy hides them, so the menu says how many.
    var newerSchemaCount = 0
    /// Ended rounds beyond Recent's five, grouped under Show More.
    var older: [FeedbackRound] = []

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
/// actions, the active round and the last ended rounds under "Recent Rounds", and a basket of checked
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
    var onZipSelected: (() -> Void)?
    var onClearSelection: (() -> Void)?
    var onToggleCapture: ((FeedbackBasketKey) -> Void)?
    var onQuickLook: ((FeedbackBasketKey) -> Void)?
    var onCopyRecentRound: ((FeedbackRound) -> Void)?
    var onZipRecentRound: ((FeedbackRound) -> Void)?
    var onSubmitRecentRound: ((FeedbackRound) -> Void)?
    var onOpenRecentFolder: ((FeedbackRound) -> Void)?
    var onResumeRound: ((FeedbackRound) -> Void)?

    /// One round line in the open menu.
    private struct RoundRow {
        var item: NSMenuItem
        var menu: NSMenu
        var round: FeedbackRound
        var active: Bool
    }

    private struct HistoryGroup {
        var menu: NSMenu
        var rounds: [FeedbackRound]
    }

    private var item: NSStatusItem?
    private var topMenu: NSMenu?
    private var roundRows: [RoundRow] = []
    private var historyGroups: [HistoryGroup] = []
    /// Shared by group headings and rows created later during menu tracking.
    private var menuDate = Date()
    private var copySelectedItem: NSMenuItem?
    private var zipSelectedItem: NSMenuItem?
    private var clearSelectionItem: NSMenuItem?
    private var basketSeparator: NSMenuItem?
    private var allRoundsItem: NSMenuItem?
    /// The `zipEnabled` of the last rebuild. The basket lines read it, so a
    /// checkbox click reads no flag.
    private var zipEnabled = false
    /// Kept while the Share menu shows.
    private var sharePicker: NSSharingServicePicker?

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
            zipSelectedItem?.title = Self.zipSelectedTitle(count)
        } else {
            insertBasketItems(into: menu, count: count)
        }
        for row in roundRows {
            Self.updateRoundSubtitle(
                row.item,
                round: row.round,
                active: row.active,
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
        } else if let group = historyGroups.first(where: { $0.menu === menu }) {
            fillHistoryGroup(menu, rounds: group.rounds)
        } else if let row = roundRows.first(where: { $0.menu === menu }) {
            fillSubmenu(row.menu, for: row.round)
        }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        let state = currentState()
        menu.removeAllItems()
        roundRows = []
        historyGroups = []
        menuDate = Date()
        copySelectedItem = nil
        zipSelectedItem = nil
        clearSelectionItem = nil
        basketSeparator = nil
        allRoundsItem = nil
        zipEnabled = state.zipEnabled

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
            menu.addItem(.sectionHeader(title: "Recent Rounds"))
            for round in recent {
                let active = round.folderName == state.active?.folderName
                let row = makeRoundRow(round, active: active, now: menuDate, basket: state.basket)
                roundRows.append(row)
                menu.addItem(row.item)
            }
        }
        addHistory(to: menu, state: state)
        // A round from a newer copy is never opened or saved here, so it
        // cannot lose fields this copy does not know. Say why it is missing.
        if state.newerSchemaCount > 0 {
            let count = state.newerSchemaCount
            menu.addItem(grayLine("\(count) \(count == 1 ? "round was" : "rounds were") saved by a newer \(ForkBranding.name) and \(count == 1 ? "is" : "are") hidden"))
        }
        if !recent.isEmpty || !historyGroups.isEmpty || state.newerSchemaCount > 0 {
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

    // MARK: - Older rounds

    private func addHistory(to menu: NSMenu, state: FeedbackMenuState) {
        let rounds = state.older.filter { $0.folderName != state.active?.folderName }
        let groups = FeedbackHistory.groups(rounds, now: menuDate, calendar: .current, locale: .current)
        guard !groups.isEmpty else { return }

        let more = NSMenuItem(title: "Show More", action: nil, keyEquivalent: "")
        let history = NSMenu()
        history.autoenablesItems = false
        for group in groups {
            let item = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            submenu.delegate = self
            submenu.addItem(grayLine("Loading..."))
            item.submenu = submenu
            history.addItem(item)
            historyGroups.append(HistoryGroup(menu: submenu, rounds: group.rounds))
        }
        more.submenu = history
        menu.addItem(more)
    }

    private func fillHistoryGroup(_ menu: NSMenu, rounds: [FeedbackRound]) {
        // Release prior row records before replacing their menu items.
        roundRows.removeAll { $0.item.menu === menu }
        menu.removeAllItems()
        let basket = currentState().basket
        for round in rounds {
            let row = makeRoundRow(round, active: false, now: menuDate, basket: basket)
            roundRows.append(row)
            menu.addItem(row.item)
        }
    }

    private func makeRoundRow(_ round: FeedbackRound, active: Bool, now: Date, basket: FeedbackBasket) -> RoundRow {
        let title = FeedbackLibrary.title(startedAt: round.startedAt, now: now, timeZone: .current)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        Self.updateRoundSubtitle(
            item,
            round: round,
            active: active,
            selectedCount: basket.count(inFolder: round.folderName)
        )
        if active {
            // The green dot of the menu bar mark and the help box, in the
            // state column, so the row's text stays lined up with the others.
            item.onStateImage = FeedbackRoundDot.menuImage
            item.state = .on
        }

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self
        // A placeholder, so the submenu is never empty before it first opens.
        // menuNeedsUpdate replaces it before anything shows.
        submenu.addItem(grayLine("Loading..."))
        item.submenu = submenu
        return RoundRow(item: item, menu: submenu, round: round, active: active)
    }

    /// Reserve the counts and active prefix before fitting the app names.
    /// Measure with the menu font and leave room for menu margins and arrows.
    private static func updateRoundSubtitle(_ item: NSMenuItem, round: FeedbackRound, active: Bool, selectedCount: Int) {
        let prefix = active ? "Active round, " : ""
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
        let maximumWidth: CGFloat = 240
        var subtitle = prefix + FeedbackLibrary.subtitle(for: round, selectedCount: selectedCount)
        let longestName = round.captures.compactMap(\.sourceApp).map(\.count).max() ?? 1
        for limit in stride(from: longestName, through: 1, by: -1) {
            if (subtitle as NSString).size(withAttributes: attributes).width <= maximumWidth { break }
            subtitle = prefix + FeedbackLibrary.subtitle(for: round, selectedCount: selectedCount, appNameLimit: limit)
        }
        item.subtitle = subtitle
        item.toolTip = prefix + FeedbackLibrary.fullSubtitle(for: round, selectedCount: selectedCount)
    }

    // MARK: - Basket lines

    private static func copySelectedTitle(_ count: Int) -> String {
        "Copy \(count) Selected"
    }

    private static func zipSelectedTitle(_ count: Int) -> String {
        "Zip \(count) Selected"
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
        // Fork: Zip N Selected sits right below Copy N Selected (#85).
        let zip = zipEnabled ? menuItem(Self.zipSelectedTitle(count), action: #selector(zipSelected)) : nil
        let clear = menuItem("Clear Selection", action: #selector(clearSelection))
        let separator = NSMenuItem.separator()
        let lines = [separator, copy, zip, clear].compactMap { $0 }
        for (offset, line) in lines.enumerated() {
            menu.insertItem(line, at: anchor + offset)
        }
        copySelectedItem = copy
        zipSelectedItem = zip
        clearSelectionItem = clear
        basketSeparator = separator
    }

    private func removeBasketItems(from menu: NSMenu) {
        for item in [copySelectedItem, zipSelectedItem, clearSelectionItem, basketSeparator] {
            if let item, item.menu === menu {
                menu.removeItem(item)
            }
        }
        copySelectedItem = nil
        zipSelectedItem = nil
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
        let fresh = (state.active.map { [$0] } ?? []) + state.recent + state.older
        let round = fresh.first { $0.folderName == listed.folderName } ?? listed
        let folderURL = state.rootURL.appendingPathComponent(round.folderName, isDirectory: true)

        menu.removeAllItems()
        menu.addItem(menuItem("Copy Round Prompt", action: #selector(copyRecentRound(_:)), round: round))
        if state.zipEnabled {
            menu.addItem(menuItem("Zip Round", action: #selector(zipRecentRound(_:)), round: round))
        }
        if state.supportSubmissionEnabled {
            menu.addItem(menuItem("Submit Round to Nextshot…", action: #selector(submitRecentRound(_:)), round: round))
        }
        menu.addItem(.separator())

        for capture in FeedbackLibrary.capturesNewestFirst(round) {
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

    /// The macOS Share menu for a zip, at the Nshot button (#85). It shows
    /// once the run loop is back in its default mode, so never inside menu
    /// tracking.
    func showSharePicker(for url: URL) {
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let button = self.item?.button else { return }
                let picker = NSSharingServicePicker(items: [url])
                self.sharePicker = picker
                picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
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
    @objc private func submitRecentRound(_ sender: NSMenuItem) {
        if let round = sender.representedObject as? FeedbackRound { onSubmitRecentRound?(round) }
    }

    @objc private func zipSelected() { onZipSelected?() }
    @objc private func clearSelection() { onClearSelection?() }

    @objc private func copyRecentRound(_ sender: NSMenuItem) {
        if let round = sender.representedObject as? FeedbackRound { onCopyRecentRound?(round) }
    }

    @objc private func zipRecentRound(_ sender: NSMenuItem) {
        if let round = sender.representedObject as? FeedbackRound { onZipRecentRound?(round) }
    }

    @objc private func openRecentFolder(_ sender: NSMenuItem) {
        if let round = sender.representedObject as? FeedbackRound { onOpenRecentFolder?(round) }
    }

    @objc private func resumeRound(_ sender: NSMenuItem) {
        if let round = sender.representedObject as? FeedbackRound { onResumeRound?(round) }
    }
}
