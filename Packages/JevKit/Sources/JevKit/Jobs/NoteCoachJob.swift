// Packages/JevKit/Sources/JevKit/Jobs/NoteCoachJob.swift
import FeedbackKit
import Foundation

/// Note coach (idea 1, issue #37, flag `noteCoach`): judges whether each
/// note names a change.
///
/// Stub from the Jev base: it sends nothing and returns no lines. The #37
/// session fills in this file and adds its own test file.
public struct NoteCoachJob: JevJob {
    public let id = "noteCoach"
    public let flag = FeatureFlag.noteCoach
    public let requires: JevDataKinds = []
    public let version = 0

    public init() {}

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        .empty
    }
}
