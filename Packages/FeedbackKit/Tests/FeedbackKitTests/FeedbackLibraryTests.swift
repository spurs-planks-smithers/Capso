import Foundation
import Testing
@testable import FeedbackKit

@Suite("FeedbackLibrary")
struct FeedbackLibraryTests {
    private let root: URL
    private let fileManager = FileManager.default
    private let tz = FeedbackFixtures.timeZone
    private let en = Locale(identifier: "en_US")

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("FeedbackLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        FeedbackFixtures.date(day, hour, minute)
    }

    private func capture(_ index: Int, app: String? = "Safari", title: String? = nil, badges: [Int] = []) -> FeedbackCapture {
        FeedbackCapture(
            index: index,
            imageFile: "capture-\(index).png",
            cleanImageFile: "capture-\(index)-clean.png",
            size: PixelSize(width: 800, height: 600),
            capturedAt: date(21, 15, 43),
            sourceApp: app,
            windowTitle: title,
            marks: badges.map { FeedbackMark(kind: .counter, badge: $0, box: FeedbackBox(x1: 0, y1: 0, x2: 24, y2: 24)) }
        )
    }

    /// Writes `root/<folderName>/feedback.json`, the way the store does.
    @discardableResult
    private func write(_ session: FeedbackSession) throws -> FeedbackSession {
        let folder = root.appendingPathComponent(session.folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(session).write(to: folder.appendingPathComponent("feedback.json"))
        return session
    }

    /// An ended session with one capture. `day` is the day of its end.
    private func ended(day: Int, name: String? = nil, startedDay: Int? = nil) -> FeedbackSession {
        FeedbackSession(
            name: name ?? "session \(day)",
            slug: "session-\(day)",
            folderName: "2026-10-\(day)-0900-session-\(day)",
            startedAt: date(startedDay ?? day, 9, 0),
            endedAt: date(day, 10, 0),
            captures: [capture(1)]
        )
    }

    @Test("Lists ended sessions with captures, newest end first, at most 5")
    func listsNewestFirstWithLimit() throws {
        defer { try? fileManager.removeItem(at: root) }
        for day in 10...16 {
            try write(ended(day: day))
        }

        let listing = FeedbackLibrary.recent(in: root)
        #expect(listing.sessions.map(\.folderName) == [
            "2026-10-16-0900-session-16",
            "2026-10-15-0900-session-15",
            "2026-10-14-0900-session-14",
            "2026-10-13-0900-session-13",
            "2026-10-12-0900-session-12",
        ])
        #expect(listing.unreadable.isEmpty)
    }

    @Test("Sorts by end time, so a resumed and ended old session comes first")
    func sortsByEndTime() throws {
        defer { try? fileManager.removeItem(at: root) }
        let a = try write(ended(day: 20, name: "A", startedDay: 10))
        let b = try write(ended(day: 16, name: "B", startedDay: 15))

        #expect(FeedbackLibrary.recent(in: root).sessions == [a, b])
    }

    @Test("Leaves out the active session and sessions with no captures")
    func leavesOutActiveAndEmpty() throws {
        defer { try? fileManager.removeItem(at: root) }
        let kept = try write(ended(day: 12))
        var active = ended(day: 13)
        active.endedAt = nil
        try write(active)
        var empty = ended(day: 14)
        empty.captures = []
        try write(empty)

        #expect(FeedbackLibrary.recent(in: root).sessions == [kept])
    }

    @Test("Skips an unreadable folder and names it")
    func skipsUnreadableFolder() throws {
        defer { try? fileManager.removeItem(at: root) }
        let good = try write(ended(day: 12))
        let broken = root.appendingPathComponent("2026-10-01-0900-broken", isDirectory: true)
        try fileManager.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: broken.appendingPathComponent("feedback.json"))

        let listing = FeedbackLibrary.recent(in: root)
        #expect(listing.unreadable == ["2026-10-01-0900-broken"])
        #expect(listing.sessions == [good])
    }

    @Test("Ignores plain files and folders without feedback.json")
    func ignoresStrayEntries() throws {
        defer { try? fileManager.removeItem(at: root) }
        try Data("{\"folderName\":\"x\"}".utf8).write(to: root.appendingPathComponent(".active.json"))
        try fileManager.createDirectory(at: root.appendingPathComponent("empty-folder", isDirectory: true), withIntermediateDirectories: true)

        let listing = FeedbackLibrary.recent(in: root)
        #expect(listing.unreadable == [])
        #expect(listing.sessions.isEmpty)
    }

    @Test("Returns an empty listing when the root folder does not exist")
    func missingRoot() {
        defer { try? fileManager.removeItem(at: root) }
        let listing = FeedbackLibrary.recent(in: root.appendingPathComponent("nope", isDirectory: true))
        #expect(listing == FeedbackLibrary.Listing(sessions: [], unreadable: []))
    }

    @Test("Loads one session by folder name, nil when missing")
    func loadsOneSession() throws {
        defer { try? fileManager.removeItem(at: root) }
        let session = try write(ended(day: 12))

        #expect(FeedbackLibrary.session(named: session.folderName, in: root) == session)
        #expect(FeedbackLibrary.session(named: "2026-10-01-0900-missing", in: root) == nil)
        #expect(FeedbackLibrary.session(named: "../\(session.folderName)", in: root) == nil)
    }

    @Test("Titles a row by relative day and start time")
    func titlesRow() {
        defer { try? fileManager.removeItem(at: root) }
        let now = date(22, 7, 0)
        #expect(FeedbackLibrary.title(startedAt: date(22, 6, 27), now: now, timeZone: tz, locale: en) == "Today, 6:27 AM")
        #expect(FeedbackLibrary.title(startedAt: date(21, 15, 41), now: now, timeZone: tz, locale: en) == "Yesterday, 3:41 PM")
        #expect(FeedbackLibrary.title(startedAt: date(20, 21, 59), now: now, timeZone: tz, locale: en) == "Oct 20, 9:59 PM")
    }

    @Test("Subtitles a row with apps in order, capture count, and selection count")
    func subtitlesRow() {
        defer { try? fileManager.removeItem(at: root) }
        let apps: [String?] = ["Preview", "Preview", "TextEdit", "Claude", nil]
        var s = ended(day: 21)
        s.captures = apps.enumerated().map { capture($0.offset + 1, app: $0.element) }
        #expect(FeedbackLibrary.subtitle(for: s, selectedCount: 0) == "Preview, TextEdit, Claude, 5 captures")
        #expect(FeedbackLibrary.subtitle(for: s, selectedCount: 2) == "Preview, TextEdit, Claude, 5 captures, 2 selected")

        var one = ended(day: 21)
        one.captures = [capture(1, app: "Safari")]
        #expect(FeedbackLibrary.subtitle(for: one, selectedCount: 0) == "Safari, 1 capture")
    }

    @Test("Subtitles a row with no known app by count alone")
    func subtitleWithoutApps() {
        defer { try? fileManager.removeItem(at: root) }
        var s = ended(day: 21)
        s.captures = [capture(1, app: nil), capture(2, app: nil)]
        #expect(FeedbackLibrary.subtitle(for: s, selectedCount: 0) == "2 captures")
    }

    @Test("Names a capture row by time and window title, else app")
    func namesCaptureRow() {
        defer { try? fileManager.removeItem(at: root) }
        var titled = capture(1, app: "Preview", title: "snapshot-5412387.pdf")
        titled.capturedAt = date(21, 15, 43)
        #expect(FeedbackLibrary.captureRowTitle(titled, timeZone: tz, locale: en) == "3:43 PM snapshot-5412387.pdf")

        var appOnly = capture(2, app: "TextEdit", title: nil)
        appOnly.capturedAt = date(21, 15, 43)
        #expect(FeedbackLibrary.captureRowTitle(appOnly, timeZone: tz, locale: en) == "3:43 PM TextEdit")

        var neither = capture(4, app: nil, title: nil)
        neither.capturedAt = date(21, 15, 43)
        #expect(FeedbackLibrary.captureRowTitle(neither, timeZone: tz, locale: en) == "3:43 PM Capture 4")
    }

    @Test("Counts items as a short text")
    func countsItems() {
        defer { try? fileManager.removeItem(at: root) }
        #expect(FeedbackLibrary.itemCountText(capture(1, badges: [])) == "No items")
        #expect(FeedbackLibrary.itemCountText(capture(1, badges: [1])) == "1 item")
        #expect(FeedbackLibrary.itemCountText(capture(1, badges: [1, 2, 3, 4])) == "4 items")
    }
}
