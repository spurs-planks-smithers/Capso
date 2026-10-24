// Packages/JevKit/Sources/JevKit/Runner/JevGate.swift
import FeedbackKit
import Foundation

/// Answers "may Jev run?" and "do prompts point to refined files?" from the
/// flags alone. `flags` must already apply the dev-only rule, as
/// `FlagResolver` does.
public enum JevGate {
    /// True when `jevBase` is on and at least one job's flag is shadow or on.
    public static func mayRun(jobs: [any JevJob] = JevJobRegistry.all, flags: (FeatureFlag) -> FlagState) -> Bool {
        flags(.jevBase) == .on && jobs.contains { flags($0.flag) != .off }
    }

    /// True when `jevBase` is on and at least one job's flag is on. Shadow
    /// never changes a prompt.
    public static func pointsToRefinedFiles(jobs: [any JevJob] = JevJobRegistry.all, flags: (FeatureFlag) -> FlagState) -> Bool {
        flags(.jevBase) == .on && jobs.contains { flags($0.flag) == .on }
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
