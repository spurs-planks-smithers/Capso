// App/Feedback/FeedbackHoverPreview.swift
import AppKit
import FeedbackKit
import ImageIO

/// Fork: the large preview of a capture row (#265). The pointer rests on a
/// row in a round's submenu for `HoverPreviewPolicy.delay`, then a borderless
/// panel shows the annotated image beside the submenu. It stays until the
/// pointer leaves the row, the submenu closes, or the row is clicked for
/// Quick Look.
///
/// The panel takes no clicks, never becomes key, and stays out of screenshots
/// (`sharingType = .none`). It reads one local file and opens no connection.
///
/// The Find Capture window (#125, Drew, 2026-11-08) uses a second instance:
/// the pointer rests on a card for `HoverPreviewPolicy.windowDelay`, and the
/// preview shows large, centered on the window.
@MainActor
final class FeedbackHoverPreview {
    /// Where the preview goes. Frames are in screen points.
    enum Placement {
        /// Beside a menu, centered on the hovered row.
        case besideMenu(row: NSRect, menu: NSRect)
        /// Centered on a window, sized to the window less its margins.
        case centered(on: NSRect)
    }

    private let delay: HoverDelay
    private var panel: NSPanel?
    private var imageView: NSImageView?
    /// The row or card the pointer is on. A late exit from an old one is ignored.
    private var currentKey: AnyHashable?

    init(delay: TimeInterval = HoverPreviewPolicy.delay) {
        self.delay = HoverDelay(delay: delay)
    }
    /// Counts hovers, so a decode that finishes late shows nothing.
    private var generation = 0
    private var decodeTask: Task<Void, Never>?
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 8
        return cache
    }()

    /// The pointer entered a row. `rowFrame` and `menuFrame` are in screen points.
    func begin(key: FeedbackBasketKey, imageURL: URL, rowFrame: NSRect, menuFrame: NSRect, screen: NSScreen?) {
        begin(key: key, imageURL: imageURL, placement: .besideMenu(row: rowFrame, menu: menuFrame), screen: screen)
    }

    /// The pointer entered a row or a card.
    func begin(key: AnyHashable, imageURL: URL, placement: Placement, screen: NSScreen?) {
        endAll()
        currentKey = key
        generation += 1
        let generation = generation
        delay.start { [weak self] in
            self?.show(generation: generation, imageURL: imageURL, placement: placement, screen: screen)
        }
    }

    /// A click on the row. A preview that has not shown yet is dropped. One
    /// that shows stays until the pointer leaves.
    func cancelPending(key: AnyHashable) {
        guard key == currentKey, panel == nil else { return }
        delay.cancel()
        decodeTask?.cancel()
        decodeTask = nil
        generation += 1
    }

    /// The pointer left a row. Does nothing when the pointer already entered another.
    func end(key: AnyHashable) {
        guard key == currentKey else { return }
        endAll()
    }

    /// Hides the preview and drops any pending one.
    func endAll() {
        delay.cancel()
        decodeTask?.cancel()
        decodeTask = nil
        generation += 1
        currentKey = nil
        panel?.orderOut(nil)
    }

    // MARK: - Show

    private func show(generation: Int, imageURL: URL, placement: Placement, screen: NSScreen?) {
        guard generation == self.generation else { return }
        let anchor: NSRect
        switch placement {
        case .besideMenu(_, let menu): anchor = menu
        case .centered(let window): anchor = window
        }
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? anchor.insetBy(dx: -800, dy: -600)
        let box: CGSize
        switch placement {
        case .besideMenu: box = HoverPreviewPolicy.box(on: visible)
        case .centered(let window): box = HoverPreviewPolicy.box(over: window, on: visible)
        }
        let scale = screen?.backingScaleFactor ?? 2

        if let cached = cachedImage(for: imageURL) {
            present(cached, placement: placement, visible: visible, box: box)
            return
        }
        // Decode off the main thread. A capture can be several megabytes.
        let maxPixel = Int(max(box.width, box.height) * scale)
        decodeTask = Task { [weak self] in
            let decoded = await Task.detached(priority: .userInitiated) {
                Self.decode(imageURL, maxPixel: maxPixel, scale: scale)
            }.value
            guard !Task.isCancelled, let self, let decoded, generation == self.generation else { return }
            self.store(decoded.image, for: imageURL)
            self.present(decoded.image, placement: placement, visible: visible, box: box)
        }
    }

    private func present(_ image: NSImage, placement: Placement, visible: NSRect, box: NSSize) {
        // `image.size` is the natural size in points, so a small capture
        // is not enlarged.
        let size = HoverPreviewPolicy.fittedSize(of: image.size, in: box)
        guard size.width > 0, size.height > 0 else { return }
        let origin: CGPoint
        switch placement {
        case .besideMenu(let row, let menu):
            origin = HoverPreviewPolicy.origin(for: size, besideMenu: menu, anchorY: row.midY, in: visible)
        case .centered(let window):
            origin = HoverPreviewPolicy.origin(for: size, centeredOn: window, in: visible)
        }
        let panel = self.panel ?? makePanel()
        imageView?.image = image
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: HoverPreviewPolicy.maxSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // One level above pop-up menus, so the panel sits over the submenu's neighbors.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)

        let view = NSImageView(frame: panel.contentView?.bounds ?? .zero)
        view.autoresizingMask = [.width, .height]
        view.imageScaling = .scaleAxesIndependently
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        view.layer?.backgroundColor = NSColor.white.cgColor
        panel.contentView = view
        imageView = view
        self.panel = panel
        return panel
    }

    // MARK: - Image

    private func cacheKey(for url: URL) -> NSString? {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            return nil
        }
        return "\(url.path)|\(modified.timeIntervalSinceReferenceDate)" as NSString
    }

    private func cachedImage(for url: URL) -> NSImage? {
        guard let key = cacheKey(for: url) else { return nil }
        return cache.object(forKey: key)
    }

    private func store(_ image: NSImage, for url: URL) {
        guard let key = cacheKey(for: url) else { return }
        cache.setObject(image, forKey: key)
    }

    private struct Decoded: @unchecked Sendable {
        var image: NSImage
    }

    /// Reads the capture at no more than `maxPixel` on its long side. The
    /// point size is the pixel size over the display scale, capped by the
    /// file's own size, so a small capture is never enlarged.
    private nonisolated static func decode(_ url: URL, maxPixel: Int, scale: CGFloat) -> Decoded? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard width > 0, height > 0 else { return nil }
        // Never ask for more pixels than the file holds.
        let limit = min(maxPixel, max(width, height))
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        // The natural point size of the whole file. The thumbnail has the
        // same aspect ratio, so it fits the box the same way.
        let natural = NSSize(width: CGFloat(cgImage.width) / scale * CGFloat(max(width, height)) / CGFloat(limit),
                             height: CGFloat(cgImage.height) / scale * CGFloat(max(width, height)) / CGFloat(limit))
        return Decoded(image: NSImage(cgImage: cgImage, size: natural))
    }
}
