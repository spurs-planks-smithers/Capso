import FeedbackKit
import XCTest
@testable import Capso

/// Fork: the offline update reminder's coordinator (#203). The rules have
/// their own tests in FeedbackKit (`UpdateReminderTests`). These check that
/// the coordinator wires them to the clock, the idle check, the toast, and
/// the link. It uses a private defaults suite and fake closures, so no timer
/// runs and nothing opens.
@MainActor
final class FeedbackUpdateReminderTests: XCTestCase {
    private static let day: TimeInterval = 24 * 60 * 60

    private var suite = ""
    private var defaults: UserDefaults!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var flagOn = true
    private var idle = true
    private var hasRounds = true
    private var toasts: [String] = []
    private var opened: [URL] = []

    override func setUp() async throws {
        suite = "FeedbackUpdateReminderTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        flagOn = true
        idle = true
        hasRounds = true
        toasts = []
        opened = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeReminder(build: String = "900") -> FeedbackUpdateReminder {
        FeedbackUpdateReminder(
            defaults: defaults,
            version: "0.5.0",
            build: build,
            now: { [unowned self] in self.clock },
            gates: { [unowned self] in
                UpdateReminder.Gates(flagOn: self.flagOn, enabled: UpdateReminder.isEnabled(self.defaults), automaticUpdates: false)
            },
            hasRounds: { [unowned self] in self.hasRounds },
            isIdle: { [unowned self] in self.idle },
            showToast: { [unowned self] in self.toasts.append($0) },
            openLink: { [unowned self] in self.opened.append($0) }
        )
    }

    private func advance(days: Double) {
        clock = clock.addingTimeInterval(days * Self.day)
    }

    func testRowAppearsAfterSevenDaysAndTheMenuNeverShowsTheToast() {
        let reminder = makeReminder()
        XCTAssertFalse(reminder.menuRowVisible(), "the first run starts the clock")
        advance(days: 6.9)
        XCTAssertFalse(reminder.menuRowVisible())
        advance(days: 0.2)
        XCTAssertTrue(reminder.menuRowVisible())
        XCTAssertTrue(toasts.isEmpty, "a menu open must not raise a toast")
    }

    func testRecheckShowsTheToastOnceAtAnIdleMoment() {
        let reminder = makeReminder()
        _ = reminder.menuRowVisible()
        advance(days: 8)

        idle = false
        reminder.recheck()
        XCTAssertTrue(toasts.isEmpty, "no toast while a round or capture is open")

        idle = true
        reminder.recheck()
        XCTAssertEqual(toasts, [UpdateReminder.toastText(productName: ForkBranding.name, menuName: ForkBranding.shortName)])

        reminder.recheck()
        advance(days: 3)
        reminder.recheck()
        XCTAssertEqual(toasts.count, 1, "the toast shows once per build")
        XCTAssertTrue(reminder.menuRowVisible(), "the row stays")
    }

    func testNoToastWithoutASavedRound() {
        let reminder = makeReminder()
        _ = reminder.menuRowVisible()
        advance(days: 20)
        hasRounds = false
        reminder.recheck()
        XCTAssertTrue(toasts.isEmpty)
        XCTAssertFalse(reminder.menuRowVisible())
    }

    func testOpenSiteOpensTheLinkWithTheVersionAndHidesTheRow() {
        let reminder = makeReminder()
        _ = reminder.menuRowVisible()
        advance(days: 8)
        XCTAssertTrue(reminder.menuRowVisible())

        reminder.openSite()
        XCTAssertEqual(opened.map(\.absoluteString), ["https://nextshot.dev/#from=0.5.0"])
        XCTAssertFalse(reminder.menuRowVisible())
        reminder.recheck()
        XCTAssertTrue(toasts.isEmpty, "a person who clicked gets no toast")
    }

    func testANewBuildStartsTheWaitAgain() {
        let first = makeReminder(build: "900")
        _ = first.menuRowVisible()
        advance(days: 8)
        XCTAssertTrue(first.menuRowVisible())

        let updated = makeReminder(build: "910")
        XCTAssertFalse(updated.menuRowVisible(), "an updated copy stays quiet")
        advance(days: 7)
        XCTAssertTrue(updated.menuRowVisible())
    }

    func testTheFlagAndTheSettingsToggleHideTheRow() {
        let reminder = makeReminder()
        _ = reminder.menuRowVisible()
        advance(days: 8)
        XCTAssertTrue(reminder.menuRowVisible())

        flagOn = false
        XCTAssertFalse(reminder.menuRowVisible())
        flagOn = true
        XCTAssertTrue(reminder.menuRowVisible())

        defaults.set(false, forKey: UpdateReminder.enabledKey)
        XCTAssertFalse(reminder.menuRowVisible())
    }
}
