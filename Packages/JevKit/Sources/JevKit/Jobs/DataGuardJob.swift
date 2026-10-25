// Packages/JevKit/Sources/JevKit/Jobs/DataGuardJob.swift
import FeedbackKit
import Foundation

/// Injection and data guard (idea 15, issue #70, flag `dataGuard`): flags
/// screen text that holds instructions aimed at an AI agent, and finds
/// private data to blur in the agent's copy of a capture.
///
/// Stub from the orchestration session: it sends nothing and returns no
/// lines. The #70 session fills in this file and adds its own test file.
public struct DataGuardJob: JevJob {
    public let id = "dataGuard"
    public let flag = FeatureFlag.dataGuard
    public let requires: JevDataKinds = []
    public let version = 0

    public init() {}

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        .empty
    }
}
