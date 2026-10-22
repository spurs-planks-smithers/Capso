// App/Feedback/SingleInstanceGuard.swift
import AppKit
import os

/// Fork: keeps one copy of the app running. A scripted relaunch once started
/// two copies in the same second (2026-10-22), and both registered the global
/// hotkeys and both menu bar items. `AppDelegate` calls this first, after its
/// unit-test early return, so a second copy sets up nothing.
@MainActor
enum SingleInstanceGuard {
    private static let logger = Logger(subsystem: "com.drewschulz.nextshot", category: "Launch")

    /// When another copy with this bundle ID runs, activates the oldest copy
    /// and exits this one. Two copies that start together both see each
    /// other, so only the oldest (earliest launch, then lowest process ID)
    /// stays.
    static func quitIfAnotherCopyRuns() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = NSRunningApplication.current
        var copies = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }
        // Count this copy even before macOS lists it, so two new copies
        // cannot both decide that the other one is older.
        if !copies.contains(where: { $0.processIdentifier == current.processIdentifier }) {
            copies.append(current)
        }
        guard let keeper = copies.min(by: isOlder), keeper.processIdentifier != current.processIdentifier else {
            return
        }
        logger.notice("Another copy runs (pid \(keeper.processIdentifier)). Quitting pid \(current.processIdentifier).")
        keeper.activate()
        exit(0)
    }

    /// Orders copies by launch time, then by process ID.
    private static func isOlder(_ a: NSRunningApplication, _ b: NSRunningApplication) -> Bool {
        let aDate = a.launchDate ?? .distantPast
        let bDate = b.launchDate ?? .distantPast
        if aDate != bDate { return aDate < bDate }
        return a.processIdentifier < b.processIdentifier
    }
}
