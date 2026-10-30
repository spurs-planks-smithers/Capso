// Packages/FeedbackKit/Sources/FeedbackKit/ZipPlan.swift
import CoreGraphics
import Foundation

/// What a zip export holds (#85). Design: `docs/superpowers/specs/2026-10-25-zip-handoff-design.md`.
public enum ZipKind: String, Sendable {
    /// Every capture of one round.
    case round
    /// The captures checked in the Recent Rounds menu, from one round or several.
    case selection
}

/// The zip's file name without `.zip`, which is also its top folder.
public enum ZipName {
    /// `nextshot-round-2026-10-25-0637-3-captures`. A round passes its start
    /// time, a selection passes the time of the zip.
    public static func base(kind: ZipKind, time: Date, captureCount: Int, timeZone: TimeZone) -> String {
        let count = captureCount == 1 ? "1-capture" : "\(captureCount)-captures"
        return "nextshot-\(kind.rawValue)-\(FeedbackNaming.format(time, "yyyy-MM-dd-HHmm", timeZone: timeZone))-\(count)"
    }
}

/// One step of the size ladder: the JPEG quality of each image kind, and a
/// factor on the standard tier size.
public struct ZipStep: Equatable, Sendable {
    public var annotatedQuality: Double
    public var cleanQuality: Double
    public var pixelScale: Double

    public init(annotatedQuality: Double, cleanQuality: Double, pixelScale: Double) {
        self.annotatedQuality = annotatedQuality
        self.cleanQuality = cleanQuality
        self.pixelScale = pixelScale
    }
}

/// A zip over the budget steps down until it fits: clean copies first, then
/// all images, then pixels, down to the floor.
public enum ZipLadder {
    /// The goal for the real zip size, in bytes (5 MB).
    public static let budgetBytes = 5_000_000
    /// No image shrinks below this long edge, in pixels.
    public static let floorLongEdge = 1000

    public static func step(_ index: Int) -> ZipStep {
        switch index {
        case ...0: ZipStep(annotatedQuality: 0.75, cleanQuality: 0.75, pixelScale: 1)
        case 1: ZipStep(annotatedQuality: 0.75, cleanQuality: 0.50, pixelScale: 1)
        case 2: ZipStep(annotatedQuality: 0.60, cleanQuality: 0.50, pixelScale: 1)
        default: ZipStep(annotatedQuality: 0.60, cleanQuality: 0.50, pixelScale: pow(0.85, Double(index - 2)))
        }
    }

    /// The standard tier size, times `pixelScale`, never below the floor and
    /// never above the standard tier size. An image smaller than the floor
    /// keeps its size.
    public static func targetSize(_ source: PixelSize, pixelScale: Double) -> PixelSize {
        let base = ImageSizing.resizedSize(source, limits: .standard)
        let longEdge = max(base.width, base.height)
        guard pixelScale < 1, longEdge > 0 else { return base }
        let floor = min(floorLongEdge, longEdge)
        let scaledLong = max(floor, Int((Double(longEdge) * pixelScale).rounded()))
        return withLongEdge(scaledLong, of: base)
    }

    /// `size` with its long edge set to `longEdge`, keeping the aspect ratio.
    static func withLongEdge(_ longEdge: Int, of size: PixelSize) -> PixelSize {
        let current = max(size.width, size.height)
        guard longEdge < current, current > 0 else { return size }
        let factor = Double(longEdge) / Double(current)
        func scaled(_ value: Int) -> Int { max(Int((Double(value) * factor).rounded()), 1) }
        return size.width >= size.height
            ? PixelSize(width: longEdge, height: scaled(size.height))
            : PixelSize(width: scaled(size.width), height: longEdge)
    }
}

/// One image to encode into the zip.
public struct ZipImage: Equatable, Sendable {
    /// The bundle's PNG.
    public var sourceURL: URL
    /// The name in the zip: `K-<stem>.jpg` or `K-<stem>-clean.jpg`.
    public var fileName: String
    public var size: PixelSize
    public var isClean: Bool

    public init(sourceURL: URL, fileName: String, size: PixelSize, isClean: Bool) {
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.size = size
        self.isClean = isClean
    }
}

/// The zip's own round and its images at one ladder step.
public struct ZipPlan: Equatable, Sendable {
    /// Renumbered, renamed, and rescaled. The README, the manifest, the
    /// prompts, and `feedback.json` all come from it, so they agree.
    public var round: FeedbackRound
    public var images: [ZipImage]
    /// A selection's source rounds, one line each. A round zip has none.
    public var sourceRoundLines: [String]
    /// True when a smaller pixel scale would shrink no image.
    public var atFloor: Bool
    public var attachments: [ZipAttachment] = []
}

public struct ZipAttachment: Equatable, Sendable {
    public var source: URL
    public var name: String
}

public enum ZipPlanner {
    /// Builds the zip's round from the entries. A round zip keeps each
    /// capture's index as K. A selection numbers its captures 1 to N in the
    /// order `PromptBuilder.renderSelection` uses: capture time, then folder,
    /// then capture index.
    public static func plan(
        kind: ZipKind,
        entries: [FeedbackSelectionEntry],
        folderName: String,
        zipTime: Date,
        pixelScale: Double
    ) -> ZipPlan {
        let ordered: [FeedbackSelectionEntry] = switch kind {
        case .round: entries.sorted { $0.capture.index < $1.capture.index }
        case .selection: entries.sorted(by: selectionOrder)
        }

        var captures: [FeedbackCapture] = []
        var images: [ZipImage] = []
        var attachments: [ZipAttachment] = []
        var atFloor = true
        for (offset, entry) in ordered.enumerated() {
            let source = entry.capture
            let number = kind == .round ? source.index : offset + 1
            let target = ZipLadder.targetSize(source.size, pixelScale: pixelScale)
            if ZipLadder.targetSize(source.size, pixelScale: pixelScale * 0.85) != target {
                atFloor = false
            }
            let capture = rescaled(source, index: number, target: target)
            captures.append(capture)

            let folder = URL(fileURLWithPath: entry.folderPath, isDirectory: true)
            images.append(ZipImage(sourceURL: folder.appendingPathComponent(source.imageFile), fileName: capture.imageFile, size: capture.size, isClean: false))
            images.append(ZipImage(sourceURL: folder.appendingPathComponent(source.cleanImageFile), fileName: capture.cleanImageFile, size: capture.size, isClean: true))
            for name in [source.browserEvidenceFile].compactMap({ $0 }) + (source.browserAssetFiles ?? []) {
                attachments.append(ZipAttachment(source: folder.appendingPathComponent(name), name: name))
            }
        }

        let round: FeedbackRound
        switch kind {
        case .round:
            let first = ordered.first?.round
            round = FeedbackRound(
                name: first?.name ?? FeedbackNaming.defaultSlug,
                slug: first?.slug ?? FeedbackNaming.defaultSlug,
                folderName: folderName,
                startedAt: first?.startedAt ?? zipTime,
                endedAt: first?.endedAt,
                captures: captures
            )
        case .selection:
            round = FeedbackRound(
                name: "selection",
                slug: "selection",
                folderName: folderName,
                startedAt: ordered.first?.capture.capturedAt ?? zipTime,
                endedAt: zipTime,
                captures: captures
            )
        }

        return ZipPlan(
            round: round,
            images: images,
            sourceRoundLines: kind == .selection ? sourceLines(ordered) : [],
            atFloor: atFloor,
            attachments: Array(Set(attachments.map(\.name))).sorted().compactMap { name in attachments.first { $0.name == name } }
        )
    }

    private static func selectionOrder(_ lhs: FeedbackSelectionEntry, _ rhs: FeedbackSelectionEntry) -> Bool {
        if lhs.capture.capturedAt != rhs.capture.capturedAt {
            return lhs.capture.capturedAt < rhs.capture.capturedAt
        }
        if lhs.folderPath != rhs.folderPath {
            return lhs.folderPath < rhs.folderPath
        }
        return lhs.capture.index < rhs.capture.index
    }

    /// The capture with its zip number, its zip file names, and every mark
    /// scaled to the zip image. Rounding can make two boxes touch that did not
    /// touch before, which would change which shape a badge labels. So when
    /// the pairs differ, it tries a long edge 1 to 8 pixels shorter.
    static func rescaled(_ source: FeedbackCapture, index: Int, target: PixelSize) -> FeedbackCapture {
        let sourcePairs = pairs(source)
        let longEdge = max(target.width, target.height)
        var first: FeedbackCapture?
        for shorter in 0...8 where longEdge - shorter > 0 {
            let size = ZipLadder.withLongEdge(longEdge - shorter, of: target)
            let candidate = scaled(source, index: index, to: size)
            if pairs(candidate) == sourcePairs {
                return candidate
            }
            first = first ?? candidate
        }
        return first ?? scaled(source, index: index, to: target)
    }

    private static func scaled(_ source: FeedbackCapture, index: Int, to size: PixelSize) -> FeedbackCapture {
        var capture = source
        capture.index = index
        capture.imageFile = "\(index)-\(source.fileStem).jpg"
        capture.cleanImageFile = "\(index)-\((source.cleanImageFile as NSString).deletingPathExtension).jpg"
        capture.size = size
        capture.marks = source.marks.map { mark in
            var mark = mark
            let box = mark.box
            mark.box = ImageSizing.scale(
                CGRect(x: box.x1, y: box.y1, width: box.x2 - box.x1, height: box.y2 - box.y1),
                from: source.size,
                to: size
            )
            mark.point = mark.point.map { ImageSizing.scale(CGPoint(x: $0.x, y: $0.y), from: source.size, to: size) }
            return mark
        }
        return capture
    }

    /// Badge number and the position of its shape in `marks`, per item.
    private static func pairs(_ capture: FeedbackCapture) -> [String] {
        FeedbackItems.split(capture).items.map { item in
            let shape = item.shape.flatMap { capture.marks.firstIndex(of: $0) }.map(String.init) ?? "none"
            return "\(item.badge.badge ?? 0):\(shape)"
        }
    }

    /// "- 2026-10-20-1912-pricing-page: its captures 2 and 3, here 1 and 2",
    /// one line per source round, in the order the round first appears.
    private static func sourceLines(_ ordered: [FeedbackSelectionEntry]) -> [String] {
        var folders: [String] = []
        var theirs: [String: [Int]] = [:]
        var here: [String: [Int]] = [:]
        for (offset, entry) in ordered.enumerated() {
            let folder = URL(fileURLWithPath: entry.folderPath).lastPathComponent
            if theirs[folder] == nil {
                folders.append(folder)
            }
            theirs[folder, default: []].append(entry.capture.index)
            here[folder, default: []].append(offset + 1)
        }
        return folders.map { folder in
            let own = theirs[folder] ?? []
            let noun = own.count == 1 ? "capture" : "captures"
            return "- \(folder): its \(noun) \(list(own)), here \(list(here[folder] ?? []))"
        }
    }

    /// "2", "2 and 3", or "1, 2, and 3".
    private static func list(_ numbers: [Int]) -> String {
        let text = numbers.map(String.init)
        switch text.count {
        case 0: return ""
        case 1: return text[0]
        case 2: return "\(text[0]) and \(text[1])"
        default: return text.dropLast().joined(separator: ", ") + ", and " + text[text.count - 1]
        }
    }
}
