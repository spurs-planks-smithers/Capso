// App/Feedback/SingleInstanceGuard.swift
import AppKit
import os

/// Fork: keeps one copy of the app running, the newest build. A scripted
/// relaunch once started two copies in the same second (2026-10-22), and
/// both registered the global hotkeys and both menu bar items. `AppDelegate`
/// calls this first, after its unit-test early return, so a copy that exits
/// sets up nothing.
///
/// Since 2026-10-25 it also runs the disk image install (`DiskImageInstaller`)
/// and lets a newer build replace an older running one. `LaunchPlan` holds
/// the rules.
@MainActor
enum SingleInstanceGuard {
    private static let logger = Logger(subsystem: "com.drewschulz.nextshot", category: "Launch")

    /// The installer copy passes its process ID after this argument, so the
    /// installed copy waits for it to exit before it decides anything.
    static let installedByArgument = "--nextshot-installed-by"

    /// Returns when this copy should start. Otherwise exits, after it brings
    /// the copy that stays to the front or installs this one.
    static func quitIfAnotherCopyRuns() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        waitForInstallerToExit()

        let current = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated && $0.processIdentifier != current.processIdentifier }
        let me = copy(of: current, bundleURL: Bundle.main.bundleURL, launchedNow: true)
        let destination = me.onReadOnlyVolume ? DiskImageInstaller.destination(runningCopies: others) : nil
        let installedBuild = destination.flatMap { FileManager.default.fileExists(atPath: $0.path) ? DiskImageInstaller.build(of: $0) : nil }

        let plan = LaunchPlan.decide(
            me: me,
            others: others.map { copy(of: $0, bundleURL: $0.bundleURL, launchedNow: false) },
            installedBuild: installedBuild
        )
        logger.notice("Launch plan for build \(me.build.description, privacy: .public): \(String(describing: plan), privacy: .public)")
        // The running copies that are not on an image, for the install dialogs.
        let installed = others.filter { app in
            !(app.bundleURL.map(DiskImageInstaller.isOnReadOnlyVolume) ?? false)
        }

        switch plan {
        case .run:
            break
        case .quitOlderCopies(let pids):
            let older = others.filter { pids.contains($0.processIdentifier) }
            older.forEach { $0.terminate() }
            if !waitUntilGone(pids, timeout: 10), let stuck = older.first(where: { !$0.isTerminated }) {
                // Two running copies would fight over the hotkeys, so the old one stays.
                logger.notice("Older copy pid \(stuck.processIdentifier) did not quit. Quitting pid \(current.processIdentifier).")
                stuck.activate()
                exit(0)
            }
        case .yield(let pid):
            if me.onReadOnlyVolume, let destination {
                DiskImageInstaller.offerReplaceNewer(destination: destination, runningCopies: installed)
            }
            logger.notice("Another copy runs (pid \(pid)). Quitting pid \(current.processIdentifier).")
            others.first { $0.processIdentifier == pid }?.activate()
            exit(0)
        case .openInstalled:
            if let destination {
                DiskImageInstaller.offerReplaceNewer(destination: destination, runningCopies: [])
                DiskImageInstaller.openAndExit(destination)
            }
        case .offerInstall:
            if let destination {
                DiskImageInstaller.offerInstall(destination: destination, runningCopies: installed)
                // Not Now, or the install failed: run from the image, unless
                // another copy still runs. An installed copy goes first.
                if let keeper = (installed + others).first(where: { !$0.isTerminated }) {
                    keeper.activate()
                    exit(0)
                }
            }
        }

        if !me.onReadOnlyVolume {
            let ownBundle = Bundle.main.bundleURL
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                DiskImageInstaller.ejectLeftoverImages(skipping: ownBundle)
            }
        }
    }

    /// Waits while any of `pids` runs, at most `timeout` seconds. Runs the
    /// main run loop meanwhile, so AppKit can deliver the quit replies.
    static func waitUntilGone(_ pids: [pid_t], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
        while pids.contains(where: alive), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        return !pids.contains(where: alive)
    }

    /// The installer copy is still exiting when it opens this copy.
    private static func waitForInstallerToExit() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: installedByArgument),
              index + 1 < arguments.count,
              let pid = pid_t(arguments[index + 1]) else { return }
        if !waitUntilGone([pid], timeout: 5) {
            logger.notice("The installer copy (pid \(pid)) still runs after 5 seconds.")
        }
    }

    private static func copy(of app: NSRunningApplication, bundleURL: URL?, launchedNow: Bool) -> LaunchPlan.Copy {
        LaunchPlan.Copy(
            pid: app.processIdentifier,
            build: DiskImageInstaller.build(of: bundleURL),
            // macOS may not list this copy's launch date yet. It is the newest.
            launchDate: app.launchDate ?? (launchedNow ? Date() : .distantPast),
            onReadOnlyVolume: bundleURL.map(DiskImageInstaller.isOnReadOnlyVolume) ?? false
        )
    }
}
