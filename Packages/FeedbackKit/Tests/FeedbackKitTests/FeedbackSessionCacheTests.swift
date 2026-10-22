import Foundation
import Testing
@testable import FeedbackKit

@Suite("FeedbackSessionCache")
struct FeedbackSessionCacheTests {
    private let root: URL
    private let fileManager = FileManager.default
    /// A whole-second date, so setting it and reading it back match exactly.
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("FeedbackSessionCacheTests-\(UUID().uuidString)", isDirectory: true)
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

    /// An ended session with one capture. `day` is the day of its end.
    private func ended(day: Int, name: String? = nil, endHour: Int = 10) -> FeedbackSession {
        FeedbackSession(
            name: name ?? "session \(day)",
            slug: "session-\(day)",
            folderName: "2026-10-\(day)-0900-session-\(day)",
            startedAt: date(day, 9, 0),
            endedAt: date(day, endHour, 0),
            captures: [capture(1)]
        )
    }

    private func file(_ session: FeedbackSession) -> URL {
        root.appendingPathComponent(session.folderName, isDirectory: true).appendingPathComponent("feedback.json")
    }

    /// Writes `root/<folderName>/feedback.json` and sets its modification date.
    @discardableResult
    private func write(_ session: FeedbackSession, modified: Date? = nil) throws -> FeedbackSession {
        let folder = root.appendingPathComponent(session.folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(session).write(to: file(session))
        try setModified(modified ?? stamp, of: file(session))
        return session
    }

    private func setModified(_ date: Date, of file: URL) throws {
        try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    }

    @Test("A fresh cache lists the same sessions as FeedbackLibrary.recent")
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

        var cache = FeedbackSessionCache()
        let listing = cache.recent(in: root)

        #expect(listing == FeedbackLibrary.recent(in: root))
        #expect(listing.sessions.map(\.folderName) == [
            "2026-10-16-0900-session-16",
            "2026-10-15-0900-session-15",
            "2026-10-14-0900-session-14",
            "2026-10-13-0900-session-13",
            "2026-10-12-0900-session-12",
        ])
        #expect(listing.unreadable == ["2026-10-19-0900-broken"])
    }

    @Test("Reuses a decoded session while feedback.json is unchanged")
    func reusesWhileUnchanged() throws {
        defer { try? fileManager.removeItem(at: root) }
        let session = try write(ended(day: 12))
        var cache = FeedbackSessionCache()
        #expect(cache.recent(in: root).sessions == [session])

        // Same byte count and same modification date, so only a decode would notice.
        let size = try Data(contentsOf: file(session)).count
        try Data(("{" + String(repeating: " ", count: size - 1)).utf8).write(to: file(session))
        try setModified(stamp, of: file(session))

        let listing = cache.recent(in: root)
        #expect(listing.sessions == [session])
        #expect(listing.unreadable == [])
    }

    @Test("Decodes again when feedback.json changes")
    func decodesWhenFileChanges() throws {
        defer { try? fileManager.removeItem(at: root) }
        let session = try write(ended(day: 12))
        var cache = FeedbackSessionCache()
        #expect(cache.recent(in: root).sessions.first?.endedAt == date(12, 10, 0))

        var changed = session
        changed.endedAt = date(12, 11, 0)
        try write(changed, modified: stamp.addingTimeInterval(1))

        #expect(cache.recent(in: root).sessions.first?.endedAt == date(12, 11, 0))
    }

    @Test("Sees a change within the same second when the size differs")
    func seesSizeChangeWithSameDate() throws {
        defer { try? fileManager.removeItem(at: root) }
        let session = try write(ended(day: 12))
        var cache = FeedbackSessionCache()
        #expect(cache.recent(in: root).sessions == [session])

        var changed = session
        changed.name = "a much longer session name than before"
        try write(changed, modified: stamp)

        #expect(cache.recent(in: root).sessions == [changed])
    }

    @Test("Drops a folder deleted after it was cached")
    func dropsDeletedFolder() throws {
        defer { try? fileManager.removeItem(at: root) }
        let session = try write(ended(day: 12))
        var cache = FeedbackSessionCache()
        #expect(cache.recent(in: root).sessions == [session])

        try fileManager.removeItem(at: root.appendingPathComponent(session.folderName))
        #expect(cache.recent(in: root).sessions.isEmpty)

        // A new folder with the same name, size, and date must not meet a stale entry.
        let replacement = try write(ended(day: 12, name: "SESSION 12"))
        #expect(cache.recent(in: root).sessions == [replacement])
    }

    @Test("Keeps an unreadable folder listed until its file changes")
    func unreadableUntilFileChanges() throws {
        defer { try? fileManager.removeItem(at: root) }
        let session = ended(day: 12)
        let folder = root.appendingPathComponent(session.folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: file(session))
        try setModified(stamp, of: file(session))

        var cache = FeedbackSessionCache()
        #expect(cache.recent(in: root).unreadable == [session.folderName])
        #expect(cache.recent(in: root).unreadable == [session.folderName])

        try write(session, modified: stamp.addingTimeInterval(5))

        let listing = cache.recent(in: root)
        #expect(listing.sessions == [session])
        #expect(listing.unreadable == [])
    }
}
