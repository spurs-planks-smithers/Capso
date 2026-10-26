import XCTest
@testable import Capso

/// Fork: the rules for a starting copy of Nextshot (`LaunchPlan`). Builds
/// order by build number, so a SemVer release (0.3.0) is newer than the date
/// builds in the field (2026.10.24, build 524), although its version text
/// is lower.
final class LaunchPlanTests: XCTestCase {
    private let early = Date(timeIntervalSince1970: 1_000)
    private let late = Date(timeIntervalSince1970: 2_000)

    private let dateBuild = LaunchPlan.Build(version: "2026.10.24", number: 524)
    private let release = LaunchPlan.Build(version: "0.3.0", number: 625)
    private let nextRelease = LaunchPlan.Build(version: "0.3.1", number: 640)

    private func copy(
        _ pid: pid_t,
        _ build: LaunchPlan.Build,
        launched: Date? = nil,
        onImage: Bool = false
    ) -> LaunchPlan.Copy {
        LaunchPlan.Copy(pid: pid, build: build, launchDate: launched ?? early, onReadOnlyVolume: onImage)
    }

    // MARK: - Build order

    func testSemVerReleaseIsNewerThanTheDateBuildsInTheField() {
        XCTAssertTrue(dateBuild < release)
        XCTAssertFalse(release < dateBuild)
    }

    func testBuildNumberDecidesBeforeVersionText() {
        let lowerVersionHigherBuild = LaunchPlan.Build(version: "0.3.0", number: 700)
        let higherVersionLowerBuild = LaunchPlan.Build(version: "0.9.0", number: 650)
        XCTAssertTrue(higherVersionLowerBuild < lowerVersionHigherBuild)
    }

    func testVersionTextBreaksATieOnTheBuildNumber() {
        let a = LaunchPlan.Build(version: "0.3.0", number: 625)
        let b = LaunchPlan.Build(version: "0.3.1", number: 625)
        XCTAssertTrue(a < b)
        XCTAssertEqual(a, LaunchPlan.Build(version: "0.3.0", number: 625))
    }

    func testDevVersionTextKeepsItsNumbers() {
        let dev = LaunchPlan.Build(version: "0.3.0-dev", number: 631)
        XCTAssertEqual(dev.version, [0, 3, 0])
        XCTAssertEqual(dev.number, 631)
    }

    func testUnknownBuildIsOlderThanEveryRealBuild() {
        XCTAssertTrue(LaunchPlan.Build.unknown < dateBuild)
        XCTAssertTrue(LaunchPlan.Build.unknown < release)
    }

    func testDescriptionShowsVersionAndBuild() {
        XCTAssertEqual(release.description, "0.3.0 (625)")
        XCTAssertEqual(dateBuild.description, "2026.10.24 (524)")
    }

    // MARK: - A copy that starts from a normal folder

    func testNewReleaseAsksTheOldDateBuildToQuit() {
        let me = copy(20, release)
        let plan = LaunchPlan.decide(me: me, others: [copy(10, dateBuild)], installedBuild: nil)
        XCTAssertEqual(plan, .quitOlderCopies([10]))
    }

    func testOldDateBuildYieldsToARunningRelease() {
        let me = copy(20, dateBuild, launched: late)
        let plan = LaunchPlan.decide(me: me, others: [copy(10, release)], installedBuild: nil)
        XCTAssertEqual(plan, .yield(to: 10))
    }

    func testAloneRunsNormally() {
        XCTAssertEqual(LaunchPlan.decide(me: copy(20, release), others: [], installedBuild: nil), .run)
    }

    func testTwoCopiesOfOneBuildKeepTheOlderLaunch() {
        let first = copy(10, release, launched: early)
        let second = copy(20, release, launched: late)
        XCTAssertEqual(LaunchPlan.decide(me: second, others: [first], installedBuild: nil), .yield(to: 10))
        XCTAssertEqual(LaunchPlan.decide(me: first, others: [second], installedBuild: nil), .run)
    }

    // MARK: - A copy that starts from a disk image

    func testImageCopyOfANewerReleaseOffersToInstallOverTheDateBuild() {
        let me = copy(20, release, onImage: true)
        XCTAssertEqual(LaunchPlan.decide(me: me, others: [], installedBuild: dateBuild), .offerInstall)
    }

    func testImageCopyOffersToInstallOverARunningDateBuild() {
        let me = copy(20, release, onImage: true)
        let plan = LaunchPlan.decide(me: me, others: [copy(10, dateBuild)], installedBuild: dateBuild)
        XCTAssertEqual(plan, .offerInstall)
    }

    func testImageCopyOfAnOlderBuildOpensTheInstalledRelease() {
        let me = copy(20, dateBuild, onImage: true)
        XCTAssertEqual(LaunchPlan.decide(me: me, others: [], installedBuild: release), .openInstalled)
    }

    func testImageCopyOfTheSameBuildOpensTheInstalledCopy() {
        let me = copy(20, release, onImage: true)
        XCTAssertEqual(LaunchPlan.decide(me: me, others: [], installedBuild: release), .openInstalled)
    }

    func testImageCopyYieldsToARunningNewerInstalledCopy() {
        let me = copy(20, release, onImage: true)
        let plan = LaunchPlan.decide(me: me, others: [copy(10, nextRelease)], installedBuild: nextRelease)
        XCTAssertEqual(plan, .yield(to: 10))
    }

    func testImageCopyOffersToInstallWhenNothingIsInstalled() {
        let me = copy(20, release, onImage: true)
        XCTAssertEqual(LaunchPlan.decide(me: me, others: [], installedBuild: nil), .offerInstall)
    }
}
