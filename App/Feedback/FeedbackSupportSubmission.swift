import AppKit
import FeedbackKit
import SupportKit

/// Owns one explicit submission. A retry sends the same immutable package.
@MainActor
final class FeedbackSupportSubmission {
    private let rootURL: URL
    private let waitForSaves: @MainActor () async -> Void
    private let captureIsOpen: @MainActor () -> Bool
    private let showToast: @MainActor (String) -> Void
    private var panel: FeedbackSupportPanel?
    private var work: Task<Void, Never>?
    private var package: SupportPackage?

    init(rootURL: URL, waitForSaves: @escaping @MainActor () async -> Void, captureIsOpen: @escaping @MainActor () -> Bool, showToast: @escaping @MainActor (String) -> Void) {
        self.rootURL = rootURL
        self.waitForSaves = waitForSaves
        self.captureIsOpen = captureIsOpen
        self.showToast = showToast
    }

    func show(round: FeedbackRound) {
        guard Flags.isOn(.supportSubmission) else { return }
        guard !captureIsOpen() else {
            showToast("Finish the open capture before submitting feedback.")
            NSSound.beep()
            return
        }
        if let panel { panel.bringForward(); return }
        let panel = FeedbackSupportPanel()
        self.panel = panel
        panel.onSubmit = { [weak self] note, email in self?.submit(folderName: round.folderName, note: note, email: email) }
        panel.onClosed = { [weak self] in
            self?.work?.cancel()
            self?.work = nil
            self?.package?.remove()
            self?.package = nil
            self?.panel = nil
        }
        panel.show(captureCount: round.captures.count)
    }

    private func submit(folderName: String, note: String, email: String) {
        guard work == nil, let panel else { return }
        guard Flags.isOn(.supportSubmission) else { panel.fail("Feedback submission is disabled.", prepared: false); return }
        panel.setSending("Checking the saved captures for sensitive information...")
        work = Task { @MainActor [weak self, weak panel] in
            guard let self, let panel else { return }
            defer { self.work = nil }
            do {
                if self.package == nil {
                    try SupportInput.validate(note: note, contactEmail: email)
                    guard !self.captureIsOpen() else { throw SupportError.captureOpen }
                    await self.waitForSaves()
                    try Task.checkCancellation()
                    guard !self.captureIsOpen() else { throw SupportError.captureOpen }
                    guard let snapshot = FeedbackLibrary.round(named: folderName, in: self.rootURL) else { throw SupportError.noCaptures }
                    let folder = self.rootURL.appendingPathComponent(folderName, isDirectory: true)
                    let info = Bundle.main.infoDictionary
                    let app = SupportApp(
                        version: info?["CFBundleShortVersionString"] as? String ?? "unknown",
                        build: info?["CFBundleVersion"] as? String ?? "unknown",
                        channel: BuildChannelDetector.current.rawValue,
                        osVersion: ProcessInfo.processInfo.operatingSystemVersionString
                    )
                    let preparation = Task.detached(priority: .userInitiated) {
                        try SupportArchiveWriter.prepare(round: snapshot, folder: folder, app: app, note: note, contactEmail: email)
                    }
                    let prepared = try await withTaskCancellationHandler {
                        try await preparation.value
                    } onCancel: { preparation.cancel() }
                    if Task.isCancelled { prepared.remove(); throw CancellationError() }
                    self.package = prepared
                }
                guard let package = self.package else { throw SupportError.noCaptures }
                try Task.checkCancellation()
                panel.setSending("Submitting the saved package...")
                let receipt = try await SupportTransport().submit(package)
                try Task.checkCancellation()
                package.remove()
                self.package = nil
                panel.received(receipt.id)
            } catch is CancellationError {
                self.package?.remove()
                self.package = nil
            } catch {
                // Error text comes from the local error enum, never the response body.
                let message = (error as? SupportError)?.errorDescription ?? "Submission could not finish. Retry sends the same saved package."
                panel.fail(message, prepared: self.package != nil)
            }
        }
    }
}
