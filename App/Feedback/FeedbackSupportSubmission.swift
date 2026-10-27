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
    private let isEnabled: @MainActor () -> Bool
    private let makePanel: @MainActor () -> any FeedbackSupportPresenting
    private let prepare: @MainActor (FeedbackRound, URL, SupportApp, String, String) async throws -> SupportPackage
    private let send: @MainActor (SupportPackage) async throws -> SupportReceipt
    private var panel: (any FeedbackSupportPresenting)?
    private var work: Task<Void, Never>?
    private var package: SupportPackage?
    private var panelID: UUID?
    private var operationID: UUID?

    init(
        rootURL: URL,
        waitForSaves: @escaping @MainActor () async -> Void,
        captureIsOpen: @escaping @MainActor () -> Bool,
        showToast: @escaping @MainActor (String) -> Void,
        isEnabled: @escaping @MainActor () -> Bool = { Flags.isOn(.supportSubmission) },
        makePanel: @escaping @MainActor () -> any FeedbackSupportPresenting = { FeedbackSupportPanel() },
        prepare: @escaping @MainActor (FeedbackRound, URL, SupportApp, String, String) async throws -> SupportPackage = FeedbackSupportSubmission.preparePackage,
        send: @escaping @MainActor (SupportPackage) async throws -> SupportReceipt = { try await SupportTransport().submit($0) }
    ) {
        self.rootURL = rootURL
        self.waitForSaves = waitForSaves
        self.captureIsOpen = captureIsOpen
        self.showToast = showToast
        self.isEnabled = isEnabled
        self.makePanel = makePanel
        self.prepare = prepare
        self.send = send
    }

    func show(round: FeedbackRound) {
        guard isEnabled() else { return }
        guard !captureIsOpen() else {
            showToast("Finish the open capture before submitting feedback.")
            NSSound.beep()
            return
        }
        if let panel { panel.bringForward(); return }
        let panel = makePanel()
        let panelID = UUID()
        self.panel = panel
        self.panelID = panelID
        panel.onSubmit = { [weak self] note, email in
            self?.submit(panelID: panelID, folderName: round.folderName, note: note, email: email)
        }
        panel.onClosed = { [weak self] in
            guard let self, self.panelID == panelID else { return }
            // Revoke ownership before cancellation can resume an old task.
            self.panelID = nil
            self.operationID = nil
            self.work?.cancel()
            self.work = nil
            self.package?.remove()
            self.package = nil
            self.panel = nil
        }
        panel.show(captureCount: round.captures.count)
    }

    private func submit(panelID: UUID, folderName: String, note: String, email: String) {
        guard self.panelID == panelID, work == nil, let panel else { return }
        guard isEnabled() else { panel.fail("Feedback submission is disabled.", prepared: false); return }
        panel.setSending("Checking the saved captures for sensitive information...")
        let operationID = UUID()
        self.operationID = operationID
        work = Task { @MainActor [weak self, weak panel] in
            guard let self, let panel, self.owns(panelID: panelID, operationID: operationID) else { return }
            // Cleanup belongs to this task's package, never a later task's package.
            var operationPackage = self.package
            defer {
                if self.owns(panelID: panelID, operationID: operationID) {
                    self.work = nil
                    self.operationID = nil
                }
            }
            do {
                if operationPackage == nil {
                    try SupportInput.validate(note: note, contactEmail: email)
                    guard !self.captureIsOpen() else { throw SupportError.captureOpen }
                    await self.waitForSaves()
                    try self.requireOwnership(panelID: panelID, operationID: operationID)
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
                    let prepared = try await self.prepare(snapshot, folder, app, note, email)
                    operationPackage = prepared
                    try self.requireOwnership(panelID: panelID, operationID: operationID)
                    self.package = prepared
                }
                guard let package = operationPackage else { throw SupportError.noCaptures }
                try self.requireOwnership(panelID: panelID, operationID: operationID)
                panel.setSending("Submitting the saved package...")
                let receipt = try await self.send(package)
                try self.requireOwnership(panelID: panelID, operationID: operationID)
                package.remove()
                self.package = nil
                panel.received(receipt.id)
            } catch is CancellationError {
                operationPackage?.remove()
                if self.owns(panelID: panelID, operationID: operationID) { self.package = nil }
            } catch {
                guard self.owns(panelID: panelID, operationID: operationID) else {
                    operationPackage?.remove()
                    return
                }
                // Error text comes from the local error enum, never the response body.
                let message = (error as? SupportError)?.errorDescription ?? "Submission could not finish. Retry sends the same saved package."
                panel.fail(message, prepared: operationPackage != nil)
            }
        }
    }

    private func owns(panelID: UUID, operationID: UUID) -> Bool {
        self.panelID == panelID && self.operationID == operationID
    }

    private func requireOwnership(panelID: UUID, operationID: UUID) throws {
        guard !Task.isCancelled, owns(panelID: panelID, operationID: operationID) else { throw CancellationError() }
    }

    private static func preparePackage(_ snapshot: FeedbackRound, folder: URL, app: SupportApp, note: String, email: String) async throws -> SupportPackage {
        let preparation = Task.detached(priority: .userInitiated) {
            try SupportArchiveWriter.prepare(round: snapshot, folder: folder, app: app, note: note, contactEmail: email)
        }
        return try await withTaskCancellationHandler {
            try await preparation.value
        } onCancel: { preparation.cancel() }
    }

}
