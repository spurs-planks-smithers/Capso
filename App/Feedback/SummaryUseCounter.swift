// App/Feedback/SummaryUseCounter.swift
import Foundation

/// Fork: a local-only count of how often the on-device summary name is used
/// (#200, Drew, 2026-11-01). Nextshot cannot learn a user's macOS version or
/// Apple Intelligence setting from its download stats, so this tells Drew how
/// many copies got a summary on his own Macs. It is whole numbers in the app's
/// settings domain. It holds no text from the user, it is never uploaded, and
/// no support archive includes it.
///
/// Keys, under the prefix `summaryUse.`:
/// - `copy.summary`: a prompt copy that used a stored summary.
/// - `copy.cutName`: the model could run, but no summary was stored yet (the
///   first copy of a round, a NONE answer, or a request still running).
/// - `copy.unavailable.<state>`: the model could not run. The state is a
///   `FeedbackSummaryModel.stateName` word, such as `deviceNotEligible`.
/// - `request.named`, `request.noName`, `request.failed`: results of requests.
/// - `since`: the date of the first count.
///
/// Read them with `scripts/nextshot-summary-use.sh`.
enum SummaryUseCounter {
    static let prefix = "summaryUse."

    static func count(_ event: String, defaults: UserDefaults = .standard) {
        let key = prefix + event
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        if defaults.object(forKey: prefix + "since") == nil {
            defaults.set(Date(), forKey: prefix + "since")
        }
    }
}
