// Packages/JevKit/Sources/JevKit/Jobs/DataGuardLocalCovers.swift
import CoreGraphics
import FeedbackKit
import Foundation

/// The guard's local half, shared with the crops job (#81). The crops job
/// draws the same covers on its item crops, so a crop holds no private data
/// that the covered copy hides. Everything here runs on the Mac: the text
/// rules and Vision. None of it sends a request.
extension DataGuardJob {
    /// The covers for `hits`, `leftovers`, and the cut lines, for the kinds in
    /// on. `found` says a kind in on found data. `unplaced` says a kind in on
    /// found data it has no box for, so the covers are incomplete.
    static func covers(
        hits: [DataGuardKind: [LocalHit]],
        leftovers: [DataGuardKind: Leftover],
        sources: [Source],
        blockCut: Bool,
        modes: [DataGuardKind: FlagState]
    ) -> (covers: [FeedbackBox], found: Bool, unplaced: Bool) {
        var covers: [FeedbackBox] = []
        var found = false
        var unplaced = false
        for kind in DataGuardKind.allCases where modes[kind] == .on {
            for hit in hits[kind] ?? [] {
                found = true
                guard let box = hit.box else {
                    unplaced = true
                    continue
                }
                let grown = kind == .faces
                    ? DataGuardCovers.grown(box, share: DataGuardRule.faceShare, minimum: DataGuardRule.textPad)
                    : DataGuardCovers.padded(box, by: DataGuardRule.textPad)
                if !covers.contains(grown) { covers.append(grown) }
            }
            if let leftover = leftovers[kind], leftover.cover, let box = leftover.box {
                found = true
                let grown = DataGuardCovers.grown(box, share: DataGuardRule.jevShare, minimum: DataGuardRule.jevMinimum)
                if !covers.contains(grown) { covers.append(grown) }
            }
        }
        // Text nobody checked may hold private data. With a text kind in on,
        // a cut line is covered whole, and a cut block counts as unplaced.
        if DataGuardKind.textKinds.contains(where: { modes[$0] == .on }) {
            for box in sources.filter(\.cut).compactMap(\.box) {
                let padded = DataGuardCovers.padded(box, by: DataGuardRule.textPad)
                if !covers.contains(padded) { covers.append(padded) }
            }
            if blockCut { unplaced = true }
        }
        return (covers, found, unplaced)
    }

    /// The private data that the local text rules find. The app name is left
    /// out: only the strong injection rules read it.
    static func localHits(sources: [Source], kinds: Set<DataGuardKind>) -> [DataGuardKind: [LocalHit]] {
        var hits: [DataGuardKind: [LocalHit]] = [:]
        for source in sources where source.place != .app {
            for hit in DataGuardPatterns.dataHits(in: source.text, kinds: kinds) {
                hits[hit.rule.kind, default: []].append(LocalHit(rule: hit.rule, box: source.box))
            }
        }
        return hits
    }

    /// The faces in `image`, as hits. Nil when the finder throws, so the
    /// caller reports the covers as incomplete rather than as complete.
    static func faceHits(in image: CGImage, faceFinder: DataGuardFaceFinder) -> [LocalHit]? {
        guard let faces = try? faceFinder.faces(in: image) else { return nil }
        return faces
            .filter { $0.confidence >= DataGuardRule.faceConfidenceMinimum }
            .map { LocalHit(rule: .face, box: $0.box) }
    }
}
