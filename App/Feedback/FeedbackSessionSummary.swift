// App/Feedback/FeedbackSessionSummary.swift
import FeedbackKit
import Foundation

/// Fork: runs the on-device summary of the session name in the background
/// (#200, Drew, 2026-10-31) and keeps the names it writes.
///
/// A copy never waits for it. Every copy asks for the names that exist now
/// (`names(priming:)`). A missing name starts a request in the background, and
/// the prompt keeps the name that `RoundTitle` cuts. The next copy of the same
/// words has the summary. When a capture's notes become final, `prime` starts
/// the requests for the capture and for its round, so a round prompt copied a
/// few seconds later has its name. A selection is primed when a capture is
/// checked, for the same reason.
///
/// Nothing runs unless `sessionTitle` and `sessionSummary` are both on, and
/// the model is available (`FeedbackSummaryModel.isAvailable`). With either
/// flag off, no file is read, no model is asked, and prompts are as before.
/// The names live in `SummaryNames.fileName` in the rounds folder.
@MainActor
final class FeedbackSessionSummary {
    private let fileURL: URL
    private var loaded: SummaryNames?
    /// Requests in progress, by key, so one input never runs twice at once.
    private var running: [String: Task<Void, Never>] = [:]
    /// Keys that gave no name in this launch (a vague input, a refusal, an
    /// error). They are not asked again until a relaunch.
    private var declined: Set<String> = []

    init(rootURL: URL) {
        fileURL = rootURL.appendingPathComponent(SummaryNames.fileName)
    }

    /// Both flags are on. `sessionSummary` alone does nothing.
    static var isEnabled: Bool {
        Flags.isOn(.sessionTitle) && Flags.isOn(.sessionSummary)
    }

    /// Both flags are on and this Mac can run the model now. Callers that
    /// read a round from disk to start a request check this first.
    static var canRun: Bool {
        isEnabled && FeedbackSummaryModel.isAvailable
    }

    /// The names that exist now, read from the file once per launch.
    private var stored: SummaryNames {
        if let loaded { return loaded }
        let names = SummaryNames.load(from: fileURL)
        loaded = names
        return names
    }

    /// The names a prompt uses now. None while the feature is off.
    var current: SummaryNames {
        Self.isEnabled ? stored : .none
    }

    /// The names for a copy, and a request in the background for `captures`
    /// when their name is missing. Returns at once.
    func names(priming captures: [FeedbackCapture]) -> SummaryNames {
        prime(captures)
        return current
    }

    /// Starts the summary for `captures` unless it is stored, running, or
    /// already declined. The reviewer's words are the only input.
    func prime(_ captures: [FeedbackCapture]) {
        guard let input = SummaryNames.input(of: captures), Self.canRun else { return }
        let basis = SummaryNames.basis(ofInput: input)
        guard running[basis] == nil, !declined.contains(basis), !stored.contains(basis: basis) else { return }
        running[basis] = Task { [weak self] in
            let start = Date()
            let name: String?
            do {
                name = try await FeedbackSummaryModel.name(forInput: input)
            } catch {
                // The error type only: the text can echo the notes.
                FeedbackLog.logger.notice("session summary failed: \(String(describing: type(of: error)), privacy: .public)")
                name = nil
            }
            self?.finish(basis: basis, input: input, name: name, seconds: Date().timeIntervalSince(start))
        }
    }

    private func finish(basis: String, input: String, name: String?, seconds: Double) {
        running[basis] = nil
        guard let name else {
            declined.insert(basis)
            FeedbackLog.logger.notice("session summary: no name, \(seconds, format: .fixed(precision: 2), privacy: .public) s")
            return
        }
        var names = stored
        names.set(name, forInput: input)
        loaded = names
        do {
            try names.save(to: fileURL)
        } catch {
            let nsError = error as NSError
            FeedbackLog.logger.error("session summary file not saved: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
        }
        // The name is the reviewer's words in short form, so it stays private.
        FeedbackLog.logger.notice("session summary stored: \(name.count, privacy: .public) characters, \(seconds, format: .fixed(precision: 2), privacy: .public) s")
    }
}
