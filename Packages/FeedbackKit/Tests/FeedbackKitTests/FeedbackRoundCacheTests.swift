import Foundation
import Testing
@testable import FeedbackKit

@Suite("FeedbackRoundCache")
struct FeedbackRoundCacheTests {
    private let root: URL
    private let fileManager = FileManager.default
    /// A whole-second date, so setting it and reading it back match exactly.
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("FeedbackRoundCacheTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        FeedbackFixtures.date(day, hour, minute)
    }

    private func capture(_ index: Int) -> FeedbackCapture {
        FeedbackCapture(
            index: index,
            imageFile: "capture-\(index).png",
            cleanImageFile: "capture-\(index)-clean.png",
            size: PixelSize(width: 800, height: 600),
            capturedAt: date(21, 15, 43),
            sourceApp: "Safari"
        )
    }

    /// An ended round with one capture. `day` is the day of its end.
    private func ended(day: Int, name: String? = nil, endHour: Int = 10) -> FeedbackRound {
        FeedbackRound(
            name: name ?? "round \(day)",
            slug: "round-\(day)",
            folderName: "2026-10-\(day)-0900-round-\(day)",
            startedAt: date(day, 9, 0),
            endedAt: date(day, endHour, 0),
            captures: [capture(1)]
        )
    }

    private func file(_ round: FeedbackRound) -> URL {
        root.appendingPathComponent(round.folderName, isDirectory: true).appendingPathComponent("feedback.json")
    }

    /// Writes `root/<folderName>/feedback.json` and sets its modification date.
    @discardableResult
    private func write(_ round: FeedbackRound, modified: Date? = nil) throws -> FeedbackRound {
        let folder = root.appendingPathComponent(round.folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(round).write(to: file(round))
        try setModified(modified ?? stamp, of: file(round))
        return round
    }

    private func setModified(_ date: Date, of file: URL) throws {
        try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    }

    @Test("A fresh cache lists the same rounds as FeedbackLibrary.recent")
    func freshCacheMatchesLibrary() throws {
        defer { try? fileManager.removeItem(at: root) }
        for day in 10...16 {
            try write(ended(day: day))
        }
        var active = ended(day: 17)
        active.endedAt = nil
        try write(active)
        var empty = ended(day: 18)
        empty.captures = []
        try write(empty)
        let broken = root.appendingPathComponent("2026-10-19-0900-broken", isDirectory: true)
        try fileManager.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: broken.appendingPathComponent("feedback.json"))
        try fileManager.createDirectory(at: root.appendingPathComponent("2026-10-20-0900-no-file"), withIntermediateDirectories: true)

        var cache = FeedbackRoundCache()
        let listing = cache.recent(in: root)

        #expect(listing == FeedbackLibrary.recent(in: root))
        #expect(listing.rounds.map(\.folderName) == [
            "2026-10-16-0900-round-16",
            "2026-10-15-0900-round-15",
            "2026-10-14-0900-round-14",
            "2026-10-13-0900-round-13",
            "2026-10-12-0900-round-12",
        ])
        #expect(listing.unreadable == ["2026-10-19-0900-broken"])
    }

    @Test("Names a newer-schema round apart from unreadable ones, and reads it again after a change")
    func namesNewerSchema() throws {
        defer { try? fileManager.removeItem(at: root) }
        let good = try write(ended(day: 12))
        let newer = ended(day: 13)
        try write(newer)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file(newer))) as? [String: Any])
        json["schemaVersion"] = FeedbackRound.currentSchemaVersion + 1
        try JSONSerialization.data(withJSONObject: json).write(to: file(newer))
        try setModified(stamp, of: file(newer))

        var cache = FeedbackRoundCache()
        var listing = cache.recent(in: root)
        #expect(listing.rounds == [good])
        #expect(listing.newerSchema == [newer.folderName])
        #expect(listing.unreadable.isEmpty)
        // The second call comes from the cache and says the same.
        #expect(cache.recent(in: root) == listing)

        // The same round saved again under the current schema is listed.
        try write(newer, modified: stamp.addingTimeInterval(60))
        listing = cache.recent(in: root)
        #expect(listing.rounds.map(\.folderName) == [newer.folderName, good.folderName])
        #expect(listing.newerSchema.isEmpty)
    }

    @Test("Reuses a decoded round while feedback.json is unchanged")
    func reusesWhileUnchanged() throws {
        defer { try? fileManager.removeItem(at: root) }
        let round = try write(ended(day: 12))
        var cache = FeedbackRoundCache()
        #expect(cache.recent(in: root).rounds == [round])

        // Same byte count and same modification date, so only a decode would notice.
        let size = try Data(contentsOf: file(round)).count
        try Data(("{" + String(repeating: " ", count: size - 1)).utf8).write(to: file(round))
        try setModified(stamp, of: file(round))

        let listing = cache.recent(in: root)
        #expect(listing.rounds == [round])
        #expect(listing.unreadable == [])
    }

    @Test("Decodes again when feedback.json changes")
    func decodesWhenFileChanges() throws {
        defer { try? fileManager.removeItem(at: root) }
        let round = try write(ended(day: 12))
        var cache = FeedbackRoundCache()
        #expect(cache.recent(in: root).rounds.first?.endedAt == date(12, 10, 0))

        var changed = round
        changed.endedAt = date(12, 11, 0)
        try write(changed, modified: stamp.addingTimeInterval(1))

        #expect(cache.recent(in: root).rounds.first?.endedAt == date(12, 11, 0))
    }

    @Test("Sees a change within the same second when the size differs")
    func seesSizeChangeWithSameDate() throws {
        defer { try? fileManager.removeItem(at: root) }
        let round = try write(ended(day: 12))
        var cache = FeedbackRoundCache()
        #expect(cache.recent(in: root).rounds == [round])

        var changed = round
        changed.name = "a much longer round name than before"
        try write(changed, modified: stamp)

        #expect(cache.recent(in: root).rounds == [changed])
    }

    @Test("Drops a folder deleted after it was cached")
    func dropsDeletedFolder() throws {
        defer { try? fileManager.removeItem(at: root) }
        let round = try write(ended(day: 12))
        var cache = FeedbackRoundCache()
        #expect(cache.recent(in: root).rounds == [round])

        try fileManager.removeItem(at: root.appendingPathComponent(round.folderName))
        #expect(cache.recent(in: root).rounds.isEmpty)

        // A new folder with the same name, size, and date must not meet a stale entry.
        let replacement = try write(ended(day: 12, name: "ROUND 12"))
        #expect(cache.recent(in: root).rounds == [replacement])
    }

    @Test("Keeps an unreadable folder listed until its file changes")
    func unreadableUntilFileChanges() throws {
        defer { try? fileManager.removeItem(at: root) }
        let round = ended(day: 12)
        let folder = root.appendingPathComponent(round.folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: file(round))
        try setModified(stamp, of: file(round))

        var cache = FeedbackRoundCache()
        #expect(cache.recent(in: root).unreadable == [round.folderName])
        #expect(cache.recent(in: root).unreadable == [round.folderName])

        try write(round, modified: stamp.addingTimeInterval(5))

        let listing = cache.recent(in: root)
        #expect(listing.rounds == [round])
        #expect(listing.unreadable == [])
    }
}
