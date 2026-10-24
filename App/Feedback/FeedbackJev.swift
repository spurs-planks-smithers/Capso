// App/Feedback/FeedbackJev.swift
import FeedbackKit
import Foundation
import JevKit
import os

/// Fork: Jev results in the macOS system log. Public fields only: job ids,
/// capture numbers, statuses, times, and token counts.
/// Read with: /usr/bin/log show --last 10m --predicate 'subsystem == "com.drewschulz.nextshot" AND category == "Jev"'
enum JevLog {
    static let logger = Logger(subsystem: "com.drewschulz.nextshot", category: "Jev")
}

/// Fork: connects JevKit's runner to the feedback controller. Every call
/// returns at once, except `settle` at round end, which waits at most 500 ms.
/// With `jevBase` off, the runner stores nothing, reads no key, and sends
/// nothing. Only JevKit makes the request, and only to api.typesafe.ai.
@MainActor
final class FeedbackJev {
    /// The longest a round-end copy waits for a running capture (Jev design).
    static let roundEndWait: Duration = .milliseconds(500)

    private let runner: JevRunner

    init(rootURL: URL) {
        runner = JevRunner(
            rootURL: rootURL,
            client: JevClient(transport: URLSessionTransport(), keyProvider: KeychainKeyProvider()),
            flags: { Flags.state($0) },
            log: { JevLog.logger.notice("\($0, privacy: .public)") }
        )
    }

    /// True when a copied prompt should point to the refined files: `jevBase`
    /// is on and at least one feature is on. Shadow changes no prompt.
    var pointsToRefinedFiles: Bool {
        JevGate.pointsToRefinedFiles { Flags.state($0) }
    }

    /// Reads the key at launch when Jev may run, so the one macOS access
    /// dialog shows at launch and not during a capture.
    func warmUp() {
        Task { await runner.warmUp() }
    }

    /// A capture was stored. Round end waits for it.
    func captureStored(folderName: String, capture: Int) {
        Task { await runner.expect(folderName: folderName, capture: capture) }
    }

    /// The capture's notes are final and its screen text is stored.
    /// `screenLines` are the OCR lines with boxes, which feedback.json does
    /// not keep.
    func captureReady(folderName: String, capture: Int, screenLines: [FeedbackTextLine]?) {
        Task { await runner.start(folderName: folderName, capture: capture, screenLines: screenLines) }
    }

    /// Round end, before the round prompt is copied. Returns at once when no
    /// feature is on.
    func settle(folderName: String) async {
        guard pointsToRefinedFiles else { return }
        await runner.settle(folderName: folderName, timeout: Self.roundEndWait)
    }
}
