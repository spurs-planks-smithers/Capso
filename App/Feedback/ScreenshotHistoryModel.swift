import Foundation
import FeedbackKit

/// Stable identity for an owned screenshot version or an existing round image.
enum ScreenshotSourceID: Hashable, Codable, Sendable {
    case local(UUID)
    case round(folderName: String, captureIndex: Int)

    var sortKey: String {
        switch self {
        case .local(let id): return "local:\(id.uuidString)"
        case .round(let folder, let index): return "round:\(folder):\(index)"
        }
    }

    /// The key of a round capture in the Nshot menu's checks. A screenshot has none.
    var basketKey: FeedbackBasketKey? {
        guard case .round(let folder, let index) = self else { return nil }
        return FeedbackBasketKey(folderName: folder, captureIndex: index)
    }
}

struct ScreenshotMetadata: Codable, Sendable {
    static let currentSchemaVersion = 1
    var schemaVersion = Self.currentSchemaVersion
    var id: UUID
    var parent: ScreenshotSourceID?
    var createdAt: Date
    var capturedAt: Date
    var size: PixelSize
    var appName: String?
    var windowTitle: String?
    var marks: [FeedbackMark]
    var note: String?
    var hasReliableCleanImage: Bool
    var hasReliableBadges: Bool

    init(id: UUID = UUID(), parent: ScreenshotSourceID? = nil, createdAt: Date,
         capturedAt: Date, size: PixelSize, appName: String?, windowTitle: String?,
         marks: [FeedbackMark], note: String?, hasReliableCleanImage: Bool,
         hasReliableBadges: Bool) {
        self.id = id
        self.parent = parent
        self.createdAt = createdAt
        self.capturedAt = capturedAt
        self.size = size
        self.appName = appName
        self.windowTitle = windowTitle
        self.marks = marks
        self.note = note
        self.hasReliableCleanImage = hasReliableCleanImage
        self.hasReliableBadges = hasReliableBadges
    }
}

struct ScreenshotWrite: Sendable {
    var metadata: ScreenshotMetadata
    var annotatedPNG: Data
    var cleanPNG: Data?
}

struct ScreenshotHistoryItem: Identifiable, Sendable {
    let id: ScreenshotSourceID
    var metadata: ScreenshotMetadata
    let annotatedURL: URL
    let cleanURL: URL?
    let thumbnailURL: URL?
    /// The round's name, as Recent Rounds shows it. Nil for a screenshot.
    var roundName: String?
    /// The capture's summary name, else its first instruction. Nil when the
    /// reviewer wrote no words.
    var captureName: String?

    init(id: ScreenshotSourceID, metadata: ScreenshotMetadata, annotatedURL: URL,
         cleanURL: URL?, thumbnailURL: URL? = nil, roundName: String? = nil, captureName: String? = nil) {
        self.id = id
        self.metadata = metadata
        self.annotatedURL = annotatedURL
        self.cleanURL = cleanURL
        self.thumbnailURL = thumbnailURL
        self.roundName = roundName
        self.captureName = captureName
    }

    var createdAt: Date { metadata.createdAt }
    var capturedAt: Date { metadata.capturedAt }
    var appName: String? { metadata.appName }
    var windowTitle: String? { metadata.windowTitle }
    var size: PixelSize { metadata.size }
    var marks: [FeedbackMark] { metadata.marks }
    var note: String? { metadata.note }
}

enum ScreenshotCapturePurpose: Sendable {
    case feedback
    case instantScreenshot
}
