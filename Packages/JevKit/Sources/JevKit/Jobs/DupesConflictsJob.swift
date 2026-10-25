// Packages/JevKit/Sources/JevKit/Jobs/DupesConflictsJob.swift
import FeedbackKit
import Foundation

/// Duplicates and conflicts (ideas 9 and 10, issue #39, flag
/// `dupesConflicts`): compares each entry of this capture with the earlier
/// entries of the round, and writes a line for each repeat, overlap, or
/// opposite ask.
///
/// Jev only labels pairs. Code applies the thresholds and writes every line
/// the agent sees, with ids and code words only. The design is
/// docs/superpowers/specs/2026-10-24-dupes-conflicts-design.md.
///
/// Each part has a sub-flag (#96): `dupesMerge` for the "Same ask" and "may
/// overlap" lines, and `dupesConflict` for the "Ask first" lines. The runner
/// caps each at the state of `dupesConflicts`. A part that is off asks no
/// question, and a part in shadow records its outcomes and writes no line.
/// With both off, the job sends no request. With `dupesMerge` on and
/// `dupesConflict` off, the job still asks `opposite`, so a pair that is a
/// conflict never gets a merge line.
public struct DupesConflictsJob: JevJob {
    public let id = "dupesConflicts"
    public let flag = FeatureFlag.dupesConflicts
    /// The live eval of 2026-10-24 (docs/evals/2026-10-24-dupes-conflicts-eval.md)
    /// showed that notes alone cannot tell two elements apart when the words
    /// match: duplicate precision 0.53. With screen text it was 1.00. So the
    /// job needs screen text, and the runner skips it without that consent.
    public let requires: JevDataKinds = [.screenText]
    /// Version 2 needs screen text. Version 3 adds the sub-flags. Raise it
    /// when the questions change.
    public let version = 3

    public var options: [FeatureFlag] { [.dupesMerge, .dupesConflict] }

    public init() {}

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        let merge = context.optionModes[.dupesMerge] ?? .off
        let conflict = context.optionModes[.dupesConflict] ?? .off
        guard merge != .off || conflict != .off else { return .empty }
        // `sameAsk` serves the merge lines only. `opposite` serves the
        // conflict lines, and also guards the merge lines: a conflict wins
        // over a duplicate, so a pair that is a conflict never reads as a
        // repeat, also when its conflict line is off.
        let asking: Set<DupesConflicts.QuestionKind> = merge == .off ? [.opposite] : [.sameAsk, .opposite]

        // Drew chose notes and screen text, without images (2026-10-24). The
        // image path stays for a later choice, but this job never sends one.
        let allowed = context.allowed.subtracting(.images)
        let newEntries = DupesConflicts.entries(of: context.capture)
        let earlierCaptures = context.round.captures
            .filter { $0.index < context.capture.index }
            .sorted { $0.index < $1.index }
            .flatMap { DupesConflicts.entries(of: $0) }
        let candidates = DupesConflicts.candidates(earlierCaptures: earlierCaptures, new: newEntries)
        let checked = newEntries.filter { !candidates($0).isEmpty }
        guard !checked.isEmpty else { return .empty }

        let batches = DupesConflicts.batches(
            new: checked,
            candidates: candidates,
            allowed: allowed,
            images: context.images,
            asking: asking
        )
        let results = try await send(batches, using: context.jev)

        var lines: [JevRefinedLine] = []
        var flagged: [JevSummaryValue] = []
        var failures: [(reason: JevFailureReason, entries: [DupesConflicts.Entry])] = []
        var firstError: JevError?
        var anySucceeded = false
        for (batch, result) in zip(batches, results) {
            switch result {
            case .success(let response):
                anySucceeded = true
                for entry in batch.entries {
                    let outcomes = DupesConflicts.outcomes(of: entry, against: candidates(entry), in: response)
                    // A part in shadow adds to the summary only. A part in on adds its lines too.
                    lines += DupesConflicts.lines(for: entry, outcomes: DupesConflicts.kept(outcomes, merge: merge, conflict: conflict, modes: [.on]))
                    flagged += DupesConflicts.flaggedSummary(of: entry, outcomes: DupesConflicts.kept(outcomes, merge: merge, conflict: conflict, modes: [.shadow, .on]))
                }
            case .failure(let error):
                firstError = firstError ?? error
                if let index = failures.firstIndex(where: { $0.reason == error.reason }) {
                    failures[index].entries += batch.entries
                } else {
                    failures.append((error.reason, batch.entries))
                }
            }
        }
        if !anySucceeded, let firstError {
            throw firstError
        }

        var notChecked: [JevSummaryValue] = []
        for failure in failures {
            let reason = DupesConflicts.code(failure.reason)
            let labels = DupesConflicts.packed(failure.entries) { group in
                "Not checked for repeats (\(reason)): \(DupesConflicts.list(group.map(\.name)))."
            }
            // Say so only when a part writes lines. In shadow nothing shows.
            if merge == .on || conflict == .on {
                lines += labels.map { JevRefinedLine(scope: .capture, label: $0) }
            }
            notChecked += failure.entries.map { .fields(["entry": .code($0.id), "reason": .code(reason)]) }
        }
        return JevJobOutput(lines: lines, summary: [
            JevSummaryField(key: "flagged", value: .array(flagged)),
            JevSummaryField(key: "notChecked", value: .array(notChecked)),
        ])
    }

    /// Sends all requests in parallel. A `JevError` ends only its own request,
    /// so the other answers stay in use. Any other error (for example
    /// cancellation) ends the job. Results keep the order of `batches`.
    private func send(
        _ batches: [DupesConflicts.Batch],
        using asker: JevAsker
    ) async throws -> [Result<JevResponse, JevError>] {
        try await withThrowingTaskGroup(of: (Int, Result<JevResponse, JevError>).self) { group in
            for (position, batch) in batches.enumerated() {
                group.addTask {
                    do {
                        return (position, .success(try await asker.ask(batch.request)))
                    } catch let error as JevError {
                        return (position, .failure(error))
                    }
                }
            }
            var results = [Result<JevResponse, JevError>?](repeating: nil, count: batches.count)
            for try await (position, result) in group {
                results[position] = result
            }
            return results.compactMap { $0 }
        }
    }
}

/// The logic of the job, as plain functions so tests can call them.
///
/// Every id, key, question, and label is `JevCodeText`, built from literals
/// and numbers only. Drew's notes go out only as `.reviewer`, and screen text
/// only as `.screen`.
enum DupesConflicts {
    // MARK: Decision rules and questions

    /// `opposite` at or above this is a conflict, whatever `sameAsk` says. 0.7
    /// is TypeSafe's starting point for a Noul yes.
    static let conflictAt = 0.7
    /// `sameAsk` at or above this is a duplicate.
    static let duplicateAt = 1.5
    /// `sameAsk` at or above this, and below `duplicateAt`, is an overlap.
    static let overlapAt = 0.5

    /// A capture sends at most this many requests. The base allows 16 HTTP
    /// attempts per capture, retries included, so half are left for retries.
    /// A capture with more new entries shares requests.
    static let maxRequests = 8
    /// Earlier crops in one request, newest first. Other same-source pairs go
    /// text only.
    static let maxEarlierCrops = 6
    /// The crop of an item, as the note panel's preview shows it.
    static let cropMargin = 120
    static let cropAspectRatio = 4.0 / 3.0

    static let sameAskLevels: [JevValue] = [
        "They ask for different changes, or for changes to different elements. This includes the same kind of change on a different element, page, or screen.",
        "They overlap. Part of one ask is in the other, or they may be about the same element. A person should check.",
        "They ask for the same change to the same element.",
    ]
    static let oppositeYes: JevValue = "For example: larger and smaller, remove it and rename it, or two different values for the same setting."
    static let oppositeNo: JevValue = "Different elements, changes that can both be done, or one note adds detail to the other."

    static func sameAskText(position: Int) -> JevCodeText {
        "Compare the review note of `new[\(position)]` with earlier_note in this question. Both are a reviewer's change requests for an app's interface. How do the two notes relate as change requests?"
    }

    static func oppositeText(position: Int) -> JevCodeText {
        "Compare the review note of `new[\(position)]` with earlier_note in this question. Do the two notes ask for changes to the same element that cannot both be done?"
    }

    enum QuestionKind: String, Sendable {
        case sameAsk
        case opposite

        var code: JevCodeText {
            switch self {
            case .sameAsk: "sameAsk"
            case .opposite: "opposite"
            }
        }
    }

    enum Outcome: Equatable, Sendable {
        case conflict
        case duplicate
        case overlap
        case different

        /// The name in the jev.json summary, which the review script reads.
        var code: JevCodeText {
            switch self {
            case .conflict: "conflict"
            case .duplicate: "duplicate"
            case .overlap: "overlap"
            case .different: "different"
            }
        }
    }

    /// A conflict wins over a duplicate, because a false "same ask" would hide
    /// a real choice. A missing answer counts as different.
    static func outcome(sameAsk: Double?, opposite: Double?) -> Outcome {
        if let opposite, opposite >= conflictAt { return .conflict }
        guard let sameAsk else { return .different }
        if sameAsk >= duplicateAt { return .duplicate }
        if sameAsk >= overlapAt { return .overlap }
        return .different
    }

    /// The reason's raw value as code text. A new reason in the base stops
    /// the build here until it has a name.
    static func code(_ reason: JevFailureReason) -> JevCodeText {
        switch reason {
        case .timeout: "timeout"
        case .offline: "offline"
        case .rateLimited: "rateLimited"
        case .overloaded: "overloaded"
        case .server: "server"
        case .badRequest: "badRequest"
        case .unauthorized: "unauthorized"
        case .invalidResponse: "invalidResponse"
        case .modelMismatch: "modelMismatch"
        case .noKey: "noKey"
        case .consent: "consent"
        case .paused: "paused"
        case .capReached: "capReached"
        case .jobError: "jobError"
        }
    }

    // MARK: Entries

    /// One numbered item with a note (K.N), or one general note (K.note).
    struct Entry: Equatable, Sendable {
        var captureIndex: Int
        /// Nil for a general note.
        var badge: Int?
        /// Drew's words, exactly as stored.
        var note: String
        /// Nil for a general note, which has no mark.
        var screenText: String?
        var app: String?
        var windowTitle: String?
        /// The crop of an item in capture pixels. Nil for a note: the whole image.
        var cropRegion: FeedbackBox?

        /// K.N or K.note, from numbers only.
        var id: JevCodeText {
            if let badge { return "\(captureIndex).\(badge)" }
            return "\(captureIndex).note"
        }

        /// How a line names the entry in the middle of a sentence.
        var name: JevCodeText {
            if badge != nil { return id }
            return "the general note of capture \(captureIndex)"
        }

        /// How a line names the entry at the start of a sentence.
        var sentenceName: JevCodeText {
            if badge != nil { return id }
            return "The general note of capture \(captureIndex)"
        }

        /// The key of this entry in `earlier_screen_text` and `earlier_crops`.
        var key: JevCodeText {
            if let badge { return "e\(captureIndex)_\(badge)" }
            return "e\(captureIndex)_note"
        }

        /// Same capture, same app name, or same window title. A missing name
        /// never matches. Code decides this on the Mac, and it decides
        /// whether images go.
        func sharesSource(with other: Entry) -> Bool {
            if captureIndex == other.captureIndex { return true }
            if let app, app == other.app { return true }
            if let windowTitle, windowTitle == other.windowTitle { return true }
            return false
        }
    }

    /// The entries of one capture: the items with an instruction in badge
    /// order, then the general note.
    static func entries(of capture: FeedbackCapture) -> [Entry] {
        let app = ScreenText.field(capture.sourceApp)
        let windowTitle = ScreenText.field(capture.windowTitle)
        let crops = PreviewCrop.cropsByBadge(
            marks: capture.marks,
            imageSize: capture.size,
            margin: cropMargin,
            aspectRatio: cropAspectRatio
        )

        var entries: [Entry] = []
        for item in FeedbackItems.split(capture).items {
            guard let badge = item.badge.badge,
                  let instruction = item.badge.instruction,
                  hasText(instruction)
            else { continue }
            entries.append(Entry(
                captureIndex: capture.index,
                badge: badge,
                note: instruction,
                screenText: ScreenText.field(item.ocrText),
                app: app,
                windowTitle: windowTitle,
                cropRegion: crops[badge]
            ))
        }
        if let note = capture.note, hasText(note) {
            entries.append(Entry(
                captureIndex: capture.index,
                badge: nil,
                note: note,
                screenText: nil,
                app: app,
                windowTitle: windowTitle,
                cropRegion: nil
            ))
        }
        return entries
    }

    private static func hasText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The entries one new entry is compared with: every entry of the
    /// earlier captures, then the entries before it in its own capture
    /// (Drew, 2026-10-24). So each pair inside a capture runs once, and the
    /// first entry of the round has none.
    static func candidates(earlierCaptures: [Entry], new newEntries: [Entry]) -> @Sendable (Entry) -> [Entry] {
        { entry in
            let before = newEntries.prefix { $0 != entry }
            return earlierCaptures + before
        }
    }

    // MARK: Question ids

    /// `<new id>.vs.<earlier id>.sameAsk`, for example `4.2.vs.3.2.sameAsk`.
    /// The id starts with the new entry's id, as the base asks.
    static func questionID(new: Entry, earlier: Entry, kind: QuestionKind) -> JevCodeText {
        "\(new.id).vs.\(earlier.id).\(kind.code)"
    }

    /// Reads a question id from a response or jev.json back into its pair.
    /// Ids hold dots, so it splits on the last "." for the kind and on ".vs."
    /// for the two entry ids.
    static func parse(questionID: String) -> (new: String, earlier: String, kind: QuestionKind)? {
        guard let dot = questionID.lastIndex(of: "."),
              let kind = QuestionKind(rawValue: String(questionID[questionID.index(after: dot)...]))
        else { return nil }
        let pair = questionID[..<dot]
        guard let separator = pair.range(of: ".vs.") else { return nil }
        let new = pair[..<separator.lowerBound]
        let earlier = pair[separator.upperBound...]
        guard !new.isEmpty, !earlier.isEmpty else { return nil }
        return (String(new), String(earlier), kind)
    }

    // MARK: Requests

    /// One request and the new entries it holds.
    struct Batch: Sendable {
        var entries: [Entry]
        var request: JevRequest
    }

    /// One request per new entry. Above `maxRequests` entries, the entries
    /// split into exactly `maxRequests` chunks in order, as evenly as
    /// possible, with the larger chunks first.
    static func chunks(_ entries: [Entry]) -> [[Entry]] {
        guard entries.count > maxRequests else { return entries.map { [$0] } }
        let size = entries.count / maxRequests
        let larger = entries.count % maxRequests
        var chunks: [[Entry]] = []
        var start = 0
        for position in 0..<maxRequests {
            let end = start + size + (position < larger ? 1 : 0)
            chunks.append(Array(entries[start..<end]))
            start = end
        }
        return chunks
    }

    /// Builds the requests. Screen text goes only with `.screenText` allowed,
    /// and images only with `.images` allowed and only for same-source pairs.
    /// A failed image load leaves that image out. `candidates` gives the
    /// entries each new entry is compared with. `asking` names the questions
    /// each pair gets (the sub-flags decide, see `DupesConflictsJob`).
    static func batches(
        new newEntries: [Entry],
        candidates: (Entry) -> [Entry],
        allowed: JevDataKinds,
        images: JevImageLoader,
        asking: Set<QuestionKind> = [.sameAsk, .opposite]
    ) -> [Batch] {
        let sendScreenText = allowed.contains(.screenText)
        let sendImages = allowed.contains(.images)

        // One load per entry, also when it is an earlier crop in many requests.
        // A failed load is stored as nil, so it is not tried again.
        var loaded: [JevCodeText: JevImage?] = [:]
        func image(of entry: Entry) -> JevImage? {
            if let cached = loaded[entry.id] { return cached }
            let image = try? images.image(of: entry.captureIndex, .annotated, region: entry.cropRegion)
            loaded[entry.id] = .some(image)
            return image
        }

        var batches: [Batch] = []
        for chunk in chunks(newEntries) {
            // Every entry that a new entry of this request is compared with,
            // once each, in capture and badge order.
            var earlier: [Entry] = []
            for entry in chunk {
                for other in candidates(entry) where !earlier.contains(other) {
                    earlier.append(other)
                }
            }
            earlier.sort { ($0.captureIndex, $0.badge ?? Int.max) < ($1.captureIndex, $1.badge ?? Int.max) }

            var newValues: [JevValue] = []
            var newHasCrop: [Bool] = []
            for entry in chunk {
                var fields: [(JevCodeText, JevValue)] = [("id", .code(entry.id)), ("note", .reviewer(entry.note))]
                if sendScreenText {
                    if let text = entry.screenText { fields.append(("screen_text", .screen(text))) }
                    if let app = entry.app { fields.append(("app", .screen(app))) }
                }
                var hasCrop = false
                if sendImages,
                   newHasCrop.filter({ $0 }).count < JevRequestEncoder.maxImages,
                   candidates(entry).contains(where: { entry.sharesSource(with: $0) }),
                   let crop = image(of: entry) {
                    fields.append(("crop", .image(crop)))
                    hasCrop = true
                }
                newValues.append(.object(fields))
                newHasCrop.append(hasCrop)
            }

            var state: [(JevCodeText, JevValue)] = [("new", .array(newValues))]

            var screenKeys = Set<JevCodeText>()
            if sendScreenText {
                let texts = earlier.compactMap { entry -> (JevCodeText, JevValue)? in
                    entry.screenText.map { (entry.key, JevValue.screen($0)) }
                }
                if !texts.isEmpty {
                    state.append(("earlier_screen_text", .object(texts)))
                    screenKeys = Set(texts.map(\.0))
                }
            }

            var cropKeys = Set<JevCodeText>()
            if sendImages {
                // The encoder refuses a request with more images than its
                // limit, so the new crops come first and the earlier crops
                // fill what is left.
                let limit = min(maxEarlierCrops, JevRequestEncoder.maxImages - newHasCrop.filter { $0 }.count)
                var crops: [(JevCodeText, JevValue)] = []
                for entry in earlier.reversed() where chunk.contains(where: { candidates($0).contains(entry) && $0.sharesSource(with: entry) }) {
                    guard crops.count < limit else { break }
                    if let crop = image(of: entry) {
                        crops.append((entry.key, .image(crop)))
                    }
                }
                if !crops.isEmpty {
                    state.append(("earlier_crops", .object(crops)))
                    cropKeys = Set(crops.map(\.0))
                }
            }

            let stateValue = JevValue.object(state)
            let notice: JevCodeText = stateValue.kinds.contains(.screenText) ? "\(JevPrompting.screenTextNotice) " : ""
            var questions: [(id: JevCodeText, question: JevQuestion)] = []
            for (position, entry) in chunk.enumerated() {
                for other in candidates(entry) {
                    var pointers: [JevCodeText] = []
                    if screenKeys.contains(other.key) {
                        pointers.append(" Screen text for earlier_note: `earlier_screen_text.\(other.key)`.")
                    }
                    if cropKeys.contains(other.key) {
                        pointers.append(" Crop for earlier_note: `earlier_crops.\(other.key)`.")
                    }
                    if newHasCrop[position] {
                        pointers.append(" Crop for the new note: `new[\(position)].crop`.")
                    }
                    let suffix = JevCodeText.joined(pointers, separator: "")

                    func instructions(_ text: JevCodeText) -> JevValue {
                        .fields([
                            "question": .code("\(notice)\(text)\(suffix)"),
                            "earlier_id": .code(other.id),
                            "earlier_note": .reviewer(other.note),
                        ])
                    }
                    if asking.contains(.sameAsk) {
                        questions.append((
                            questionID(new: entry, earlier: other, kind: .sameAsk),
                            .score(instructions(sameAskText(position: position)), levels: sameAskLevels)
                        ))
                    }
                    if asking.contains(.opposite) {
                        questions.append((
                            questionID(new: entry, earlier: other, kind: .opposite),
                            .noul(instructions(oppositeText(position: position)), yes: oppositeYes, no: oppositeNo)
                        ))
                    }
                }
            }
            batches.append(Batch(entries: chunk, request: JevRequest(state: stateValue, questions: questions)))
        }
        return batches
    }

    // MARK: Outcomes, lines, and the summary

    /// The outcome of each pair of one new entry, in the order of `earlier`.
    static func outcomes(
        of entry: Entry,
        against earlier: [Entry],
        in response: JevResponse
    ) -> [(earlier: Entry, outcome: Outcome)] {
        earlier.map { other in
            let sameAsk = response.score(questionID(new: entry, earlier: other, kind: .sameAsk).text)?.score
            let opposite = response.noul(questionID(new: entry, earlier: other, kind: .opposite).text)
            return (other, outcome(sameAsk: sameAsk, opposite: opposite))
        }
    }

    /// Keeps the outcomes of the parts whose mode is in `modes`. An outcome of
    /// any other part becomes `.different`, so it adds no line and no summary
    /// entry. A conflict that is hidden this way hides the pair's duplicate
    /// too, because `outcome(sameAsk:opposite:)` already let the conflict win:
    /// a pair that is a conflict never gets a "make the change once" line.
    /// Lines use `[.on]`, and the summary uses `[.shadow, .on]`.
    static func kept(
        _ outcomes: [(earlier: Entry, outcome: Outcome)],
        merge: FlagState,
        conflict: FlagState,
        modes: Set<FlagState>
    ) -> [(earlier: Entry, outcome: Outcome)] {
        outcomes.map { pair in
            switch pair.outcome {
            case .conflict: (pair.earlier, modes.contains(conflict) ? .conflict : .different)
            case .duplicate, .overlap: (pair.earlier, modes.contains(merge) ? pair.outcome : .different)
            case .different: pair
            }
        }
    }

    /// The jev.json summary of one new entry: each pair that is not
    /// different, as `{"pair": "4.2.vs.3.2", "outcome": "duplicate"}`. The
    /// review script reads it, so it needs none of this file's logic.
    static func flaggedSummary(of entry: Entry, outcomes: [(earlier: Entry, outcome: Outcome)]) -> [JevSummaryValue] {
        outcomes.filter { $0.outcome != .different }.map { pair in
            .fields([
                "pair": .code("\(entry.id).vs.\(pair.earlier.id)"),
                "outcome": .code(pair.outcome.code),
            ])
        }
    }

    /// The lines for one new entry. Each line names its own entry first, so it
    /// reads the same alone, in a capture section, and in the round section.
    /// No line holds screen text, a file name, or a quoted note, and no line
    /// says to skip a change.
    ///
    /// Duplicates and conflicts get round lines only: the writer puts a
    /// capture's round lines at the top of its own refined file and of
    /// refined.md, so a second line per item would repeat them. Overlaps stay
    /// in the item's section.
    static func lines(for entry: Entry, outcomes: [(earlier: Entry, outcome: Outcome)]) -> [JevRefinedLine] {
        let scope: JevRefinedLine.Scope = entry.badge.map { .item(badge: $0) } ?? .capture
        var lines: [JevRefinedLine] = []

        // An earlier paste can only have done the work when an entry comes
        // from an earlier capture. Entries of the same capture go in one paste.
        func fromEarlierCapture(_ group: [Entry]) -> Bool {
            group.contains { $0.captureIndex < entry.captureIndex }
        }

        let duplicates = outcomes.filter { $0.outcome == .duplicate }.map(\.earlier)
        for label in packed(duplicates, label: { group in
            let allCaptures = captures(group.map(\.captureIndex) + [entry.captureIndex])
            let paste: JevCodeText = fromEarlierCapture(group) ? " An earlier paste may have made this change. Check the code, and make the change once." : " Make the change once."
            return "Same ask: \(entry.name) repeats \(list(group.map(\.name))) (\(allCaptures)).\(paste) Each note is in manifest.md."
        }) {
            lines.append(JevRefinedLine(scope: .round, label: label))
        }

        let overlaps = outcomes.filter { $0.outcome == .overlap }.map(\.earlier)
        for label in packed(overlaps, label: { group in
            let read: JevCodeText = group.count == 1 ? group[0].name : "them"
            let paste: JevCodeText = fromEarlierCapture(group) ? " An earlier paste may have done part of it." : ""
            return "\(entry.sentenceName) may overlap with \(list(group.map(\.name))). Read \(read) in manifest.md.\(paste) Check the code before you edit twice."
        }) {
            lines.append(JevRefinedLine(scope: scope, label: label))
        }

        for other in outcomes.filter({ $0.outcome == .conflict }).map(\.earlier) {
            lines.append(JevRefinedLine(
                scope: .round,
                label: "Ask first: \(entry.name) and \(other.name) ask for opposite changes to the same element. Read both in manifest.md. Ask the user which one wins before you edit either. \(entry.sentenceName) is newer."
            ))
        }
        return lines
    }

    /// The writer cuts a label at this length, so a long list splits into
    /// several lines instead.
    static let maxLabelLength = JevRefinedRenderer.maxLabelLength

    /// Packs entries into as few labels as possible, each at most
    /// `maxLabelLength` scalars. A label for one entry always goes out, even
    /// when it is longer, so no entry is lost.
    static func packed(_ entries: [Entry], label: ([Entry]) -> JevCodeText) -> [JevCodeText] {
        var labels: [JevCodeText] = []
        var group: [Entry] = []
        for entry in entries {
            if !group.isEmpty, label(group + [entry]).text.unicodeScalars.count > maxLabelLength {
                labels.append(label(group))
                group = []
            }
            group.append(entry)
        }
        if !group.isEmpty {
            labels.append(label(group))
        }
        return labels
    }

    /// "A", "A and B", "A, B, and C".
    static func list(_ parts: [JevCodeText]) -> JevCodeText {
        switch parts.count {
        case 0: ""
        case 1: parts[0]
        case 2: "\(parts[0]) and \(parts[1])"
        default: "\(JevCodeText.joined(Array(parts.dropLast()), separator: ", ")), and \(parts[parts.count - 1])"
        }
    }

    /// "capture 1", "captures 1 and 3", "captures 1, 2, and 3".
    static func captures(_ indexes: [Int]) -> JevCodeText {
        let sorted = Set(indexes).sorted()
        let numbers = sorted.map { number -> JevCodeText in "\(number)" }
        return sorted.count == 1 ? "capture \(list(numbers))" : "captures \(list(numbers))"
    }
}
