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
            guard let round = FeedbackLibrary.round(named: folderName, in: rootURL) else { return ([], []) }
            let folderPath = rootURL.appendingPathComponent(folderName, isDirectory: true).path
            return (round.captures.map { FeedbackSelectionEntry(round: round, capture: $0, folderPath: folderPath) }, [])
        }
    }

    /// Returns false, after a beep, when a zip already runs. A checked
    /// capture that is gone is named in the zip's README.
    @discardableResult
    func zipSelected(_ basket: FeedbackBasket) -> Bool {
        start(kind: .selection) { rootURL in
            let resolved = FeedbackLibrary.entries(for: basket, in: rootURL)
            return (resolved.entries, resolved.missing)
        }
    }

    private typealias Resolved = (entries: [FeedbackSelectionEntry], unresolved: [FeedbackBasketKey])

    private func start(kind: ZipKind, resolve: @escaping @MainActor (URL) -> Resolved) -> Bool {
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
            let resolved = resolve(rootURL)
            let list = resolved.entries
            let unresolved = resolved.unresolved
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let sessionTitle = Flags.isOn(.sessionTitle)
            do {
                // An empty list throws noCaptures, so it gets the same toast.
                let result = try await Task.detached(priority: .userInitiated) {
                    try ZipWriter.write(kind: kind, entries: list, unresolved: unresolved, into: downloads, now: Date(), timeZone: .current, sessionTitle: sessionTitle)
                }.value
                making.cancel()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([result.url as NSURL])
                showToast(ZipMessages.ready(fileName: result.url.lastPathComponent, bytes: result.bytes, overBudget: result.overBudget))
                showShare(result.url)
                let seconds = Date().timeIntervalSince(began)
                // The zip name holds the date only, but the folder stays private like other names.
                FeedbackLog.logger.notice("zip written: \(kind.rawValue, privacy: .public), \(result.captureCount, privacy: .public) captures, \(result.missing.count, privacy: .public) missing, \(result.bytes, privacy: .public) bytes, step \(result.stepIndex, privacy: .public), over \(result.overBudget, privacy: .public), \(seconds, format: .fixed(precision: 1), privacy: .public) s, \(result.url.lastPathComponent, privacy: .private)")
            } catch {
                // Every failure replaces "Making zip..." with a toast that
                // names the reason (spec, Errors).
                making.cancel()
                showToast(ZipMessages.failure(for: error))
                if case ZipError.noCaptures = error {
                    FeedbackLog.logger.notice("zip: no capture has both images, \(unresolved.count, privacy: .public) not found")
                    NSSound.beep()
                } else {
                    report(error, "Zip not written")
                }
            }
        }
        return true
    }
}
