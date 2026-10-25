// App/Feedback/DiskImageInstaller.swift
import AppKit
import DiskArbitration
import os

/// Fork: installs Nextshot from its disk image, and ejects old installer images.
///
/// Finder refuses to replace a running app, so a drag cannot update a copy
/// that runs. A double-click on Nextshot inside the disk image starts the new
/// copy instead. That copy asks the running copy to quit, puts itself where
/// the old copy was, opens the installed copy, and exits. The installed copy
/// then ejects every Nextshot installer image that is still mounted
/// (Drew, 2026-10-25, items 1.2 and 1.4).
///
/// The installer copy opens the installed copy through Launch Services,
/// never through a child process (local-only rule, `NetworkSourceScanTests`).
@MainActor
enum DiskImageInstaller {
    nonisolated static let appName = "Nextshot.app"
    nonisolated private static let logger = Logger(subsystem: "com.drewschulz.nextshot", category: "Launch")

    // MARK: - Facts about a copy

    /// The version date and build number (CFBundleVersion, the commit count).
    nonisolated static func build(of bundleURL: URL?) -> LaunchPlan.Build {
        guard let bundleURL, let info = Bundle(url: bundleURL)?.infoDictionary else { return .unknown }
        return LaunchPlan.Build(
            version: info["CFBundleShortVersionString"] as? String ?? "",
            number: Int(info["CFBundleVersion"] as? String ?? "") ?? 0
        )
    }

    /// "2026.10.24 (524)", the same text as the top row of the Nshot menu.
    nonisolated static func versionText(of bundleURL: URL) -> String {
        let info = Bundle(url: bundleURL)?.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// True on a disk image, and on the read-only place where App
    /// Translocation runs a downloaded app before the user moves it.
    nonisolated static func isOnReadOnlyVolume(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
    }

    /// Where an install goes: the place of the copy that runs now, else an
    /// existing copy in /Applications or ~/Applications, else /Applications.
    static func destination(runningCopies: [NSRunningApplication]) -> URL {
        if let running = runningCopies.compactMap(\.bundleURL).first(where: { !isOnReadOnlyVolume($0) }) {
            return running
        }
        let candidates = [
            URL(fileURLWithPath: "/Applications", isDirectory: true).appendingPathComponent(appName),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent(appName),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    // MARK: - Install

    /// Asks the user, then installs this copy at `destination` and exits.
    /// Returns only when the user says Not Now or the install fails.
    static func offerInstall(destination: URL, runningCopies: [NSRunningApplication]) {
        let folderName = FileManager.default.displayName(atPath: destination.deletingLastPathComponent().path)
        let alert = NSAlert()
        alert.messageText = "Install Nextshot \(versionText(of: Bundle.main.bundleURL))?"
        if let running = runningCopies.first, let url = running.bundleURL {
            alert.informativeText = "Nextshot \(versionText(of: url)) is open. Nextshot quits it, replaces it in \(folderName), and opens the new version."
        } else if FileManager.default.fileExists(atPath: destination.path) {
            alert.informativeText = "This replaces Nextshot \(versionText(of: destination)) in \(folderName) and opens the new version."
        } else {
            alert.informativeText = "This copies Nextshot to \(folderName) and opens it there."
        }
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            logger.notice("Install declined.")
            return
        }

        for app in runningCopies {
            app.terminate()
        }
        if !SingleInstanceGuard.waitUntilGone(runningCopies.map(\.processIdentifier), timeout: 10) {
            showFailure(
                "Nextshot did not quit.",
                "Quit Nextshot from the Nshot menu, then open this copy again."
            )
            return
        }

        do {
            try copyThisApp(to: destination)
        } catch {
            logger.error("Install failed: \(error.localizedDescription, privacy: .public)")
            showFailure(
                "Nextshot could not install the new version.",
                "\(error.localizedDescription) Drag Nextshot to Applications instead."
            )
            return
        }
        logger.notice("Installed build \(build(of: Bundle.main.bundleURL).description, privacy: .public) at \(destination.path, privacy: .public).")
        openAndExit(destination)
    }

    /// Copies the running bundle next to `destination`, then swaps it in, so
    /// a failed copy never leaves a half app at `destination`.
    nonisolated private static func copyThisApp(to destination: URL) throws {
        let files = FileManager.default
        let folder = destination.deletingLastPathComponent()
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = folder.appendingPathComponent(".Nextshot-install-\(UUID().uuidString).app")
        do {
            try files.copyItem(at: Bundle.main.bundleURL, to: staged)
            if files.fileExists(atPath: destination.path) {
                _ = try files.replaceItemAt(destination, withItemAt: staged)
            } else {
                try files.moveItem(at: staged, to: destination)
            }
        } catch {
            try? files.removeItem(at: staged)
            throw error
        }
    }

    /// Opens the copy at `url` as a new instance and exits this one. The new
    /// copy gets this process ID, and waits for it to exit before it starts.
    static func openAndExit(_ url: URL) -> Never {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [SingleInstanceGuard.installedByArgument, String(getpid())]
        let opened = DispatchSemaphore(value: 0)
        // The handler runs on a background queue, so the wait below cannot block it.
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                logger.error("Could not open \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            opened.signal()
        }
        _ = opened.wait(timeout: .now() + 5)
        exit(0)
    }

    private static func showFailure(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Eject

    /// Ejects each mounted disk image that holds a Nextshot.app with this
    /// bundle ID, except the volume that `ownBundle` runs from. Finder lists
    /// every mounted image under Locations, so old installers piled up there.
    /// Runs off the main thread: an eject can take a second.
    nonisolated static func ejectLeftoverImages(skipping ownBundle: URL) {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let session = DASessionCreate(kCFAllocatorDefault) else { return }
        let ownVolume = (try? ownBundle.resourceValues(forKeys: [.volumeURLKey]).volume)?.standardizedFileURL
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        for volume in volumes where volume.standardizedFileURL != ownVolume {
            let app = volume.appendingPathComponent(appName)
            guard Bundle(url: app)?.bundleIdentifier == bundleID, isDiskImage(volume, session: session) else { continue }
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
                logger.notice("Ejected the installer image \(volume.lastPathComponent, privacy: .public).")
            } catch {
                logger.notice("Could not eject \(volume.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A USB stick with a copy of Nextshot is not an installer, so only disk
    /// images count.
    nonisolated private static func isDiskImage(_ volume: URL, session: DASession) -> Bool {
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any],
              let model = description[kDADiskDescriptionDeviceModelKey as String] as? String else { return false }
        return model.trimmingCharacters(in: .whitespaces) == "Disk Image"
    }
}
