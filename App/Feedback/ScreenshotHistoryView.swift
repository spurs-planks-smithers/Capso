import AppKit
import ImageIO
import Observation
import SwiftUI

@MainActor
@Observable
final class ScreenshotHistoryPresentation {
    var items: [ScreenshotHistoryItem] = []
}

@MainActor
struct ScreenshotHistoryView: View {
    let presentation: ScreenshotHistoryPresentation
    let onCopy: (ScreenshotHistoryItem, ScreenshotImageVariant) -> Void
    let onPreview: (ScreenshotHistoryItem) -> Void
    let onAnnotate: (ScreenshotHistoryItem) -> Void

    @State private var appFilter: String?
    @State private var selection: ScreenshotSourceID?

    private var items: [ScreenshotHistoryItem] {
        presentation.items.filter { appFilter == nil || appName($0) == appFilter }
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.id.sortKey < $1.id.sortKey }
                return $0.createdAt > $1.createdAt
            }
    }

    private var apps: [String] {
        Array(Set(presentation.items.map(appName))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var selectedItem: ScreenshotHistoryItem? {
        items.first { $0.id == selection }
    }

    private var groups: [(date: Date, items: [ScreenshotHistoryItem])] {
        let grouped = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(groups, id: \.date) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(group.date.formatted(date: .complete, time: .omitted))
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245, maximum: 340), spacing: 16)], spacing: 16) {
                                    ForEach(group.items) { item in
                                        card(item)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            Divider()
            selectionBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: appFilter) { _, _ in selection = nil }
        .onChange(of: presentation.items.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Screenshot History").font(.system(size: 20, weight: .semibold))
                Text("\(items.count) images from screenshots and feedback rounds")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Captured app", selection: $appFilter) {
                Text("All Apps").tag(String?.none)
                ForEach(apps, id: \.self) { app in
                    Text(app).tag(Optional(app))
                }
            }
            .frame(width: 250)
            .help("Filter by the app shown when the screenshot was captured.")
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36)).foregroundStyle(.secondary)
            Text(presentation.items.isEmpty ? "No screenshots yet" : "No screenshots from this app")
                .font(.headline)
            Text(presentation.items.isEmpty
                 ? "Capture an area with Option+Shift+4. Saved feedback captures also appear here."
                 : "Choose All Apps to see the rest of your history.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ item: ScreenshotHistoryItem) -> some View {
        let selected = selection == item.id
        return VStack(alignment: .leading, spacing: 9) {
            ScreenshotHistoryThumbnail(url: item.thumbnailURL ?? item.annotatedURL)
                .frame(height: 145)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            HStack {
                Text(appName(item)).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 6)
                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary).fixedSize()
            }
            Text(title(item)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            HStack {
                Text(sourceName(item))
                Spacer()
                Text("\(item.size.width) × \(item.size.height)")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .padding(10)
        .background(selected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .focusable()
        .onKeyPress(.space) {
            selection = item.id
            onPreview(item)
            return .handled
        }
        .onKeyPress(.return) {
            selection = item.id
            return .handled
        }
        .onTapGesture(count: 2) { selection = item.id; onPreview(item) }
        .onTapGesture { selection = item.id }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appName(item)), \(title(item)), \(item.createdAt.formatted(date: .complete, time: .shortened))")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { selection = item.id }
        .accessibilityAction(named: "Preview") { onPreview(item) }
        .help("\(title(item))\nCreated: \(timestamp(item.createdAt))\nCaptured: \(timestamp(item.capturedAt))\nDouble-click to preview.")
        .contextMenu {
            Button("Copy Image") { onCopy(item, .annotated) }
            Button("Copy Without Annotations") { onCopy(item, .withoutAnnotations) }
                .disabled(item.cleanURL == nil)
            Divider()
            Button("Preview") { onPreview(item) }
            Button("Annotate") { onAnnotate(item) }
        }
    }

    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let item = selectedItem {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(item)).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                        Text("Created \(timestamp(item.createdAt))")
                            .font(.caption).foregroundStyle(.secondary)
                        if item.createdAt != item.capturedAt {
                            Text("Originally captured \(timestamp(item.capturedAt))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Button("Preview") { onPreview(item) }
                    Button("Annotate") { onAnnotate(item) }
                    Button("Copy Image") { onCopy(item, .annotated) }
                        .keyboardShortcut("c", modifiers: .command)
                    Button("Copy Without Annotations") { onCopy(item, .withoutAnnotations) }
                        .disabled(item.cleanURL == nil)
                        .help(item.cleanURL == nil ? "A reliable image without annotations is unavailable for this capture." : "Copy without marks. Keep redactions.")
                }
                if item.cleanURL == nil {
                    Text("Copy Without Annotations is unavailable. This capture has no verified clean image.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Select a screenshot to copy or annotate. Double-click to preview.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(minHeight: 78, alignment: .leading)
    }

    private func appName(_ item: ScreenshotHistoryItem) -> String {
        nonempty(item.appName) ?? "Unknown App"
    }

    private func title(_ item: ScreenshotHistoryItem) -> String {
        nonempty(item.windowTitle) ?? "n/a"
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func timestamp(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().timeZone(.genericName(.short)))
    }

    private func sourceName(_ item: ScreenshotHistoryItem) -> String {
        switch item.id {
        case .local: return item.metadata.parent == nil ? "Screenshot" : "Edited version"
        case .round: return "Feedback round"
        }
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
