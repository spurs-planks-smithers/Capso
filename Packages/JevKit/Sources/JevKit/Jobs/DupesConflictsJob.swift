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
public struct DupesConflictsJob: JevJob {
    public let id = "dupesConflicts"
    public let flag = FeatureFlag.dupesConflicts
    public let requires: JevDataKinds = []
    public let version = 1

    public init() {}

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        let newEntries = DupesConflicts.entries(of: context.capture)
        let earlier = context.round.captures
            .filter { $0.index < context.capture.index }
            .sorted { $0.index < $1.index }
            .flatMap { DupesConflicts.entries(of: $0) }
        guard !newEntries.isEmpty, !earlier.isEmpty else { return .empty }

        let batches = DupesConflicts.batches(
            new: newEntries,
            earlier: earlier,
            allowed: context.allowed,
            images: context.images
        )
        let results = try await send(batches, using: context.jev)

        var lines: [JevRefinedLine] = []
        var failures: [(reason: JevFailureReason, entries: [DupesConflicts.Entry])] = []
        var firstError: JevError?
        var anySucceeded = false
        for (batch, result) in zip(batches, results) {
            switch result {
            case .success(let response):
                anySucceeded = true
                for entry in batch.entries {
                    let outcomes = DupesConflicts.outcomes(of: entry, against: earlier, in: response)
                    lines += DupesConflicts.lines(for: entry, outcomes: outcomes)
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

        for failure in failures {
            let labels = DupesConflicts.packed(failure.entries) { group in
                "Not checked for repeats (\(failure.reason.rawValue)): \(DupesConflicts.list(group.map(\.name)))."
            }
            lines += labels.map { JevRefinedLine(scope: .capture, label: $0) }
        }
        return JevJobOutput(lines: lines)
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

/// The logic of the job, as plain functions so tests and the review script
/// can call them.
enum DupesConflicts {
    // MARK: Decision rules and questions

    /// `opposite` at or above this is a conflict, whatever `sameAsk` says. 0.7
    /// is TypeSafe's starting point for a Noul yes.
    static let conflictAt = 0.7
    /// `sameAsk` at or above this is a duplicate.
    static let duplicateAt = 1.5
    /// `sameAsk` at or above this, and below `duplicateAt`, is an overlap.
    static let overlapAt = 0.5

    /// A capture sends at most this many requests (the base's cap). A capture
    /// with more new entries shares requests.
    static let maxRequests = 16
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

    static func sameAskText(position: Int) -> String {
        "Compare the review note of `new[\(position)]` with earlier_note in this question. Both are a reviewer's change requests for an app's interface. How do the two notes relate as change requests?"
    }

    static func oppositeText(position: Int) -> String {
        "Compare the review note of `new[\(position)]` with earlier_note in this question. Do the two notes ask for changes to the same element that cannot both be done?"
    }

    enum QuestionKind: String, Sendable {
        case sameAsk
        case opposite
    }

    enum Outcome: Equatable, Sendable {
        case conflict
        case duplicate
        case overlap
        case different
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

    // MARK: Entries

    /// One numbered item with a note (K.N), or one general note (K.note).
    struct Entry: Equatable, Sendable {
        var id: String
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

        /// How a line names the entry in the middle of a sentence.
        var name: String {
            badge == nil ? "the general note of capture \(captureIndex)" : id
        }

        /// How a line names the entry at the start of a sentence.
        var sentenceName: String {
            badge == nil ? "The general note of capture \(captureIndex)" : id
        }

        /// The key of this entry in `earlier_screen_text` and `earlier_crops`.
        /// It comes from numbers only, never from screen text.
        var key: String {
            "e\(captureIndex)_\(badge.map(String.init) ?? "note")"
        }

        /// Same app name, or same window title. A missing name never matches.
        /// Code decides this on the Mac, and it decides whether images go.
        func sharesSource(with other: Entry) -> Bool {
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
                id: item.id,
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
                id: "\(capture.index).note",
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

    // MARK: Question ids

    /// `<new id>.vs.<earlier id>.sameAsk`, for example `4.2.vs.3.2.sameAsk`.
    /// The id starts with the new entry's id, as the base asks.
    static func questionID(new: String, earlier: String, kind: QuestionKind) -> String {
        "\(new).vs.\(earlier).\(kind.rawValue)"
    }

    /// Reads a question id back into its pair. Ids hold dots, so it splits on
    /// the last "." for the kind and on ".vs." for the two entry ids.
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
    /// A failed image load leaves that image out.
    static func batches(
        new newEntries: [Entry],
        earlier: [Entry],
        allowed: JevDataKinds,
        images: JevImageLoader
    ) -> [Batch] {
        let sendScreenText = allowed.contains(.screenText)
        let sendImages = allowed.contains(.images)

        // One load per entry, also when it is an earlier crop in many requests.
        // A failed load is stored as nil, so it is not tried again.
        var loaded: [String: JevImage?] = [:]
        func image(of entry: Entry) -> JevImage? {
            if let cached = loaded[entry.id] { return cached }
            let image = try? images.image(of: entry.captureIndex, .annotated, region: entry.cropRegion)
            loaded[entry.id] = .some(image)
            return image
        }

        var batches: [Batch] = []
        for chunk in chunks(newEntries) {
            var newValues: [JevValue] = []
            var newHasCrop: [Bool] = []
            for entry in chunk {
                var fields: [(String, JevValue)] = [("id", .code(entry.id)), ("note", .reviewer(entry.note))]
                if sendScreenText {
                    if let text = entry.screenText { fields.append(("screen_text", .screen(text))) }
                    if let app = entry.app { fields.append(("app", .screen(app))) }
                }
                var hasCrop = false
                if sendImages,
                   earlier.contains(where: { entry.sharesSource(with: $0) }),
                   let crop = image(of: entry) {
                    fields.append(("crop", .image(crop)))
                    hasCrop = true
                }
                newValues.append(.object(fields))
                newHasCrop.append(hasCrop)
            }

            var state: [(String, JevValue)] = [("new", .array(newValues))]

            var screenKeys = Set<String>()
            if sendScreenText {
                let texts = earlier.compactMap { entry in
                    entry.screenText.map { (entry.key, JevValue.screen($0)) }
                }
                if !texts.isEmpty {
                    state.append(("earlier_screen_text", .object(texts)))
                    screenKeys = Set(texts.map(\.0))
                }
            }

            var cropKeys = Set<String>()
            if sendImages {
                var crops: [(String, JevValue)] = []
                for entry in earlier.reversed() where chunk.contains(where: { $0.sharesSource(with: entry) }) {
                    guard crops.count < maxEarlierCrops else { break }
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
            let notice = stateValue.kinds.contains(.screenText) ? JevPrompting.screenTextNotice + " " : ""
            var questions: [(id: String, question: JevQuestion)] = []
            for (position, entry) in chunk.enumerated() {
                for other in earlier {
                    var pointers = ""
                    if screenKeys.contains(other.key) {
                        pointers += " Screen text for earlier_note: `earlier_screen_text.\(other.key)`."
                    }
                    if cropKeys.contains(other.key) {
                        pointers += " Crop for earlier_note: `earlier_crops.\(other.key)`."
                    }
                    if newHasCrop[position] {
                        pointers += " Crop for the new note: `new[\(position)].crop`."
                    }

                    func instructions(_ text: String) -> JevValue {
                        .fields([
                            "question": .code(notice + text + pointers),
                            "earlier_id": .code(other.id),
                            "earlier_note": .reviewer(other.note),
                        ])
                    }
                    questions.append((
                        questionID(new: entry.id, earlier: other.id, kind: .sameAsk),
                        .score(instructions(sameAskText(position: position)), levels: sameAskLevels)
                    ))
                    questions.append((
                        questionID(new: entry.id, earlier: other.id, kind: .opposite),
                        .noul(instructions(oppositeText(position: position)), yes: oppositeYes, no: oppositeNo)
                    ))
                }
            }
            batches.append(Batch(entries: chunk, request: JevRequest(state: stateValue, questions: questions)))
        }
        return batches
    }

    // MARK: Outcomes and lines

    /// The outcome of each pair of one new entry, in the order of `earlier`.
    static func outcomes(
        of entry: Entry,
        against earlier: [Entry],
        in response: JevResponse
    ) -> [(earlier: Entry, outcome: Outcome)] {
        earlier.map { other in
            let sameAsk = response.score(questionID(new: entry.id, earlier: other.id, kind: .sameAsk))?.score
            let opposite = response.noul(questionID(new: entry.id, earlier: other.id, kind: .opposite))
            return (other, outcome(sameAsk: sameAsk, opposite: opposite))
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

        let duplicates = outcomes.filter { $0.outcome == .duplicate }.map(\.earlier)
        for group in packed(duplicates, label: { group in
            let allCaptures = captures(group.map(\.captureIndex) + [entry.captureIndex])
            return "Same ask: \(entry.name) repeats \(list(group.map(\.name))) (\(allCaptures)). An earlier paste may have made this change. Check the code, and make the change once. Each note is in manifest.md."
        }) {
            lines.append(JevRefinedLine(scope: .round, label: group))
        }

        let overlaps = outcomes.filter { $0.outcome == .overlap }.map(\.earlier)
        for group in packed(overlaps, label: { group in
            let read = group.count == 1 ? group[0].name : "them"
            return "\(entry.sentenceName) may overlap with \(list(group.map(\.name))). Read \(read) in manifest.md. An earlier paste may have done part of it. Check the code before you edit twice."
        }) {
            lines.append(JevRefinedLine(scope: scope, label: group))
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
    static func packed(_ entries: [Entry], label: ([Entry]) -> String) -> [String] {
        var labels: [String] = []
        var group: [Entry] = []
        for entry in entries {
            if !group.isEmpty, label(group + [entry]).unicodeScalars.count > maxLabelLength {
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
    static func list(_ parts: [String]) -> String {
        switch parts.count {
        case 0: ""
        case 1: parts[0]
        case 2: "\(parts[0]) and \(parts[1])"
        default: "\(parts.dropLast().joined(separator: ", ")), and \(parts[parts.count - 1])"
        }
    }

    /// "capture 1", "captures 1 and 3", "captures 1, 2, and 3".
    static func captures(_ indexes: [Int]) -> String {
        let sorted = Set(indexes).sorted()
        return "\(sorted.count == 1 ? "capture" : "captures") \(list(sorted.map(String.init)))"
    }
}
