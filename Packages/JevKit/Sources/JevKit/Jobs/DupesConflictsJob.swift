// Packages/JevKit/Sources/JevKit/Jobs/DupesConflictsJob.swift
import FeedbackKit
import Foundation

/// Duplicates and conflicts (ideas 9 and 10, issue #39, flag
/// `dupesConflicts`): compares this capture's items with the earlier items
/// of the round.
///
/// Stub from the Jev base: it sends nothing and returns no lines. The #39
/// session fills in this file and adds its own test file.
public struct DupesConflictsJob: JevJob {
    public let id = "dupesConflicts"
    public let flag = FeatureFlag.dupesConflicts
    public let requires: JevDataKinds = []
    public let version = 0

    public init() {}

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        .empty
    }
}
