// Packages/JevKit/Sources/JevKit/Runner/JevGate.swift
import FeedbackKit
import Foundation

/// Answers "may Jev run?" and "do prompts point to refined files?" from the
/// flags alone. `flags` must already apply the dev-only rule, as
/// `FlagResolver` does. It need not apply the sub-flag cap: the gate reads
/// each option through `FlagResolver.effectiveState`.
///
/// A job with options (its sub-flags, #94) has work only when at least one
/// option is on after the cap. Parent on with every sub-flag off, or in
/// shadow, writes no refined line. So it must not start the key read, the
/// stored capture work, or the round-end wait, and in shadow it must not
/// change a copied prompt.
public enum JevGate {
    /// True when `jevBase` is on and at least one job has work to run.
    public static func mayRun(jobs: [any JevJob] = JevJobRegistry.all, flags: (FeatureFlag) -> FlagState) -> Bool {
        flags(.jevBase) == .on && jobs.contains { runs($0, flags: flags) }
    }

    /// True when `jevBase` is on and at least one job is on and writes lines.
    /// Shadow never changes a prompt.
    public static func pointsToRefinedFiles(jobs: [any JevJob] = JevJobRegistry.all, flags: (FeatureFlag) -> FlagState) -> Bool {
        flags(.jevBase) == .on && jobs.contains { writes($0, flags: flags) }
    }

    /// True when the job's flag is shadow or on and, for a job with options,
    /// at least one option is shadow or on after the cap. A job with no
    /// options runs whenever its flag is not off. The runner plans only such
    /// jobs. This does not look at `jevBase`.
    public static func runs(_ job: any JevJob, flags: (FeatureFlag) -> FlagState) -> Bool {
        guard flags(job.flag) != .off else { return false }
        let options = optionStates(of: job, flags: flags)
        return options.isEmpty || options.contains { $0 != .off }
    }

    /// True when the job's flag is on and, for a job with options, at least
    /// one option is on after the cap. Only then can the job write a line.
    public static func writes(_ job: any JevJob, flags: (FeatureFlag) -> FlagState) -> Bool {
        guard flags(job.flag) == .on else { return false }
        let options = optionStates(of: job, flags: flags)
        return options.isEmpty || options.contains { $0 == .on }
    }

    /// The capped state of each option flag. The job's own flag is not an
    /// option, as the runner does not pass it either.
    private static func optionStates(of job: any JevJob, flags: (FeatureFlag) -> FlagState) -> [FlagState] {
        job.options
            .filter { $0 != job.flag }
            .map { FlagResolver.effectiveState(of: $0, state: flags) }
    }

    /// The data kinds with consent. Reviewer text is always allowed once
    /// `jevBase` is on.
    public static func allowedKinds(flags: (FeatureFlag) -> FlagState) -> JevDataKinds {
        var kinds: JevDataKinds = .reviewerText
        if flags(.jevSendScreenText) == .on { kinds.insert(.screenText) }
        if flags(.jevSendImages) == .on { kinds.insert(.images) }
        return kinds
    }
}
