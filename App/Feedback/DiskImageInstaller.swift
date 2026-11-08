// App/Feedback/DiskImageInstaller.swift
import AppKit
import DiskArbitration
import os
import Security

/// Fork: installs Nextshot from its disk image, and ejects old installer images.
///
/// Finder refuses to replace a running app, so a drag cannot update a copy
/// that runs. A double-click on Nextshot inside the disk image starts the new
/// copy instead. That copy asks the running copy to quit, puts itself where
/// the old copy was, opens the installed copy, and exits. The installed copy
/// then ejects every Nextshot installer image that is still mounted
/// (Drew, 2026-10-25, items 1.2 and 1.4).
///
/// Since 2026-11-07 a drag works too (#88, Drew, items 1.1 and 2.1). The
/// running copy opens the newer copy when its image mounts
/// (`DiskImageWatcher`). That copy quits the running copy before it asks, so
/// Finder can replace it, and it opens a copy that a drag put in place.
///
/// The installer copy opens the installed copy through Launch Services,
/// never through a child process (local-only rule, `NetworkSourceScanTests`).
@MainActor
enum DiskImageInstaller {
    nonisolated static let appName = "Nextshot.app"
    nonisolated private static let logger = Logger(subsystem: ForkBranding.logSubsystem, category: "Launch")

    // MARK: - Facts about a copy

    /// Reads Info.plist from disk on each call. `Bundle(url:)` keeps the
    /// first Info.plist it read for a path, so it cannot see a new copy
    /// that a Finder drag put at the same path.
    nonisolated static func info(of bundleURL: URL) -> [String: Any]? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// The version and build number (CFBundleVersion, the commit count).
    nonisolated static func build(of bundleURL: URL?) -> LaunchPlan.Build {
        guard let bundleURL, let info = info(of: bundleURL) else { return .unknown }
        return build(from: info)
    }

    /// The build of this process, from memory. The file on disk can already
    /// hold a newer copy.
    nonisolated static var ownBuild: LaunchPlan.Build {
        build(from: Bundle.main.infoDictionary ?? [:])
    }

    nonisolated private static func build(from info: [String: Any]) -> LaunchPlan.Build {
        LaunchPlan.Build(
            version: info["CFBundleShortVersionString"] as? String ?? "",
            number: Int(info["CFBundleVersion"] as? String ?? "") ?? 0
        )
    }

    /// The app at the top of `volume` with `bundleID`, whatever its file name.
    nonisolated static func app(onVolume volume: URL, bundleID: String) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: volume, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return items.first { $0.pathExtension == "app" && info(of: $0)?["CFBundleIdentifier"] as? String == bundleID }
    }

    /// The copy of this app on the disk image at `volume`, when it is a newer
    /// build with this app's signer. The running copy hands the update to it
    /// (`DiskImageWatcher`). Runs off the main thread: the signature check
    /// reads the whole app.
    nonisolated static func newerCopy(onImage volume: URL, than own: LaunchPlan.Build) -> URL? {
        // The disk image check reads no files, so it runs first. Listing an
        // external drive waits on a macOS privacy prompt (2026-11-07 test).
        guard let bundleID = Bundle.main.bundleIdentifier,
              let session = DASessionCreate(kCFAllocatorDefault),
              isDiskImage(volume, session: session),
              let app = app(onVolume: volume, bundleID: bundleID),
              build(of: app) > own,
              isSignedLikeThisApp(app) else { return nil }
        return app
    }

    /// True when `app` passes a strict signature check against this app's
    /// designated requirement: the same bundle ID and the same signer. So a
    /// disk image with a look-alike app cannot make Nextshot quit.
    nonisolated static func isSignedLikeThisApp(_ app: URL) -> Bool {
        var me: SecCode?
        var meStatic: SecStaticCode?
        var requirement: SecRequirement?
        var code: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
              SecCodeCopyDesignatedRequirement(meStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
    }

    /// The code hash of the app at `url` when its signature is valid, else
    /// nil. A copy that Finder is still writing fails the check.
    nonisolated static func codeHash(of url: URL) -> Data? {
        var code: SecStaticCode?
        var signing: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signing) == errSecSuccess
        else { return nil }
        return (signing as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
    }

    /// "0.7.0 (919)", the same text as the top row of the Nshot menu.
    nonisolated static func versionText(of bundleURL: URL) -> String {
        let info = info(of: bundleURL) ?? [:]
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
        let (alert, startupChoice) = installAlert(destination: destination, runningCopies: runningCopies)
        let folderName = folderName(of: destination)
        if let running = runningCopies.first, let url = running.bundleURL {
            alert.informativeText = "Nextshot \(versionText(of: url)) is open. Nextshot quits it, replaces it in \(folderName), and opens the new version."
        } else if FileManager.default.fileExists(atPath: destination.path) {
            alert.informativeText = "This replaces Nextshot \(versionText(of: destination)) in \(folderName) and opens the new version."
        } else {
            alert.informativeText = "This copies Nextshot to \(folderName) and opens it there."
        }
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            logger.notice("Install declined.")
            return
        }
        install(destination: destination, runningCopies: runningCopies, startupChoice: startupChoice.map { $0.state == .on })
    }

    /// The running copy opened this copy because its disk image mounted
    /// (`DiskImageWatcher`, #88). Finder cannot replace a running app, so
    /// this copy quits the running copy before it asks. While the dialog is
    /// open, a drag to Applications works too: this copy sees the finished
    /// copy, opens it, and exits. Not Now opens the old copy again. Returns
    /// when the running copy does not quit and the plain offer was declined
    /// or failed, or when the last open fails. The old copy has quit then,
    /// so this copy keeps running from the image and nobody is left with no
    /// Nextshot.
    static func offerInstallAfterHandOff(destination: URL, runningCopies: [NSRunningApplication]) {
        guard let oldCopy = runningCopies.first?.bundleURL else {
            offerInstall(destination: destination, runningCopies: runningCopies)
            return
        }
        let (alert, startupChoice) = installAlert(destination: destination, runningCopies: runningCopies)
        let oldVersion = versionText(of: oldCopy)
        runningCopies.forEach { $0.terminate() }
        guard SingleInstanceGuard.waitUntilGone(runningCopies.map(\.processIdentifier), timeout: 10) else {
            logger.notice("The running copy did not quit for the update. Asking the usual way.")
            offerInstall(destination: destination, runningCopies: runningCopies.filter { !$0.isTerminated })
            return
        }
        let folderName = folderName(of: destination)
        alert.informativeText = "Nextshot \(oldVersion) quit for the update. Install replaces it in \(folderName) and opens the new version. A drag to \(folderName) works too."

        let monitor = DragInstallMonitor(destination: destination)
        monitor.start()
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        monitor.stop()

        if monitor.finished {
            logger.notice("A drag installed build \(ownBuild.description, privacy: .public) at \(destination.path, privacy: .public).")
            markUserApproved(destination)
            let token = startupChoice.flatMap { LoginStartupController.stageInstallerChoice($0.state == .on) }
            openOrKeepRunning(destination, startupToken: token)
            return
        }
        if response == .alertFirstButtonReturn {
            install(destination: destination, runningCopies: [], startupChoice: startupChoice.map { $0.state == .on })
            // The install failed and said why. The staged swap left the old copy in place.
        } else {
            logger.notice("Install declined. Opening the old copy again.")
        }
        openOrKeepRunning(destination)
    }

    /// Opens the copy at `url` and exits. When Launch Services reports an
    /// error, this copy returns and keeps running from the image instead.
    private static func openOrKeepRunning(_ url: URL, startupToken: String? = nil) {
        guard openNewInstance(url, startupToken: startupToken) else {
            logger.error("Could not open \(url.path, privacy: .public). This copy keeps running from the disk image.")
            return
        }
        exit(0)
    }

    /// The "Install Nextshot ...?" dialog with its buttons, and the startup
    /// check box when this install may offer it.
    private static func installAlert(destination: URL, runningCopies: [NSRunningApplication]) -> (NSAlert, NSButton?) {
        let offersStartupChoice = LoginStartupController.canOfferInstallerChoice(destination: destination, runningCopies: runningCopies)
        let alert = NSAlert()
        alert.messageText = "Install Nextshot \(versionText(of: Bundle.main.bundleURL))?"
        let startupChoice: NSButton? = offersStartupChoice
            ? NSButton(checkboxWithTitle: "Launch Nextshot at Login", target: nil, action: nil) : nil
        startupChoice?.state = .on
        alert.accessoryView = startupChoice
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")
        return (alert, startupChoice)
    }

    private static func folderName(of destination: URL) -> String {
        FileManager.default.displayName(atPath: destination.deletingLastPathComponent().path)
    }

    /// The copy on the image is not newer. Before 2026-10-25 it exited with no
    /// word, so a double-click "to update" seemed to do nothing. Install
    /// Anyway goes back from a trial build to a release (Drew, 2026-10-25).
    /// Returns only when the user says OK or the install fails.
    static func offerReplaceNewer(destination: URL, runningCopies: [NSRunningApplication]) {
        let installed = runningCopies.first?.bundleURL ?? destination
        let alert = NSAlert()
        alert.messageText = "Nextshot is up to date."
        let state = runningCopies.isEmpty ? "installed" : "open"
        alert.informativeText = "Nextshot \(versionText(of: installed)) is \(state). This disk has \(versionText(of: Bundle.main.bundleURL)), which is not newer."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Install Anyway")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        logger.notice("Install Anyway over \(versionText(of: installed), privacy: .public).")
        install(destination: destination, runningCopies: runningCopies)
    }

    /// Quits the running copies, puts this copy at `destination`, opens it,
    /// and exits. Returns only when a step fails.
    private static func install(destination: URL, runningCopies: [NSRunningApplication], startupChoice: Bool? = nil) {
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
        let token = startupChoice.flatMap { LoginStartupController.stageInstallerChoice($0) }
        openAndExit(destination, startupToken: token)
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
            markUserApproved(staged)
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

    /// The copy keeps the download's quarantine flags, without the "user
    /// approved" bit, so Gatekeeper asked "Are you sure you want to open it?"
    /// a second time (live test, 2026-10-25). The user already said Open to
    /// this same notarized app on the image. This sets only that bit, as
    /// Finder does after Open, and keeps the download record.
    nonisolated private static func markUserApproved(_ bundle: URL) {
        let name = "com.apple.quarantine"
        let path = bundle.path
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(path, name, &buffer, size, 0, XATTR_NOFOLLOW) == size,
              let value = String(bytes: buffer, encoding: .utf8) else { return }
        var fields = value.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard let first = fields.first, let flags = UInt32(first, radix: 16) else { return }
        let userApproved: UInt32 = 0x40
        fields[0] = String(format: "%04x", flags | userApproved)
        let updated = Array(fields.joined(separator: ";").utf8)
        if setxattr(path, name, updated, updated.count, 0, XATTR_NOFOLLOW) != 0 {
            logger.notice("Could not mark the installed copy as approved: errno \(errno)")
        }
    }

    /// Opens the copy at `url` as a new instance and exits this one. The new
    /// copy gets this process ID, and waits for it to exit before it starts.
    static func openAndExit(_ url: URL, startupToken: String? = nil) -> Never {
        _ = openNewInstance(url, startupToken: startupToken)
        exit(0)
    }

    /// Opens the copy at `url` as a new instance and waits up to 5 seconds
    /// for Launch Services. False only when it reports an error.
    private static func openNewInstance(_ url: URL, startupToken: String?) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [SingleInstanceGuard.installedByArgument, String(getpid())]
        if let startupToken {
            configuration.arguments += [LoginStartupController.installerTokenArgument, startupToken]
        }
        final class Outcome: @unchecked Sendable { var failed = false }
        let outcome = Outcome()
        let opened = DispatchSemaphore(value: 0)
        // The handler runs on a background queue, so the wait below cannot block it.
        // The semaphore orders its write before the read below.
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                logger.error("Could not open \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                outcome.failed = true
            }
            opened.signal()
        }
        _ = opened.wait(timeout: .now() + 5)
        return !outcome.failed
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
            // Disk images only, checked before any file read: listing an
            // external drive waits on a macOS privacy prompt.
            guard isDiskImage(volume, session: session), app(onVolume: volume, bundleID: bundleID) != nil else { continue }
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

/// Fork: watches the install place while the hand-off dialog is open, for a
/// copy that a Finder drag put there (#88). The copy counts as done when it
/// has this copy's build and code hash in two checks in a row, half a second
/// apart. A copy that Finder is still writing fails the signature check.
@MainActor
final class DragInstallMonitor {
    private let destination: URL
    private let expectedBuild = DiskImageInstaller.ownBuild
    /// This copy's code hash. The first check computes it off the main
    /// thread: a strict signature check reads the whole app from the image.
    private var expectedHash: Data?
    private var timer: Timer?
    private var checking = false
    private var matches = 0
    /// Set by `stop()`. A check still in flight then changes nothing, so it
    /// cannot end a later dialog, such as an install failure message.
    private var stopped = false
    private(set) var finished = false

    init(destination: URL) {
        self.destination = destination
    }

    /// Checks twice a second. The timer runs in the common modes, so it
    /// fires while the dialog runs its modal loop.
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        stopped = true
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !checking, !finished, !stopped else { return }
        // The old copy has another build, so no signature check runs until a drag lands.
        guard DiskImageInstaller.build(of: destination) == expectedBuild else {
            matches = 0
            return
        }
        checking = true
        let destination = destination
        let known = expectedHash
        let ownCopy = Bundle.main.bundleURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let expected = known ?? DiskImageInstaller.codeHash(of: ownCopy)
            let found = DiskImageInstaller.codeHash(of: destination)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.checked(expected: expected, same: expected != nil && found == expected) }
            }
        }
    }

    private func checked(expected: Data?, same: Bool) {
        checking = false
        guard !stopped else { return }
        expectedHash = expected
        matches = same ? matches + 1 : 0
        guard matches >= 2, !finished else { return }
        finished = true
        stop()
        // Ends the dialog's modal loop. Apple documents this call for use from a timer.
        NSApp.abortModal()
    }
}
