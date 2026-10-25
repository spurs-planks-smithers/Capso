// Packages/JevKit/Sources/JevKit/Jobs/PromptLanesPlan.swift
import FeedbackKit
import Foundation

/// Lanes and priority (issue #72, flag `promptLanes`): builds the round plan
/// at round end, in code, from the round and `jev.json`. The lanes job rates
/// one capture at a time and never sees another capture's answers, so only
/// this step can order the whole round. See
/// docs/superpowers/specs/2026-10-24-prompt-lanes-design.md.
///
/// The plan sends nothing and reads no network. It reads `jev.json` only.
/// The result holds item ids and level names, never the reviewer's words.
public enum PromptLanesPlan {
    /// The plan for a copied round prompt, or nil when the prompt stays plain.
    /// Needs `jevBase` and `promptLanes` both on: shadow never changes a
    /// prompt. Nil also when `jev.json` is missing or no item is rated.
    public static func forPrompt(round: FeedbackRound, file: JevRecordFile?, flags: (FeatureFlag) -> FlagState) -> PromptLanes? {
        guard flags(.jevBase) == .on, flags(.promptLanes) == .on, let file else { return nil }
        return plan(round: round, file: file)
    }

    /// Every item of the round appears once: in lane A, in lane B, or in Ask
    /// first.
    ///
    /// - An item with an empty note goes to Ask first. The round decides
    ///   that, not `jev.json`, so it holds even when the capture's job failed.
    /// - A capture's labels count only from a `done` record of this job at
    ///   its current version. Shadow and on records both count.
    /// - A filled item with no usable label goes to lane B as not rated.
    /// - Each lane runs by severity, highest first. Inside one severity it
    ///   runs by capture, then badge. Not rated items come last in lane B.
    ///   Size does not change the order. It only gates lane A, in the job.
    ///
    /// Nil when no item is rated.
    public static func plan(round: FeedbackRound, file: JevRecordFile) -> PromptLanes? {
        var laneA: [Placed] = []
        var laneB: [Placed] = []
        var notRated: [Placed] = []
        var askFirst: [String] = []

        for capture in round.captures.sorted(by: { $0.index < $1.index }) {
            let captureLabels = labels(for: capture.index, in: file)
            // Same item set as the job: the plan and the job always agree.
            for item in PromptLanesJob.items(in: capture) {
                let id = "\(capture.index).\(item.badge)"
                if item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    askFirst.append(id)
                } else if let rating = rating(of: id, in: captureLabels) {
                    let placed = Placed(entry: PromptLanes.Entry(item: id, severity: rating.severity, size: rating.size), capture: capture.index, badge: item.badge)
                    if rating.laneA {
                        laneA.append(placed)
                    } else {
                        laneB.append(placed)
                    }
                } else {
                    notRated.append(Placed(entry: PromptLanes.Entry(item: id), capture: capture.index, badge: item.badge))
                }
            }
        }

        guard !laneA.isEmpty || !laneB.isEmpty else { return nil }
        return PromptLanes(
            laneA: laneA.sorted(by: before).map(\.entry),
            laneB: laneB.sorted(by: before).map(\.entry) + notRated.sorted(by: before).map(\.entry),
            askFirst: askFirst
        )
    }

    /// The bundle's `jev.json`. Nil when the file is missing, unreadable, or
    /// from another schema version.
    public static func loadRecords(folderURL: URL) -> JevRecordFile? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: folderURL.appendingPathComponent(JevRecordFile.fileName)),
              let file = try? decoder.decode(JevRecordFile.self, from: data),
              file.schemaVersion == JevRecordFile.currentSchemaVersion
        else { return nil }
        return file
    }

    // MARK: - Reading the labels

    private struct Placed {
        var entry: PromptLanes.Entry
        var capture: Int
        var badge: Int
    }

    /// Severity first, highest first. Then capture, then badge. A not rated
    /// entry has no severity, and the caller keeps those in their own list.
    private static func before(_ lhs: Placed, _ rhs: Placed) -> Bool {
        let left = lhs.entry.severity?.rawValue ?? 0
        let right = rhs.entry.severity?.rawValue ?? 0
        if left != right { return left > right }
        if lhs.capture != rhs.capture { return lhs.capture < rhs.capture }
        return lhs.badge < rhs.badge
    }

    /// The summary fields of this job's usable record for one capture. Nil
    /// when the capture has no record, the job failed or was skipped, the
    /// record is from another job version, or it has no summary.
    private static func labels(for captureIndex: Int, in file: JevRecordFile) -> [JevSummaryField]? {
        let job = PromptLanesJob()
        let record = file.captures.first { $0.capture == captureIndex }?.jobs.first {
            $0.job == job.id && $0.jobVersion == job.version && $0.status == .done
        }
        guard case .object(let fields)? = record?.summary else { return nil }
        return fields
    }

    /// A rated item has lane `A` or `B` and a level in range for severity and
    /// size. Anything else gives nil, which means not rated.
    private static func rating(of id: String, in labels: [JevSummaryField]?) -> (laneA: Bool, severity: PromptLanes.Severity, size: PromptLanes.Size)? {
        guard let labels,
              case .object(let fields)? = field(id, in: labels),
              case .code(let lane)? = field("lane", in: fields),
              lane.text == "A" || lane.text == "B",
              let severityLevel = level(field("severity", in: fields)),
              let sizeLevel = level(field("size", in: fields)),
              let severity = PromptLanes.Severity(rawValue: severityLevel),
              let size = PromptLanes.Size(rawValue: sizeLevel)
        else { return nil }
        return (laneA: lane.text == "A", severity: severity, size: size)
    }

    private static func field(_ name: String, in fields: [JevSummaryField]) -> JevSummaryValue? {
        fields.first { $0.key.text == name }?.value
    }

    /// A whole number from 0 to 9, or nil. The scales check their own range.
    /// The summary decoder tries Bool before Double, so a stored 0 or 1
    /// could decode as a boolean. It does not: the disk round-trip test
    /// stores levels 0 and 1 and fails if that ever changes.
    private static func level(_ value: JevSummaryValue?) -> Int? {
        guard case .number(let number)? = value,
              number.isFinite, number == number.rounded(), (0...9).contains(number)
        else { return nil }
        return Int(number)
    }
}
