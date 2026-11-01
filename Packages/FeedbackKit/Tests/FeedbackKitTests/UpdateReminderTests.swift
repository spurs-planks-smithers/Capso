import Foundation
import Testing
@testable import FeedbackKit

private let day: TimeInterval = 24 * 60 * 60
private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let allOn = UpdateReminder.Gates(flagOn: true, enabled: true, automaticUpdates: false)

/// One check with plain defaults: rounds exist and the app is idle.
private func check(
    _ state: UpdateReminder.State,
    after days: Double,
    build: String = "900",
    gates: UpdateReminder.Gates = allOn,
    hasRounds: Bool = true,
    isIdle: Bool = true
) -> UpdateReminder.Result {
    UpdateReminder.evaluate(
        state: state,
        now: start.addingTimeInterval(days * day),
        build: build,
        gates: gates,
        hasRounds: { hasRounds },
        isIdle: { isIdle }
    )
}

/// The state after the first run of build 900 at `start`.
private func firstRun() -> UpdateReminder.State {
    check(UpdateReminder.State(), after: 0).state
}

@Suite("UpdateReminder")
struct UpdateReminderTests {
    @Test("The first run of a build records the build and the time, and shows nothing")
    func firstRunRecordsClock() {
        let result = check(UpdateReminder.State(), after: 0)
        #expect(result.display == .nothing)
        #expect(result.state.buildSeen == "900")
        #expect(result.state.buildFirstRun == start)
    }

    @Test("Day 6 shows nothing and day 7 shows the toast and the row")
    func sevenDays() {
        let state = firstRun()
        #expect(check(state, after: 6.99).display == .nothing)
        #expect(check(state, after: 7).display == .toastAndRow)
    }

    @Test("The toast waits for an idle moment, and the row does not")
    func toastWaitsForIdle() {
        let state = firstRun()
        let busy = check(state, after: 8, isIdle: false)
        #expect(busy.display == .row)
        #expect(busy.state.toastShownForBuild == nil)
        let idle = check(busy.state, after: 8.1)
        #expect(idle.display == .toastAndRow)
        #expect(idle.state.toastShownForBuild == "900")
    }

    @Test("The toast shows once per build, then only the row stays")
    func toastOnce() {
        let first = check(firstRun(), after: 7)
        #expect(first.display == .toastAndRow)
        let second = check(first.state, after: 8)
        #expect(second.display == .row)
        let later = check(second.state, after: 40)
        #expect(later.display == .row)
    }

    @Test("A person with no saved round gets nothing")
    func needsRounds() {
        #expect(check(firstRun(), after: 30, hasRounds: false).display == .nothing)
    }

    @Test("The rounds and idle checks run only after the wait, so a menu open reads no folder early")
    func checksAreLazy() {
        var roundsChecked = 0
        var idleChecked = 0
        _ = UpdateReminder.evaluate(
            state: firstRun(), now: start.addingTimeInterval(3 * day), build: "900", gates: allOn,
            hasRounds: { roundsChecked += 1; return true }, isIdle: { idleChecked += 1; return true }
        )
        #expect(roundsChecked == 0 && idleChecked == 0)
    }

    @Test("A new build restarts the clock and clears both marks")
    func newBuildResets() {
        let shown = check(firstRun(), after: 9)
        let hidden = UpdateReminder.hidingRow(shown.state, build: "900")
        #expect(hidden.rowHiddenForBuild == "900")

        let updated = check(hidden, after: 10, build: "910")
        #expect(updated.display == .nothing)
        #expect(updated.state.buildSeen == "910")
        #expect(updated.state.buildFirstRun == start.addingTimeInterval(10 * day))
        #expect(updated.state.toastShownForBuild == nil)
        #expect(updated.state.rowHiddenForBuild == nil)

        #expect(check(updated.state, after: 16.99, build: "910").display == .nothing)
        #expect(check(updated.state, after: 17, build: "910").display == .toastAndRow)
    }

    @Test("A click on the row hides the row and the toast for that build")
    func rowClickHides() {
        let hidden = UpdateReminder.hidingRow(firstRun(), build: "900")
        #expect(check(hidden, after: 20).display == .nothing)
    }

    @Test("Each switch turns the reminder off, and the clock still runs")
    func switchesTurnItOff() {
        let state = firstRun()
        let off = [
            UpdateReminder.Gates(flagOn: false, enabled: true, automaticUpdates: false),
            UpdateReminder.Gates(flagOn: true, enabled: false, automaticUpdates: false),
            UpdateReminder.Gates(flagOn: true, enabled: true, automaticUpdates: true),
        ]
        for gates in off {
            let result = check(state, after: 20, gates: gates)
            #expect(result.display == .nothing, "\(gates)")
            #expect(result.state.buildFirstRun == start, "\(gates) moved the clock")
        }
    }

    @Test("A clock set back restarts the wait and keeps the marks")
    func clockSetBack() {
        let shown = check(firstRun(), after: 8)
        #expect(shown.display == .toastAndRow)
        let back = check(shown.state, after: -3)
        #expect(back.display == .nothing)
        #expect(back.state.buildFirstRun == start.addingTimeInterval(-3 * day))
        #expect(back.state.toastShownForBuild == "900")
    }

    @Test("The state round-trips through UserDefaults, and an empty suite reads as an empty state")
    func stateStorage() throws {
        let suite = "UpdateReminderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(UpdateReminder.State(defaults: defaults) == UpdateReminder.State())

        let state = UpdateReminder.State(
            buildSeen: "900", buildFirstRun: start, toastShownForBuild: "900", rowHiddenForBuild: "899"
        )
        state.save(to: defaults)
        #expect(UpdateReminder.State(defaults: defaults) == state)

        // A mark that goes back to nil leaves no stale value behind.
        UpdateReminder.State(buildSeen: "901", buildFirstRun: start).save(to: defaults)
        let reread = UpdateReminder.State(defaults: defaults)
        #expect(reread.toastShownForBuild == nil)
        #expect(reread.rowHiddenForBuild == nil)
    }

    @Test("The switch defaults to on and reads a stored false")
    func enabledSwitch() throws {
        let suite = "UpdateReminderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(UpdateReminder.isEnabled(defaults))
        defaults.set(false, forKey: UpdateReminder.enabledKey)
        #expect(!UpdateReminder.isEnabled(defaults))
    }

    @Test("The link carries the version after the # sign, and only safe characters")
    func link() {
        #expect(UpdateReminder.link(version: "0.5.0").absoluteString == "https://nextshot.dev/#from=0.5.0")
        #expect(UpdateReminder.link(version: "0.5.0-dev").absoluteString == "https://nextshot.dev/#from=0.5.0-dev")
        #expect(UpdateReminder.link(version: "").absoluteString == "https://nextshot.dev/")
        // Nothing but letters, digits, dots, and hyphens passes. The version
        // never gains a query or a second fragment.
        let odd = UpdateReminder.link(version: "1.2.3?x=1 #y<script>")
        #expect(odd.query == nil)
        #expect(odd.fragment == "from=1.2.3x1yscript")
    }

    @Test("The link never puts the version in the part a server sees")
    func linkHidesVersionFromServer() {
        let url = UpdateReminder.link(version: "0.5.0")
        #expect(url.host == "nextshot.dev")
        #expect(url.path == "/")
        #expect(url.query == nil)
    }

    @Test("The toast and the row use the product's own names and fit one line each")
    func words() {
        let text = UpdateReminder.toastText(productName: "Nextshot", menuName: "Nshot")
        #expect(text == "New Nextshot builds ship often.\nNextshot stays offline, so check the Nshot menu.")
        for line in text.split(separator: "\n") {
            #expect(line.count < 60, "\(line)")
        }
        #expect(UpdateReminder.toastText(productName: "Nextshot", menuName: "Nshot Dev").contains("Nshot Dev menu"))
        #expect(UpdateReminder.rowTitle == "Get the latest version…")
    }
}
