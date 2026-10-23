import XCTest
@testable import Capso
import SharedKit

/// Stand-in for Sparkle's `SPUUpdater` so `UpdateManager` can be exercised
/// without starting a real updater inside the test host.
@MainActor
final class FakeSoftwareUpdater: SoftwareUpdating {
    var canCheckForUpdates = true
    var updateCheckInterval: TimeInterval = 86_400
    var checkForUpdateInformationCount = 0
    var checkForUpdatesCount = 0

    var automaticallyChecksForUpdates = true {
        didSet { automaticallyChecksForUpdatesWriteCount += 1 }
    }
    private(set) var automaticallyChecksForUpdatesWriteCount = 0

    var storedAutomaticallyDownloadsUpdates = false {
        didSet { automaticallyDownloadsUpdatesWriteCount += 1 }
    }
    private(set) var automaticallyDownloadsUpdatesWriteCount = 0

    func checkForUpdateInformation() {
        checkForUpdateInformationCount += 1
    }

    func checkForUpdates() {
        checkForUpdatesCount += 1
    }
}

/// The values Sparkle starts from before the user picks anything, which live in
/// the app's Info.plist rather than in code.
///
/// These are deliberately unchanged by this feature: an existing install has
/// nothing stored for them, so editing the plist would silently move everyone
/// who upgrades. Anyone who wants a different interval can pick one.
final class ShippedUpdateDefaultsTests: XCTestCase {
    // Fork: security baseline rec 1 turns Sparkle's automatic checks off.
    func testAutomaticChecksAreOffInTheFork() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool, false)
    }

    func testAutomaticInstallIsOffByDefault() {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: AutomaticInstallPreference.key))
    }

    func testDefaultCheckFrequencyIsDaily() {
        let interval = Bundle.main.object(forInfoDictionaryKey: "SUScheduledCheckInterval") as? TimeInterval

        XCTAssertEqual(interval, UpdateCheckFrequency.daily.timeInterval)
        XCTAssertEqual(UpdateCheckFrequency(closestTo: interval ?? 0), .daily)
    }
}

/// Sparkle drops `setAutomaticallyDownloadsUpdates:` while automatic checks are
/// off, so Capso persists the preference by writing Sparkle's own key. These
/// cover that storage directly, since no stand-in updater can catch it.
final class AutomaticInstallPreferenceTests: XCTestCase {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaultsToFalseWhenNothingIsStored() {
        let defaults = makeDefaults("test.automaticInstall.unset")

        XCTAssertFalse(AutomaticInstallPreference.value(in: defaults, fallback: nil))
    }

    func testFallsBackToTheInfoPlistValue() {
        let defaults = makeDefaults("test.automaticInstall.fallback")

        XCTAssertTrue(AutomaticInstallPreference.value(in: defaults, fallback: true))
        XCTAssertFalse(AutomaticInstallPreference.value(in: defaults, fallback: false))
    }

    func testStoredValueWinsOverTheInfoPlistValue() {
        let defaults = makeDefaults("test.automaticInstall.override")

        AutomaticInstallPreference.setValue(false, in: defaults)

        XCTAssertFalse(AutomaticInstallPreference.value(in: defaults, fallback: true))
    }

    func testWritingPersistsUnderSparklesOwnKey() {
        let defaults = makeDefaults("test.automaticInstall.persist")

        AutomaticInstallPreference.setValue(true, in: defaults)

        XCTAssertTrue(AutomaticInstallPreference.value(in: defaults, fallback: nil))
        XCTAssertEqual(defaults.object(forKey: "SUAutomaticallyUpdate") as? Bool, true)
    }
}

@MainActor
final class UpdateManagerTests: XCTestCase {
    func testInitReadsCurrentUpdaterState() {
        let updater = FakeSoftwareUpdater()
        updater.canCheckForUpdates = false
        updater.storedAutomaticallyDownloadsUpdates = true

        let manager = UpdateManager(updater: updater)

        XCTAssertFalse(manager.canCheckForUpdates)
        XCTAssertTrue(manager.automaticallyDownloadsUpdates)
    }

    func testInitReadsAutomaticCheckSetting() {
        let updater = FakeSoftwareUpdater()
        updater.automaticallyChecksForUpdates = false

        let manager = UpdateManager(updater: updater)

        XCTAssertFalse(manager.automaticallyChecksForUpdates)
    }

    func testDisablingAutomaticChecksWritesThroughToTheUpdater() {
        let updater = FakeSoftwareUpdater()
        let manager = UpdateManager(updater: updater)

        manager.automaticallyChecksForUpdates = false

        XCTAssertFalse(updater.automaticallyChecksForUpdates)
    }

    func testEnablingAutomaticChecksWritesThroughToTheUpdater() {
        let updater = FakeSoftwareUpdater()
        updater.automaticallyChecksForUpdates = false
        let manager = UpdateManager(updater: updater)

        manager.automaticallyChecksForUpdates = true

        XCTAssertTrue(updater.automaticallyChecksForUpdates)
    }

    func testSettingTheSameAutomaticCheckValueDoesNotRewrite() {
        let updater = FakeSoftwareUpdater()
        let manager = UpdateManager(updater: updater)
        let writes = updater.automaticallyChecksForUpdatesWriteCount

        manager.automaticallyChecksForUpdates = true

        XCTAssertEqual(updater.automaticallyChecksForUpdatesWriteCount, writes)
    }

    func testInitDerivesFrequencyFromTheUpdaterInterval() {
        let updater = FakeSoftwareUpdater()
        updater.updateCheckInterval = UpdateCheckFrequency.weekly.timeInterval

        let manager = UpdateManager(updater: updater)

        XCTAssertEqual(manager.updateCheckFrequency, .weekly)
    }

    func testInitSnapsAnUnknownIntervalToTheClosestFrequency() {
        let updater = FakeSoftwareUpdater()
        updater.updateCheckInterval = 3_600

        let manager = UpdateManager(updater: updater)

        XCTAssertEqual(manager.updateCheckFrequency, .daily)
    }

    func testChangingFrequencyWritesTheIntervalToTheUpdater() {
        let updater = FakeSoftwareUpdater()
        let manager = UpdateManager(updater: updater)

        manager.updateCheckFrequency = .monthly

        XCTAssertEqual(updater.updateCheckInterval, UpdateCheckFrequency.monthly.timeInterval)
    }

    func testChangingFrequencyLeavesTheAutomaticCheckSettingAlone() {
        let updater = FakeSoftwareUpdater()
        let manager = UpdateManager(updater: updater)
        let writes = updater.automaticallyChecksForUpdatesWriteCount

        manager.updateCheckFrequency = .weekly

        XCTAssertTrue(updater.automaticallyChecksForUpdates)
        XCTAssertEqual(updater.automaticallyChecksForUpdatesWriteCount, writes)
    }

    func testFrequencyStillPersistsWhileAutomaticChecksAreOff() {
        let updater = FakeSoftwareUpdater()
        updater.automaticallyChecksForUpdates = false
        let manager = UpdateManager(updater: updater)

        manager.updateCheckFrequency = .weekly

        XCTAssertEqual(updater.updateCheckInterval, UpdateCheckFrequency.weekly.timeInterval)
    }

    func testDisablingAutomaticChecksLeavesTheAutomaticInstallToggleOn() {
        let updater = FakeSoftwareUpdater()
        updater.storedAutomaticallyDownloadsUpdates = true
        let manager = UpdateManager(updater: updater)

        manager.automaticallyChecksForUpdates = false

        XCTAssertTrue(manager.automaticallyDownloadsUpdates)
        XCTAssertTrue(updater.storedAutomaticallyDownloadsUpdates)
    }

    func testDisablingAutomaticChecksNeverWritesTheAutomaticInstallPreference() {
        let updater = FakeSoftwareUpdater()
        updater.storedAutomaticallyDownloadsUpdates = true
        let manager = UpdateManager(updater: updater)
        let writes = updater.automaticallyDownloadsUpdatesWriteCount

        manager.automaticallyChecksForUpdates = false

        XCTAssertEqual(updater.automaticallyDownloadsUpdatesWriteCount, writes)
    }

    func testAutomaticInstallWritesStillPersistWhileAutomaticChecksAreOff() {
        let updater = FakeSoftwareUpdater()
        updater.automaticallyChecksForUpdates = false
        let manager = UpdateManager(updater: updater)

        manager.automaticallyDownloadsUpdates = true

        XCTAssertTrue(updater.storedAutomaticallyDownloadsUpdates)
    }

    func testInitReadsTheStoredAutomaticInstallPreferenceWhileChecksAreOff() {
        let updater = FakeSoftwareUpdater()
        updater.automaticallyChecksForUpdates = false
        updater.storedAutomaticallyDownloadsUpdates = true

        let manager = UpdateManager(updater: updater)

        XCTAssertTrue(manager.automaticallyDownloadsUpdates)
    }

    func testEnablingAutomaticChecksLeavesTheAutomaticInstallToggleOff() {
        let updater = FakeSoftwareUpdater()
        updater.automaticallyChecksForUpdates = false
        updater.storedAutomaticallyDownloadsUpdates = false
        let manager = UpdateManager(updater: updater)

        manager.automaticallyChecksForUpdates = true

        XCTAssertFalse(manager.automaticallyDownloadsUpdates)
        XCTAssertFalse(updater.storedAutomaticallyDownloadsUpdates)
    }

    func testManualCheckStillRunsWhileAutomaticChecksAreOff() {
        let updater = FakeSoftwareUpdater()
        updater.automaticallyChecksForUpdates = false
        let manager = UpdateManager(updater: updater)

        manager.checkForUpdates()

        XCTAssertEqual(updater.checkForUpdateInformationCount, 1)
        XCTAssertEqual(manager.status?.kind, .checking)
    }

    func testManualCheckIsIgnoredWhenTheUpdaterCannotCheck() {
        let updater = FakeSoftwareUpdater()
        updater.canCheckForUpdates = false
        let manager = UpdateManager(updater: updater)

        manager.checkForUpdates()

        XCTAssertEqual(updater.checkForUpdateInformationCount, 0)
        XCTAssertNil(manager.status)
    }

    // MARK: Manual check with automatic checks off

    func testManualCheckWithAutomaticChecksOffAndAutomaticInstallOnTouchesNoPreference() {
        let updater = FakeSoftwareUpdater()
        updater.automaticallyChecksForUpdates = false
        updater.storedAutomaticallyDownloadsUpdates = true
        let manager = UpdateManager(updater: updater)
        let checkWrites = updater.automaticallyChecksForUpdatesWriteCount
        let installWrites = updater.automaticallyDownloadsUpdatesWriteCount

        manager.checkForUpdates()

        XCTAssertEqual(updater.checkForUpdateInformationCount, 1)
        XCTAssertEqual(updater.automaticallyChecksForUpdatesWriteCount, checkWrites)
        XCTAssertEqual(updater.automaticallyDownloadsUpdatesWriteCount, installWrites)
        XCTAssertFalse(manager.automaticallyChecksForUpdates)
        XCTAssertTrue(manager.automaticallyDownloadsUpdates)
    }

    func testManualProbeThatFindsAnUpdateEscalatesToTheInteractiveFlow() {
        let updater = FakeSoftwareUpdater()
        updater.automaticallyChecksForUpdates = false
        updater.storedAutomaticallyDownloadsUpdates = true
        let manager = UpdateManager(updater: updater)

        manager.checkForUpdates()
        manager.handleProbeFoundUpdate()
        manager.handleProbeFinished(error: nil)

        XCTAssertEqual(updater.checkForUpdatesCount, 1)
        XCTAssertNil(manager.status)
    }

    func testEscalatingAManualCheckLeavesBothPreferencesAlone() {
        let updater = FakeSoftwareUpdater()
        updater.automaticallyChecksForUpdates = false
        updater.storedAutomaticallyDownloadsUpdates = true
        let manager = UpdateManager(updater: updater)

        manager.checkForUpdates()
        manager.handleProbeFoundUpdate()
        manager.handleProbeFinished(error: nil)

        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        XCTAssertTrue(updater.storedAutomaticallyDownloadsUpdates)
    }

    func testManualProbeThatFindsNothingDoesNotEscalate() {
        let updater = FakeSoftwareUpdater()
        let manager = UpdateManager(updater: updater)

        manager.checkForUpdates()
        manager.handleProbeFinished(error: nil)

        XCTAssertEqual(updater.checkForUpdatesCount, 0)
    }

    func testFailedManualProbeDoesNotEscalate() {
        let updater = FakeSoftwareUpdater()
        let manager = UpdateManager(updater: updater)
        let failure = NSError(domain: "test.appcast", code: 42)

        manager.checkForUpdates()
        manager.handleProbeFoundUpdate()
        manager.handleProbeFinished(error: failure)

        XCTAssertEqual(updater.checkForUpdatesCount, 0)
    }

    func testProbeCallbacksArrivingOutsideAManualCheckAreIgnored() {
        let updater = FakeSoftwareUpdater()
        let manager = UpdateManager(updater: updater)

        manager.handleProbeFoundUpdate()
        manager.handleProbeFinished(error: nil)

        XCTAssertEqual(updater.checkForUpdatesCount, 0)
        XCTAssertNil(manager.status)
    }

    func testInitDoesNotWriteBackToTheUpdater() {
        let updater = FakeSoftwareUpdater()
        let checksWrites = updater.automaticallyChecksForUpdatesWriteCount
        let downloadsWrites = updater.automaticallyDownloadsUpdatesWriteCount

        _ = UpdateManager(updater: updater)

        XCTAssertEqual(updater.automaticallyChecksForUpdatesWriteCount, checksWrites)
        XCTAssertEqual(updater.automaticallyDownloadsUpdatesWriteCount, downloadsWrites)
    }
}
