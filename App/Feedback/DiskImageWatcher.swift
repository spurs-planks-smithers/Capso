// App/Feedback/DiskImageWatcher.swift
import AppKit
import os

/// Fork: hands the update to a newer Nextshot when its disk image mounts
/// (#88, Drew, 2026-11-07, items 1.1 and 2.1).
///
/// Finder cannot replace a running app. A drag to Applications over a
/// running Nextshot failed with "The operation can't be completed because
/// the item is in use". Updaters such as Sparkle solve this with a second
/// process that replaces the app after it quits. Nextshot starts no child
/// process (`NetworkSourceScanTests`), so the newer copy on the image is that
/// second process, opened through Launch Services.
///
/// When a disk image mounts with an app of this bundle ID, a newer build, and
/// this app's signer, this copy waits until no capture is open and no save
/// runs. Then it opens the copy on the image. That copy quits this one and
/// asks "Install Nextshot ...?". Install and a drag both work from there
/// (`DiskImageInstaller.offerInstallAfterHandOff`).
///
/// Only a copy with this code watches. A copy from before it (0.7.0 and
/// earlier) still needs the double-click on the image.
@MainActor
final class DiskImageWatcher {
    private static let logger = Logger(subsystem: ForkBranding.logSubsystem, category: "Launch")

    private let isBusy: () -> Bool
    private let waitForSaves: () async -> Void
    private var observer: NSObjectProtocol?
    private var waitingFor: URL?
    private var handingOff = false

    init(isBusy: @escaping () -> Bool, waitForSaves: @escaping () async -> Void) {
        self.isBusy = isBusy
        self.waitForSaves = waitForSaves
    }

    /// A copy that runs from a disk image is an installer, so it does not watch.
    func start() {
        guard observer == nil, !DiskImageInstaller.isOnReadOnlyVolume(Bundle.main.bundleURL) else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let volume = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { self?.mounted(volume) }
        }
    }

    private func mounted(_ volume: URL) {
        let own = DiskImageInstaller.ownBuild
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let app = DiskImageInstaller.newerCopy(onImage: volume, than: own) else { return }
            await self?.handOffWhenIdle(app)
        }
    }

    /// Quitting now would lose an open capture or a note being typed, so the
    /// hand-off waits for that work. It checks once a second while the image
    /// stays mounted.
    private func handOffWhenIdle(_ app: URL) {
        guard !handingOff else { return }
        guard FileManager.default.fileExists(atPath: app.path) else {
            if waitingFor == app {
                Self.logger.notice("The image ejected before the hand-off.")
                waitingFor = nil
            }
            return
        }
        if isBusy() {
            if waitingFor != app {
                Self.logger.notice("A newer copy mounted. The hand-off waits until no capture is open.")
            }
            waitingFor = app
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.handOffWhenIdle(app)
            }
            return
        }
        waitingFor = nil
        handingOff = true
        Task { [weak self] in
            await self?.waitForSaves()
            self?.openUnlessBusy(app)
        }
    }

    /// A capture can start while the saves finish, so the check runs again.
    private func openUnlessBusy(_ app: URL) {
        guard !isBusy() else {
            handingOff = false
            handOffWhenIdle(app)
            return
        }
        open(app)
    }

    private func open(_ app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [SingleInstanceGuard.handOffArgument, String(getpid())]
        Self.logger.notice("Handing the update to \(DiskImageInstaller.versionText(of: app), privacy: .public) at \(app.path, privacy: .public).")
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { [weak self] _, error in
            // The handler runs on a background queue.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.opened(error: error) }
            }
        }
    }

    /// The copy on the image quits this one. When it fails to open (the
    /// user said Cancel in the Gatekeeper prompt) or it does not quit this
    /// copy, a later mount can try again.
    private func opened(error: Error?) {
        if let error {
            Self.logger.notice("The copy on the image did not open: \(error.localizedDescription, privacy: .public)")
            handingOff = false
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            self?.handingOff = false
        }
    }
}
