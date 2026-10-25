// Packages/JevKit/Sources/JevKit/Jobs/PromptLanesJob.swift
import FeedbackKit
import Foundation

/// Lanes and priority (ideas 11 and 12, issue #69, flag `promptLanes`):
/// rates each item's severity and size, and sorts mechanical edits from
/// judgment calls, so the round prompt can order and split its items.
///
/// Stub from the orchestration session: it sends nothing and returns no
/// lines. The #69 session fills in this file and adds its own test file.
public struct PromptLanesJob: JevJob {
    public let id = "promptLanes"
    public let flag = FeatureFlag.promptLanes
    public let requires: JevDataKinds = []
    public let version = 0

    public init() {}

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        .empty
    }
}
