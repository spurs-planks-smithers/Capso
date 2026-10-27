import Foundation
import FeedbackKit
import HistoryKit
import ImageIO

/// Owns only UUID entry folders inside the dedicated screenshot database.
@MainActor
final class ScreenshotHistoryStore {
    enum StoreError: LocalizedError {
        case unsafePath, invalidImage, invalidMetadata, duplicateEntry
        var errorDescription: String? {
            switch self {
            case .unsafePath: return "Screenshot history contains an unsafe file path."
            case .invalidImage: return "The screenshot image cannot be saved."
            case .invalidMetadata: return "The screenshot metadata is incomplete or unsupported."
            case .duplicateEntry: return "This screenshot version is already saved."
            }
        }
    }

    let rootURL: URL
    private let database: HistoryStore
    private let files = FileManager.default
    /// A completed save remains successful if cleanup needs a later retry.
    private(set) var retentionError: Error?
    private struct Journal: Codable { let id: UUID }

    init(rootURL: URL) throws {
        let standardizedRoot = rootURL.standardizedFileURL
        guard standardizedRoot.resolvingSymlinksInPath() == standardizedRoot else {
            throw StoreError.unsafePath
        }
        self.rootURL = standardizedRoot
        for name in ["history.sqlite", "history.sqlite-wal", "history.sqlite-shm", "entries", "staging", "save-journal", "delete-journal"] {
            let child = self.rootURL.appendingPathComponent(name)
            guard child.resolvingSymlinksInPath() == child else { throw StoreError.unsafePath }
        }
        database = try HistoryStore(directory: self.rootURL)
        try recover()
        try pruneOwned(to: ScreenshotRetention.limit)
    }

    func save(_ input: ScreenshotWrite) async throws -> ScreenshotHistoryItem {
        let metadata = input.metadata
        guard metadata.schemaVersion == ScreenshotMetadata.currentSchemaVersion,
              metadata.size.width > 0, metadata.size.height > 0,
              metadata.createdAt.timeIntervalSince1970.isFinite,
              metadata.capturedAt.timeIntervalSince1970.isFinite,
              !metadata.hasReliableCleanImage || input.cleanPNG != nil else {
            throw StoreError.invalidMetadata
        }
        let image = try decodedImage(input.annotatedPNG, size: metadata.size)
        if let clean = input.cleanPNG { _ = try decodedImage(clean, size: metadata.size) }
        guard let thumbnail = ThumbnailGenerator.generateThumbnail(from: image) else {
            throw StoreError.invalidImage
        }
        let id = metadata.id
        let destination = try entryDirectory(id)
        guard !files.fileExists(atPath: destination.path),
              !(try database.fetchAll()).contains(where: { $0.id == id }) else {
            throw StoreError.duplicateEntry
        }
        let staging = try checked(rootURL.appendingPathComponent("staging/\(id.uuidString)", isDirectory: true))
        let journal = try journalURL("save", id)
        try writeJournal(id, to: journal)
        do {
            try files.createDirectory(at: staging, withIntermediateDirectories: true)
            try input.annotatedPNG.write(to: staging.appendingPathComponent("capture.png"), options: .atomic)
            if metadata.hasReliableCleanImage, let clean = input.cleanPNG {
                try clean.write(to: staging.appendingPathComponent("clean.png"), options: .atomic)
            }
            try thumbnail.write(to: staging.appendingPathComponent("thumbnail.jpg"), options: .atomic)
            try JSONEncoder().encode(metadata).write(to: staging.appendingPathComponent("screenshot.json"), options: .atomic)
            try files.moveItem(at: staging, to: destination)
            try database.insert(HistoryEntry(
                id: id, createdAt: metadata.createdAt, captureMode: .area,
                imageWidth: metadata.size.width, imageHeight: metadata.size.height,
                sourceAppName: metadata.appName, sourceWindowTitle: metadata.windowTitle,
                thumbnailFileName: "thumbnail.jpg", fullImageFileName: "capture.png",
                annotationFileName: "screenshot.json",
                fileSize: Int64(input.annotatedPNG.count + thumbnail.count + (metadata.hasReliableCleanImage ? (input.cleanPNG?.count ?? 0) : 0))
            ))
        } catch {
            // Only this new UUID is rolled back. Existing versions remain intact.
            do {
                try removeIfPresent(staging)
                try removeIfPresent(destination)
                try removeIfPresent(journal)
            } catch {
                // Keep the journal when rollback cannot finish. Startup retries the owned UUID.
            }
            throw error
        }
        // The row is the commit point. Journal cleanup must not turn it into a failed save.
        try? removeIfPresent(journal)
        do {
            try pruneOwned(to: ScreenshotRetention.limit)
            retentionError = nil
        } catch { retentionError = error }
        return try item(id: id, directory: destination)
    }

    func items() async throws -> [ScreenshotHistoryItem] {
        try completedItems()
    }

    func pruneToLatest(_ limit: Int) async throws {
        try pruneOwned(to: limit)
        retentionError = nil
    }

    private func decodedImage(_ data: Data, size: PixelSize) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == size.width, image.height == size.height else {
            throw StoreError.invalidImage
        }
        return image
    }

    private func completedItems() throws -> [ScreenshotHistoryItem] {
        try database.fetchAll().compactMap { row in
            guard row.fullImageFileName == "capture.png", row.thumbnailFileName == "thumbnail.jpg",
                  row.annotationFileName == "screenshot.json" else { throw StoreError.unsafePath }
            // Missing or corrupt images stay out of the visible index and retention count.
            return try? item(id: row.id, directory: entryDirectory(row.id))
        }.sorted(by: ScreenshotRetention.newestFirst)
    }

    private func item(id: UUID, directory: URL) throws -> ScreenshotHistoryItem {
        let metadataURL = try checked(directory.appendingPathComponent("screenshot.json"))
        let metadata = try JSONDecoder().decode(ScreenshotMetadata.self, from: Data(contentsOf: metadataURL))
        guard metadata.id == id, metadata.schemaVersion == ScreenshotMetadata.currentSchemaVersion else {
            throw StoreError.invalidMetadata
        }
        let annotated = try checked(directory.appendingPathComponent("capture.png"))
        guard files.isReadableFile(atPath: annotated.path) else { throw StoreError.invalidImage }
        let clean = try checked(directory.appendingPathComponent("clean.png"))
        let thumbnail = try checked(directory.appendingPathComponent("thumbnail.jpg"))
        return ScreenshotHistoryItem(id: .local(id), metadata: metadata, annotatedURL: annotated,
            cleanURL: metadata.hasReliableCleanImage && files.isReadableFile(atPath: clean.path) ? clean : nil,
            thumbnailURL: files.isReadableFile(atPath: thumbnail.path) ? thumbnail : nil)
    }

    private func pruneOwned(to limit: Int) throws {
        for id in ScreenshotRetention.expired(in: try completedItems(), keeping: limit) {
            let directory = try entryDirectory(id)
            // Validate ownership before recording deletion. Never use a database file path.
            _ = try item(id: id, directory: directory)
            let journal = try journalURL("delete", id)
            try writeJournal(id, to: journal)
            try database.delete(id: id)
            try removeIfPresent(directory)
            try removeIfPresent(journal)
        }
    }

    private func recover() throws {
        let rows = Set(try database.fetchAll().map(\.id))
        for operation in ["save", "delete"] {
            let directory = try checked(rootURL.appendingPathComponent("\(operation)-journal", isDirectory: true))
            guard files.fileExists(atPath: directory.path) else { continue }
            for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      url.pathExtension == "json" else { continue }
                let journal = try checked(url)
                let record = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journal))
                guard record.id == id else { throw StoreError.invalidMetadata }
                if operation == "delete" {
                    try database.delete(id: id)
                    try removeIfPresent(entryDirectory(id))
                } else if !rows.contains(id) {
                    try removeIfPresent(entryDirectory(id))
                }
                let staging = try checked(rootURL.appendingPathComponent("staging/\(id.uuidString)", isDirectory: true))
                try removeIfPresent(staging)
                try removeIfPresent(journal)
            }
        }
    }

    private func entryDirectory(_ id: UUID) throws -> URL {
        try checked(database.entriesDirectory.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    private func journalURL(_ operation: String, _ id: UUID) throws -> URL {
        let directory = try checked(rootURL.appendingPathComponent("\(operation)-journal", isDirectory: true))
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        return try checked(directory.appendingPathComponent("\(id.uuidString).json"))
    }

    private func writeJournal(_ id: UUID, to url: URL) throws {
        try JSONEncoder().encode(Journal(id: id)).write(to: url, options: .atomic)
    }

    private func checked(_ url: URL) throws -> URL {
        let normalized = url.standardizedFileURL
        guard normalized.path.hasPrefix(rootURL.path + "/"),
              normalized.resolvingSymlinksInPath().path == normalized.path else {
            throw StoreError.unsafePath
        }
        return normalized
    }

    private func removeIfPresent(_ url: URL) throws {
        let owned = try checked(url)
        if files.fileExists(atPath: owned.path) { try files.removeItem(at: owned) }
    }
}
