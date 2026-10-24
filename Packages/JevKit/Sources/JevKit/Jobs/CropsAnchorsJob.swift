// Packages/JevKit/Sources/JevKit/Jobs/CropsAnchorsJob.swift
import FeedbackKit
import Foundation

/// Crops and anchor text (ideas 7 and 8, issue #38, flag `cropsAnchors`):
/// one edge-checked crop and one "Search:" line per item.
///
/// Stub from the Jev base: it sends nothing and returns no lines. The #38
/// session fills in this file and adds its own test file.
public struct CropsAnchorsJob: JevJob {
    public let id = "cropsAnchors"
    public let flag = FeatureFlag.cropsAnchors
    public let requires: JevDataKinds = []
    public let version = 0

    public init() {}

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        .empty
    }
}
