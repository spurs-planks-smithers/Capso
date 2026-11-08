import AppKit
import FeedbackKit
import ImageIO
import Observation
import SwiftUI

/// Fork: what the Find Capture window shows (#125). The controller owns the
/// checks. The window gets a read-only copy each time they change.
@MainActor
@Observable
final class ScreenshotHistoryPresentation {
    private(set) var items: [ScreenshotHistoryItem] = []
    /// The items with their folded search text, made once per load.
    private(set) var entries: [CaptureSearch.Entry<ScreenshotHistoryItem>] = []
    /// False until the first load ends.
    private(set) var loaded = false
    /// Rises with each load, so the view can drop a filter that no item matches.
    private(set) var revision = 0
    /// The Nshot menu's checks.
    var basket = FeedbackBasket()
    var zipEnabled = false
    /// A round is active, so Resume Round stays hidden.
    var roundActive = false
    /// Raised when the menu's search field opens the window, so the app and
    /// round filters reset and its query searches every capture.
    var filterResetRequest = 0

    func setItems(_ items: [ScreenshotHistoryItem]) {
        self.items = items
        entries = items.map { item in
            CaptureSearch.Entry(
                value: item,
                date: item.createdAt,
                tieBreak: item.id.sortKey,
                fields: CaptureSearch.Fields(
                    appName: item.appName, windowTitle: item.windowTitle, marks: item.marks,
                    note: item.note, roundName: item.roundName, captureName: item.captureName
                )
            )
        }
        loaded = true
        revision &+= 1
    }
}

/// Fork: Find Capture (#125). A search field, the app filter, and every saved
/// capture grouped by day, newest first. A click on a card checks it in the
/// Nshot menu's checks. A click on a round chip shows only that round.
@MainActor
struct ScreenshotHistoryView: View {
    let presentation: ScreenshotHistoryPresentation
    let actions: FindCaptureActions
    /// The pointer entered (true) or left (false) a card. The window shows
    /// the large preview after a short rest (#125, Drew, 2026-11-08).
    var onHover: (ScreenshotHistoryItem, Bool) -> Void = { _, _ in }

    private enum Focus: Hashable {
        case search
        case grid
    }

    @State private var query = ""
    @State private var appFilter: String?
    /// The round folder that a chip click picked, or nil for every round.
    @State private var roundFilter: String?
    /// The card that Space opens in Quick Look.
    @State private var lastClicked: ScreenshotSourceID?
    @FocusState private var focus: Focus?

    /// The entries inside the round and app filters, before the search.
    private var scoped: [CaptureSearch.Entry<ScreenshotHistoryItem>] {
        presentation.entries.filter { entry in
            (roundFilter == nil || entry.value.id.basketKey?.folderName == roundFilter)
                && (appFilter == nil || appName(entry.value) == appFilter)
        }
    }

    private var apps: [String] {
        Array(Set(presentation.items.map(appName))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        let results = CaptureSearch.results(scoped, query: query)
        VStack(spacing: 0) {
            header(count: results.count)
            Divider()
            if !presentation.loaded {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                emptyState
            } else {
                grid(results)
            }
            Divider()
            bar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // The panel gives the search field focus at each show
        // (`ScreenshotHistoryPanel.focusSearch`), so the caret can end after a
        // query from the menu.
        .onChange(of: presentation.revision) { _, _ in dropStaleFilters() }
        .onChange(of: presentation.filterResetRequest) { _, _ in
            appFilter = nil
            roundFilter = nil
        }
    }

    /// A reload can remove the last capture of the chosen app or round. The
    /// filter then goes, so the list never turns empty with no visible cause.
    /// A round filter that goes returns the bar to selection mode.
    private func dropStaleFilters() {
        if let appFilter, !presentation.items.contains(where: { appName($0) == appFilter }) {
            self.appFilter = nil
        }
        if let roundFilter, !presentation.items.contains(where: { $0.id.basketKey?.folderName == roundFilter }) {
            self.roundFilter = nil
        }
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TextField("Search", text: $query, prompt: Text("Search apps, windows, notes, and rounds"))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focus, equals: .search)
                Picker("Captured app", selection: $appFilter) {
                    Text("All Apps").tag(String?.none)
                    ForEach(apps, id: \.self) { app in
                        Text(app).tag(Optional(app))
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .help("Show the captures of one app.")
            }
            Text(count == 1 ? "1 capture" : "\(count) captures")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32)).foregroundStyle(.secondary)
            Text(presentation.items.isEmpty ? "No captures yet" : "No captures match")
                .font(.headline)
            Text(presentation.items.isEmpty
                 ? "Captures that you save to a round show here."
                 : "Change the search, or choose All Apps.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grid(_ results: [ScreenshotHistoryItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(groups(results), id: \.date) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.date.formatted(date: .complete, time: .omitted))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 16)], spacing: 16) {
                            ForEach(group.items) { item in
                                card(item)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        // A card click moves focus here, so Space opens Quick Look and does
        // not type into the search field.
        .focusable()
        .focused($focus, equals: .grid)
        .focusEffectDisabled()
        // Only a card that the filters and the search still show opens.
        .onKeyPress(.space) {
            if let item = results.first(where: { $0.id == lastClicked }) {
                actions.quickLook(item.annotatedURL)
            } else {
                NSSound.beep()
            }
            return .handled
        }
    }

    /// Day groups, newest day first. Each group keeps the result order.
    private func groups(_ results: [ScreenshotHistoryItem]) -> [(date: Date, items: [ScreenshotHistoryItem])] {
        let grouped = Dictionary(grouping: results) { Calendar.current.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private func card(_ item: ScreenshotHistoryItem) -> some View {
        let key = item.id.basketKey
        let checked = key.map(presentation.basket.contains) ?? false
        let lastClick = lastClicked == item.id
        return VStack(alignment: .leading, spacing: 8) {
            ScreenshotHistoryThumbnail(url: item.thumbnailURL ?? item.annotatedURL)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(alignment: .topTrailing) {
                    if key != nil {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
            HStack {
                Text(appName(item)).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 6)
                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary).fixedSize()
            }
            Text(captureName(item)).lineLimit(1).truncationMode(.tail)
            chip(item)
        }
        .font(.system(size: 12))
        .padding(10)
        .background(checked ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(
                checked ? Color.accentColor : Color.primary.opacity(lastClick ? 0.35 : 0.10),
                lineWidth: checked ? 2 : 1
            )
        )
        .contentShape(Rectangle())
        .onHover { inside in onHover(item, inside) }
        .onTapGesture { click(item) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appName(item)), \(captureName(item)), \(item.createdAt.formatted(date: .complete, time: .shortened))")
        .accessibilityAddTraits(checked ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { click(item) }
        .accessibilityAction(named: "Quick Look") { actions.quickLook(item.annotatedURL) }
        .accessibilityAction(named: "Show This Round") {
            if let folder = key?.folderName { roundFilter = folder }
        }
        .help(key == nil
              ? "\(captureName(item))\nPress Space for Quick Look."
              : "\(captureName(item))\nClick to check. Press Space for Quick Look.")
    }

    /// The round chip. A click shows only that round. A screenshot has no
    /// round, so its chip is a plain label.
    @ViewBuilder
    private func chip(_ item: ScreenshotHistoryItem) -> some View {
        if let folder = item.id.basketKey?.folderName {
            Button {
                roundFilter = folder
            } label: {
                Text(item.roundName ?? folder)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(roundFilter == folder ? 0.22 : 0.12)))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Show only the captures of this round.")
        } else {
            Text(item.metadata.parent == nil ? "Screenshot" : "Edited version")
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .foregroundStyle(.secondary)
        }
    }

    private var bar: some View {
        let model = FindCaptureBar(
            roundName: roundFilter.map(roundLabel),
            selectedCount: presentation.basket.count,
            zipEnabled: presentation.zipEnabled,
            roundActive: presentation.roundActive
        )
        let leading = model.buttons.filter { $0.action == .back }
        let trailing = model.buttons.filter { $0.action != .back }
        return HStack(spacing: 10) {
            ForEach(leading, id: \.action) { button($0) }
            Text(model.label).fontWeight(.medium).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            ForEach(trailing, id: \.action) { button($0) }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func button(_ model: FindCaptureBar.Button) -> some View {
        Button(model.title) { perform(model.action) }
            .disabled(!model.isEnabled)
    }

    private func perform(_ action: FindCaptureBar.Action) {
        switch action {
        case .copySelected: actions.copySelected()
        case .zipSelected: actions.zipSelected()
        case .clearSelection: actions.clearSelection()
        case .back: roundFilter = nil
        case .copyRoundPrompt: if let roundFilter { actions.copyRoundPrompt(roundFilter) }
        case .zipRound: if let roundFilter { actions.zipRound(roundFilter) }
        case .openFolder: if let roundFilter { actions.openFolder(roundFilter) }
        case .resumeRound: if let roundFilter { actions.resumeRound(roundFilter) }
        }
    }

    private func click(_ item: ScreenshotHistoryItem) {
        lastClicked = item.id
        focus = .grid
        if let key = item.id.basketKey { actions.toggle(key) }
    }

    /// The name the round's chips show, else its folder name.
    private func roundLabel(_ folder: String) -> String {
        presentation.items.first { $0.id.basketKey?.folderName == folder }?.roundName ?? folder
    }

    private func appName(_ item: ScreenshotHistoryItem) -> String {
        nonempty(item.appName) ?? "Unknown App"
    }

    /// The summary name or first instruction, else the window title.
    private func captureName(_ item: ScreenshotHistoryItem) -> String {
        nonempty(item.captureName) ?? nonempty(item.windowTitle) ?? "n/a"
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

@MainActor
private struct ScreenshotHistoryThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                Label("Preview unavailable", systemImage: "photo")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) {
            image = nil
            failed = false
            let thumbnail = await ScreenshotThumbnailCache.shared.load(url)
            guard !Task.isCancelled else { return }
            if let thumbnail {
                image = NSImage(cgImage: thumbnail, size: .zero)
            } else {
                failed = true
            }
        }
    }
}

/// Decode bounded thumbnails away from the main actor. Round images remain references.
private actor ScreenshotThumbnailCache {
    static let shared = ScreenshotThumbnailCache()
    private let cache = NSCache<NSURL, CGImage>()

    init() {
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 120
    }

    func load(_ url: URL) -> CGImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        cache.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        return image
    }
}
