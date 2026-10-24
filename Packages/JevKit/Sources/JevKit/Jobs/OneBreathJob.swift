// Packages/JevKit/Sources/JevKit/Jobs/OneBreathJob.swift
import FeedbackKit
import Foundation

/// One-breath notes (idea 16, issue #40, flag `oneBreath`, shadow only):
/// records how a dictated answer that names several circles would split.
///
/// Stub from the Jev base: it sends nothing and returns no lines. The #40
/// session fills in this file and adds its own test file.
public struct OneBreathJob: JevJob {
    public let id = "oneBreath"
    public let flag = FeatureFlag.oneBreath
    public let requires: JevDataKinds = []
    public let version = 0

    public init() {}

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        .empty
    }
}
