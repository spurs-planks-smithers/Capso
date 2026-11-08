// scripts/dmg-update-harness/Harness.swift
//
// A small menu-bar-less app for `scripts/test-dmg-drag-update.sh`. It runs
// the real install files (`LaunchPlan`, `SingleInstanceGuard`,
// `DiskImageInstaller`, `DiskImageWatcher`) under its own bundle ID, so the
// test never touches Nextshot or Nextshot Dev, their hotkeys, or their grants.
// `--no-watch` turns the mount watcher off, for the control case that shows
// the old Finder failure.
import AppKit

@main
@MainActor
final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private var watcher: DiskImageWatcher?

    static func main() {
        let app = NSApplication.shared
        let delegate = HarnessDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstanceGuard.quitIfAnotherCopyRuns()
        guard !CommandLine.arguments.contains("--no-watch") else { return }
        let watcher = DiskImageWatcher(isBusy: { false }, waitForSaves: {})
        self.watcher = watcher
        watcher.start()
    }
}
