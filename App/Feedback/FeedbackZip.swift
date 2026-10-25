// App/Feedback/FeedbackZip.swift
import AppKit
import FeedbackKit

/// Fork: Zip Round and Zip N Selected in the Nshot menu (#85). It waits for
/// saves in progress, writes the zip off the main actor, then puts the zip
/// file on the clipboard, shows a toast, and opens the Share menu.
/// Design: `docs/superpowers/specs/2026-10-25-zip-handoff-design.md`.
@MainActor
final class FeedbackZip {
    private let rootURL: URL
    private let waitForSaves: @MainActor () async -> Void
    private let showToast: @MainActor (String) -> Void
    private let showShare: @MainActor (URL) -> Void
    private let report: @MainActor (Error, String) -> Void
    /// True while a zip runs. One zip at a time, so a double click never
    /// makes a second `-2` zip.
    private var running = false

    init(
        rootURL: URL,
        waitForSaves: @escaping @MainActor () async -> Void,
        showToast: @escaping @MainActor (String) -> Void,
        showShare: @escaping @MainActor (URL) -> Void,
        report: @escaping @MainActor (Error, String) -> Void
    ) {
        self.rootURL = rootURL
        self.waitForSaves = waitForSaves
        self.showToast = showToast
        self.showShare = showShare
        self.report = report
    }

    /// Returns false, after a beep, when a zip already runs.
    @discardableResult
    func zipRound(folderName: String) -> Bool {
        start(kind: .round) { rootURL in
            guard let round = FeedbackLibrary.round(named: folderName, in: rootURL) else { return [] }
            let folderPath = rootURL.appendingPathComponent(folderName, isDirectory: true).path
            return round.captures.map { FeedbackSelectionEntry(round: round, capture: $0, folderPath: folderPath) }
        }
    }

    /// Returns false, after a beep, when a zip already runs.
    @discardableResult
    func zipSelected(_ basket: FeedbackBasket) -> Bool {
        start(kind: .selection) { rootURL in
            let resolved = FeedbackLibrary.entries(for: basket, in: rootURL)
            if !resolved.missing.isEmpty {
                FeedbackLog.logger.notice("zip: \(resolved.missing.count, privacy: .public) checked captures not found")
            }
            return resolved.entries
        }
    }

    private func start(kind: ZipKind, entries: @escaping @MainActor (URL) -> [FeedbackSelectionEntry]) -> Bool {
        guard !running else {
            NSSound.beep()
            return false
        }
        running = true
        let began = Date()
        Task { @MainActor [self] in
            defer { running = false }
            let making = Task { @MainActor [showToast] in
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled {
                    showToast(ZipMessages.making)
                }
            }
            defer { making.cancel() }

            // A save can include OCR, which can take 30 s. The zip reads the
            // round from disk after it, so the zip holds every stored capture.
            await waitForSaves()
            let list = entries(rootURL)
            guard !list.isEmpty else {
                FeedbackLog.logger.notice("zip: nothing to zip")
                NSSound.beep()
                return
            }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ZipWriter.write(kind: kind, entries: list, into: downloads, now: Date(), timeZone: .current)
                }.value
                making.cancel()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([result.url as NSURL])
                showToast(ZipMessages.ready(fileName: result.url.lastPathComponent, bytes: result.bytes, overBudget: result.overBudget))
                showShare(result.url)
                let seconds = Date().timeIntervalSince(began)
                // The zip name holds the date only, but the folder stays private like other names.
                FeedbackLog.logger.notice("zip written: \(kind.rawValue, privacy: .public), \(result.captureCount, privacy: .public) captures, \(result.missing.count, privacy: .public) missing, \(result.bytes, privacy: .public) bytes, step \(result.stepIndex, privacy: .public), over \(result.overBudget, privacy: .public), \(seconds, format: .fixed(precision: 1), privacy: .public) s, \(result.url.lastPathComponent, privacy: .private)")
            } catch ZipError.noCaptures {
                FeedbackLog.logger.notice("zip: no capture has both images")
                NSSound.beep()
            } catch {
                making.cancel()
                if Self.isNoAccess(error) {
                    showToast(ZipMessages.noDownloadsAccess)
                }
                report(error, "Zip not written")
            }
        }
        return true
    }

    /// True for a write that macOS refused, as when Downloads access is off.
    private static func isNoAccess(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteNoPermissionError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EPERM) || nsError.code == Int(EACCES) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isNoAccess(underlying)
        }
        return false
    }
}
