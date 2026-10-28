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
    private func write(_ round: FeedbackRound) throws -> FeedbackRound {
        let folder = root.appendingPathComponent(round.folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(round).write(to: folder.appendingPathComponent("feedback.json"))
        return round
    }

    /// An ended round with one capture. `day` is the day of its end.
    private func ended(day: Int, name: String? = nil, startedDay: Int? = nil) -> FeedbackRound {
        FeedbackRound(
            name: name ?? "round \(day)",
            slug: "round-\(day)",
            folderName: "2026-10-\(day)-0900-round-\(day)",
            startedAt: date(startedDay ?? day, 9, 0),
            endedAt: date(day, 10, 0),
            captures: [capture(1)]
        )
    }

    @Test("Lists ended rounds with captures, newest end first, at most 5")
    func listsNewestFirstWithLimit() throws {
        defer { try? fileManager.removeItem(at: root) }
        for day in 10...16 {
            try write(ended(day: day))
        }

        let listing = FeedbackLibrary.recent(in: root)
        #expect(listing.rounds.map(\.folderName) == [
            "2026-10-16-0900-round-16",
            "2026-10-15-0900-round-15",
            "2026-10-14-0900-round-14",
            "2026-10-13-0900-round-13",
            "2026-10-12-0900-round-12",
        ])
        #expect(listing.unreadable.isEmpty)
    }

    @Test("Sorts by end time, so a resumed and ended old round comes first")
    func sortsByEndTime() throws {
        defer { try? fileManager.removeItem(at: root) }
        let a = try write(ended(day: 20, name: "A", startedDay: 10))
        let b = try write(ended(day: 16, name: "B", startedDay: 15))

        #expect(FeedbackLibrary.recent(in: root).rounds == [a, b])
    }

    @Test("Leaves out the active round and rounds with no captures")
    func leavesOutActiveAndEmpty() throws {
        defer { try? fileManager.removeItem(at: root) }
        let kept = try write(ended(day: 12))
        var active = ended(day: 13)
        active.endedAt = nil
        try write(active)
        var empty = ended(day: 14)
        empty.captures = []
        try write(empty)

        #expect(FeedbackLibrary.recent(in: root).rounds == [kept])
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
        #expect(listing.rounds == [good])
    }

    /// Rewrites a round's `feedback.json` the way a newer Nextshot would:
    /// a higher `schemaVersion`, a field this copy does not know, and a
    /// changed field this copy cannot decode.
    @discardableResult
    private func writeFromNewerSchema(_ round: FeedbackRound, breakingChange: Bool = false) throws -> Data {
        try write(round)
        let file = root.appendingPathComponent(round.folderName).appendingPathComponent("feedback.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["schemaVersion"] = FeedbackRound.currentSchemaVersion + 1
        json["futureField"] = "only a newer Nextshot knows this"
        if breakingChange {
            json["captures"] = "now a different shape"
        }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try data.write(to: file)
        return data
    }

    @Test("Refuses a round from a newer schema and names it apart from unreadable ones")
    func refusesNewerSchema() throws {
        defer { try? fileManager.removeItem(at: root) }
        let good = try write(ended(day: 12))
        let compatible = ended(day: 13)
        let compatibleBytes = try writeFromNewerSchema(compatible)
        let incompatible = ended(day: 14)
        try writeFromNewerSchema(incompatible, breakingChange: true)

        let listing = FeedbackLibrary.recent(in: root)
        #expect(listing.rounds == [good])
        #expect(listing.newerSchema == [compatible.folderName, incompatible.folderName])
        #expect(listing.unreadable.isEmpty)
        // This copy never rewrites a file it refused.
        let file = root.appendingPathComponent(compatible.folderName).appendingPathComponent("feedback.json")
        #expect(try Data(contentsOf: file) == compatibleBytes)
    }

    @Test("Loads no single round from a newer schema")
    func loadsNoNewerSchemaRound() throws {
        defer { try? fileManager.removeItem(at: root) }
        let newer = ended(day: 13)
        try writeFromNewerSchema(newer)

        #expect(FeedbackLibrary.round(named: newer.folderName, in: root) == nil)
        #expect(!FeedbackLibrary.bundleFilesNeedRepair(folderName: newer.folderName, in: root))
    }

    @Test("Reads the schema number before the rest of the round")
    func readsSchemaFirst() {
        let future = Data(#"{"schemaVersion": 99, "name": 7, "captures": "x"}"#.utf8)
        #expect(FeedbackLibrary.read(future) == .newerSchema(99))
        #expect(FeedbackLibrary.read(Data("{not json".utf8)) == .unreadable)
        let current = Data(#"{"schemaVersion": 1}"#.utf8)
        #expect(FeedbackLibrary.read(current) == .unreadable)
    }

    @Test("Ignores plain files and folders without feedback.json")
    func ignoresStrayEntries() throws {
        defer { try? fileManager.removeItem(at: root) }
        try Data("{\"folderName\":\"x\"}".utf8).write(to: root.appendingPathComponent(".active.json"))
        try fileManager.createDirectory(at: root.appendingPathComponent("empty-folder", isDirectory: true), withIntermediateDirectories: true)

        let listing = FeedbackLibrary.recent(in: root)
        #expect(listing.unreadable == [])
        #expect(listing.rounds.isEmpty)
    }

    @Test("Returns an empty listing when the root folder does not exist")
    func missingRoot() {
        defer { try? fileManager.removeItem(at: root) }
        let listing = FeedbackLibrary.recent(in: root.appendingPathComponent("nope", isDirectory: true))
        #expect(listing == FeedbackLibrary.Listing(rounds: [], unreadable: []))
    }

    @Test("Loads one round by folder name, nil when missing")
    func loadsOneRound() throws {
        defer { try? fileManager.removeItem(at: root) }
        let round = try write(ended(day: 12))

        #expect(FeedbackLibrary.round(named: round.folderName, in: root) == round)
        #expect(FeedbackLibrary.round(named: "2026-10-01-0900-missing", in: root) == nil)
        #expect(FeedbackLibrary.round(named: "../\(round.folderName)", in: root) == nil)
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
        #expect(FeedbackLibrary.subtitle(for: s, selectedCount: 0) == "Preview, TextEdit, +1, 5 captures")
        #expect(FeedbackLibrary.subtitle(for: s, selectedCount: 2) == "Preview, TextEdit, +1, 5 captures, 2 selected")

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

    @Test("Lists a round's captures newest first and leaves the round in capture order")
    func capturesNewestFirst() {
        defer { try? fileManager.removeItem(at: root) }
        var s = ended(day: 21)
        s.captures = [
            capture(1, title: "first"),
            capture(2, title: "second"),
            capture(3, title: "third"),
        ]
        s.captures[0].capturedAt = date(21, 11, 19)
        s.captures[1].capturedAt = date(21, 11, 58)
        s.captures[2].capturedAt = date(21, 12, 1)

        #expect(FeedbackLibrary.capturesNewestFirst(s).map(\.index) == [3, 2, 1])
        #expect(s.captures.map(\.index) == [1, 2, 3])
    }

    @Test("Breaks a tie in capture time by putting the higher index first")
    func capturesNewestFirstTie() {
        defer { try? fileManager.removeItem(at: root) }
        var s = ended(day: 21)
        s.captures = [capture(1), capture(2), capture(3)]
        #expect(FeedbackLibrary.capturesNewestFirst(s).map(\.index) == [3, 2, 1])
    }

    @Test("Lists no captures for a round with none")
    func capturesNewestFirstEmpty() {
        defer { try? fileManager.removeItem(at: root) }
        var s = ended(day: 21)
        s.captures = []
        #expect(FeedbackLibrary.capturesNewestFirst(s).isEmpty)
    }

    @Test("Counts items as a short text")
    func countsItems() {
        defer { try? fileManager.removeItem(at: root) }
        #expect(FeedbackLibrary.itemCountText(capture(1, badges: [])) == "No items")
        #expect(FeedbackLibrary.itemCountText(capture(1, badges: [1])) == "1 item")
        #expect(FeedbackLibrary.itemCountText(capture(1, badges: [1, 2, 3, 4])) == "4 items")
    }

    private func historyDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func historyRound(_ name: String, _ startedAt: String) -> FeedbackRound {
        var round = ended(day: 21)
        round.folderName = name
        round.startedAt = historyDate(startedAt)
        round.endedAt = round.startedAt.addingTimeInterval(60)
        return round
    }

    private func historyCalendar(firstWeekday: Int = 1, zone: String = "America/Los_Angeles") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    @Test("History covers every round once across day, week, and month boundaries")
    func historyGroupsEveryRound() {
        defer { try? fileManager.removeItem(at: root) }
        let rounds = [
            historyRound("today", "2026-10-27T10:00:00-07:00"),
            historyRound("yesterday", "2026-10-26T10:00:00-07:00"),
            historyRound("six-days", "2026-10-21T10:00:00-07:00"),
            historyRound("seven-days", "2026-10-20T10:00:00-07:00"),
            historyRound("last-week", "2026-09-06T10:00:00-07:00"),
            historyRound("month-september", "2026-09-05T10:00:00-07:00"),
            historyRound("month-august", "2026-08-31T10:00:00-07:00"),
            historyRound("last-year", "2025-12-31T10:00:00-08:00"),
        ]
        let groups = FeedbackHistory.groups(Array(rounds.reversed()), now: historyDate("2026-10-27T12:00:00-07:00"), calendar: historyCalendar(), locale: en)
        #expect(groups.map { $0.rounds.map(\.folderName) } == [
            ["today"], ["yesterday"], ["six-days"], ["seven-days"],
            ["last-week"], ["month-september"], ["month-august"], ["last-year"],
        ])
        #expect(groups[0].title == "Today")
        #expect(groups[1].title == "Yesterday")
        #expect(groups[3].title.hasPrefix("Week of "))
        #expect(groups[4].title.hasPrefix("Week of "))
        #expect(groups[5].title == "September 2026")
        #expect(groups[7].title == "December 2025")
        let actual = groups.flatMap(\.rounds).map(\.folderName)
        let expected = Set(rounds.map(\.folderName))
        #expect(!expected.isEmpty)
        #expect(!actual.isEmpty)
        #expect(Set(actual) == expected)
        #expect(actual.count == expected.count)
    }

    @Test("History follows the calendar's Sunday or Monday week start")
    func historyWeekStarts() {
        defer { try? fileManager.removeItem(at: root) }
        let rounds = [
            historyRound("sunday", "2026-11-01T12:00:00-08:00"),
            historyRound("monday", "2026-11-02T12:00:00-08:00"),
        ]
        let now = historyDate("2026-11-10T12:00:00-08:00")
        let sunday = FeedbackHistory.groups(rounds, now: now, calendar: historyCalendar(), locale: en)
        let monday = FeedbackHistory.groups(rounds, now: now, calendar: historyCalendar(firstWeekday: 2), locale: en)
        #expect(sunday.map { $0.rounds.map(\.folderName) } == [["monday", "sunday"]])
        #expect(monday.map { $0.rounds.map(\.folderName) } == [["monday"], ["sunday"]])
    }

    @Test("History uses local midnight through the daylight saving change")
    func historyLocalDayBoundaries() {
        defer { try? fileManager.removeItem(at: root) }
        let rounds = [
            historyRound("today", "2026-11-03T08:01:00Z"),
            historyRound("yesterday", "2026-11-03T07:59:00Z"),
            historyRound("first-hour", "2026-11-01T01:30:00-07:00"),
            historyRound("second-hour", "2026-11-01T01:30:00-08:00"),
            historyRound("six-days", "2026-10-28T00:00:00-07:00"),
            historyRound("seven-days", "2026-10-27T23:59:00-07:00"),
        ]
        let groups = FeedbackHistory.groups(rounds, now: historyDate("2026-11-03T08:02:00Z"), calendar: historyCalendar(), locale: en)
        #expect(groups.map { $0.rounds.map(\.folderName) } == [
            ["today"], ["yesterday"], ["second-hour", "first-hour"], ["six-days"], ["seven-days"],
        ])
        #expect(groups[0].title == "Today")
        #expect(groups[1].title == "Yesterday")
        #expect(groups[4].title.hasPrefix("Week of "))
    }

    @Test("History uses start dates, preserves ties, and excludes active or empty rounds")
    func historyIdentityAndEligibility() {
        defer { try? fileManager.removeItem(at: root) }
        var old = historyRound("old", "2026-10-01T10:00:00-07:00")
        old.endedAt = historyDate("2026-10-27T10:00:00-07:00")
        let a = historyRound("a", "2026-10-02T10:00:00-07:00")
        var b = a
        b.folderName = "b"
        var active = a
        active.endedAt = nil
        var empty = a
        empty.captures = []
        let now = historyDate("2026-10-27T12:00:00-07:00")
        let groups = FeedbackHistory.groups([old, active, empty, a, b], now: now, calendar: historyCalendar(), locale: en)
        #expect(groups.map { $0.rounds.map(\.folderName) } == [["b", "a", "old"]])
        #expect(groups[0].title.hasPrefix("Week of "))
        #expect(FeedbackHistory.groups([], now: now, calendar: historyCalendar(), locale: en).isEmpty)
    }

    @Test("History labels dates across years and future dates explicitly")
    func historyYearsAndFutureDates() {
        defer { try? fileManager.removeItem(at: root) }
        let rounds = [
            historyRound("future", "2027-01-04T10:00:00-08:00"),
            historyRound("last-year-day", "2026-12-31T10:00:00-08:00"),
            historyRound("last-year-week", "2026-12-27T10:00:00-08:00"),
            historyRound("last-year-month", "2026-11-01T10:00:00-08:00"),
        ]
        let groups = FeedbackHistory.groups(rounds, now: historyDate("2027-01-03T12:00:00-08:00"), calendar: historyCalendar(), locale: en)
        #expect(groups.count == 4)
        #expect(groups[0].title != "Today")
        #expect(groups[0].title.contains("Jan"))
        #expect(groups[1].title.contains("2026"))
        #expect(groups[2].title.hasPrefix("Week of "))
        #expect(groups[2].title.contains("2026"))
        #expect(groups[3].title == "November 2026")
    }

    @Test("History groups the same instant in the supplied time zone")
    func historyTimeZones() {
        defer { try? fileManager.removeItem(at: root) }
        let round = historyRound("round", "2026-10-26T23:45:00Z")
        let now = historyDate("2026-10-27T00:30:00Z")
        let local = FeedbackHistory.groups([round], now: now, calendar: historyCalendar(), locale: en)
        let utc = FeedbackHistory.groups([round], now: now, calendar: historyCalendar(zone: "UTC"), locale: en)
        #expect(local.first?.title == "Today")
        #expect(utc.first?.title == "Yesterday")
    }
}
