import Foundation
import FeedbackKit

/// A read-only index. Round image files stay in their original folders.
enum ScreenshotHistoryIndex {
    static func items(local: [ScreenshotHistoryItem], rounds: [FeedbackRound], rootURL: URL) -> [ScreenshotHistoryItem] {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        // Round JSON stores whole seconds. Sidecars retain fractional seconds.
        let captureDates = ISO8601DateFormatter()
        var indexed: [ScreenshotSourceID: ScreenshotHistoryItem] = [:]
        for item in local { indexed[item.id] = item }
        for round in rounds where round.schemaVersion <= FeedbackRound.currentSchemaVersion {
            guard isComponent(round.folderName), round.folderName != "ScreenshotHistory" else { continue }
            let directory = root.appendingPathComponent(round.folderName, isDirectory: true)
            guard directory.resolvingSymlinksInPath() == directory else { continue }
            for capture in round.captures {
                guard capture.index > 0, isComponent(capture.imageFile), isComponent(capture.cleanImageFile) else { continue }
                let annotated = directory.appendingPathComponent(capture.imageFile)
                guard annotated.resolvingSymlinksInPath() == annotated,
                      FileManager.default.isReadableFile(atPath: annotated.path) else { continue }
                let id = ScreenshotSourceID.round(folderName: round.folderName, captureIndex: capture.index)
                // Existing nonempty marks prove the save kept compatible image geometry.
                let reliableMarks = hasReliableMarks(capture)
                var metadata = ScreenshotMetadata(
                    id: stableMetadataID(for: id), createdAt: capture.capturedAt,
                    capturedAt: capture.capturedAt, size: capture.size,
                    appName: capture.sourceApp, windowTitle: capture.windowTitle,
                    marks: capture.marks, note: capture.note,
                    hasReliableCleanImage: reliableMarks, hasReliableBadges: reliableMarks
                )
                let provenance = directory.appendingPathComponent("\(capture.fileStem)-screenshot.json")
                if provenance.resolvingSymlinksInPath() == provenance,
                   let data = try? Data(contentsOf: provenance),
                   let recorded = try? JSONDecoder().decode(ScreenshotMetadata.self, from: data),
                   recorded.schemaVersion == ScreenshotMetadata.currentSchemaVersion,
                   recorded.size == capture.size,
                   captureDates.string(from: recorded.capturedAt) == captureDates.string(from: capture.capturedAt),
                   recorded.marks == capture.marks {
                    metadata.hasReliableCleanImage = recorded.hasReliableCleanImage
                    metadata.hasReliableBadges = recorded.hasReliableBadges
                }
                let clean = directory.appendingPathComponent(capture.cleanImageFile)
                let safeClean = metadata.hasReliableCleanImage && clean.resolvingSymlinksInPath() == clean
                    && FileManager.default.isReadableFile(atPath: clean.path)
                indexed[id] = ScreenshotHistoryItem(id: id, metadata: metadata, annotatedURL: annotated,
                    cleanURL: safeClean ? clean : nil)
            }
        }
        return indexed.values.sorted(by: ScreenshotRetention.newestFirst)
    }

    private static func hasReliableMarks(_ capture: FeedbackCapture) -> Bool {
        guard !capture.marks.isEmpty, capture.size.width > 0, capture.size.height > 0 else { return false }
        let badges = capture.marks.compactMap(\.badge)
        guard badges.allSatisfy({ $0 > 0 }), Set(badges).count == badges.count else { return false }
        return capture.marks.allSatisfy { mark in
            let box = mark.box
            guard box.x1 >= 0, box.y1 >= 0, box.x2 >= box.x1, box.y2 >= box.y1,
                  box.x2 <= capture.size.width, box.y2 <= capture.size.height else { return false }
            if mark.kind == .counter && mark.badge == nil { return false }
            if let point = mark.point {
                return point.x >= 0 && point.y >= 0 && point.x <= capture.size.width && point.y <= capture.size.height
            }
            return true
        }
    }

    private static func isComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }

    private static func stableMetadataID(for id: ScreenshotSourceID) -> UUID {
        // This UUID is metadata only. Source identity and ordering always use ScreenshotSourceID.
        var bytes = [UInt8](repeating: 0, count: 16)
        for (offset, byte) in id.sortKey.utf8.enumerated() {
            let index = offset % 16
            bytes[index] = (bytes[index] &* 31) &+ byte
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
