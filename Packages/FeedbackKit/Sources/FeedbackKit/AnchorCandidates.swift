// Packages/FeedbackKit/Sources/FeedbackKit/AnchorCandidates.swift
import Foundation

/// One line of screen text that can be a search line, with the id the Choice
/// question uses. The model sees the text through the id and never gets it as an option name.
public struct AnchorLine: Equatable, Sendable {
    public var id: String
    public var text: String
    /// Where the line came from: its position in the `lines` array given to
    /// `AnchorCandidates.build`, or its row in the stored OCR block when there
    /// are no line boxes. A review script can find the line again with it.
    public var source: Int
    /// The line's box in export pixels. Nil when the line comes from the stored OCR block.
    public var box: FeedbackBox?

    public init(id: String, text: String, source: Int, box: FeedbackBox? = nil) {
        self.id = id
        self.text = text
        self.source = source
        self.box = box
    }
}

/// The search-line candidates of one capture.
public struct AnchorCandidateSet: Equatable, Sendable {
    /// Every kept line once, with ids in reading order.
    public var lines: [AnchorLine]
    /// The ids offered for each badge number, nearest first.
    public var itemCandidates: [Int: [String]]
    /// The ids offered for the general note. Set only for a capture with no
    /// badges and a note.
    public var captureCandidates: [String]?

    public init(lines: [AnchorLine], itemCandidates: [Int: [String]], captureCandidates: [String]? = nil) {
        self.lines = lines
        self.itemCandidates = itemCandidates
        self.captureCandidates = captureCandidates
    }
}

/// What code decides after Jev answers the Choice question for one item.
public enum AnchorPick: Equatable, Sendable {
    /// The line to use, with its text exactly as stored.
    case picked(id: String, text: String)
    /// The answer is valid, but a score is below its threshold.
    case noneFit
    /// The answer cannot be used: the choice is not an offered line, or a score is not a probability.
    case invalid
}

/// Candidates for the search line of an item: one OCR line, word for word,
/// that the agent can search the repository for. See "Anchor text" in
/// `docs/superpowers/specs/2026-10-24-crops-anchors-design.md`.
///
/// Each candidate is one OCR line. The joined mark text in `manifest.md` is
/// never a candidate, because it can hold several lines.
public enum AnchorCandidates {
    /// The most lines kept per item from the window, nearest first. Lines
    /// under the item's own marks come on top of these.
    public static let perItem = 40
    /// The most lines when there are no line boxes, or for a capture-level search line.
    public static let fallbackLimit = 120
    /// A line shorter than this many characters is not a candidate.
    public static let minLength = 3
    /// The most ids one item offers. A Jev Choice takes at most 255 options,
    /// and a box over a whole window can hold more lines than that.
    public static let maxOptions = 250

    /// Builds the candidates of a capture.
    ///
    /// With line boxes, an item gets the lines that touch its window, nearest
    /// to its seed box first, plus every line that `OCRMatcher` picks for its
    /// badge and its shape. Without line boxes (`lines` is nil or empty), every
    /// item gets the lines of the stored OCR block. A capture with no badges
    /// and a note gets capture-level candidates. A capture with no badges and
    /// no note gets nothing.
    public static func build(capture: FeedbackCapture, lines: [FeedbackTextLine]?) -> AnchorCandidateSet {
        var items: [FeedbackItem] = []
        var numbers = Set<Int>()
        for item in FeedbackItems.split(capture).items {
            guard let number = item.badge.badge, numbers.insert(number).inserted else { continue }
            items.append(item)
        }
        let wantsCaptureLevel = items.isEmpty && hasNote(capture)
        guard !items.isEmpty || wantsCaptureLevel else {
            return AnchorCandidateSet(lines: [], itemCandidates: [:], captureCandidates: nil)
        }

        // The save task already drops lines under Redact marks. Dropping them
        // here again keeps redacted text out of a request if a caller forgets.
        // `sources` keeps each line's position in the input.
        let input = lines ?? []
        let sources = input.indices.filter { !OCRMatcher.removingRedacted([input[$0]], marks: capture.marks).isEmpty }
        if !sources.isEmpty {
            return fromBoxes(capture: capture, items: items, wantsCaptureLevel: wantsCaptureLevel, lines: sources.map { input[$0] }, sources: sources)
        }
        return fromStoredText(capture: capture, items: items, wantsCaptureLevel: wantsCaptureLevel)
    }

    /// Decides what to do with Jev's answer for one item.
    ///
    /// The choice must be an offered id that is also in `lines`, and both
    /// scores must be probabilities. Otherwise the answer is `.invalid`. A score
    /// below its threshold gives `.noneFit`. Otherwise the line comes back
    /// with its text unchanged.
    public static func pick(
        choice: String?,
        offered: [String],
        fits: Double,
        confidence: Double,
        fitsThreshold: Double,
        confidenceThreshold: Double,
        lines: [AnchorLine]
    ) -> AnchorPick {
        guard let choice, offered.contains(choice), let line = lines.first(where: { $0.id == choice }),
              isProbability(fits), isProbability(confidence)
        else { return .invalid }
        if fits < fitsThreshold || confidence < confidenceThreshold {
            return .noneFit
        }
        return .picked(id: line.id, text: line.text)
    }

    // MARK: Candidates from line boxes

    private static func fromBoxes(
        capture: FeedbackCapture,
        items: [FeedbackItem],
        wantsCaptureLevel: Bool,
        lines: [FeedbackTextLine],
        sources: [Int]
    ) -> AnchorCandidateSet {
        // The lines that pass the filters, by position in `lines`.
        var kept: [Int: String] = [:]
        for (position, line) in lines.enumerated() {
            if let text = candidateText(line.text) {
                kept[position] = text
            }
        }
        func readsBefore(_ lhs: Int, _ rhs: Int) -> Bool {
            (lines[lhs].box.y1, lines[lhs].box.x1, lhs) < (lines[rhs].box.y1, lines[rhs].box.x1, rhs)
        }

        var positionsByBadge: [Int: [Int]] = [:]
        for item in items {
            guard let number = item.badge.badge else { continue }
            let seed = item.focus
            let window = ItemCrop.window(seed: seed, imageSize: capture.size)
            var positions = kept.keys
                .filter { window.intersects(lines[$0].box) }
                .map { (position: $0, distance: seed.distance(to: lines[$0].box.center)) }
                .sorted { lhs, rhs in
                    lhs.distance == rhs.distance ? readsBefore(lhs.position, rhs.position) : lhs.distance < rhs.distance
                }
                .prefix(perItem)
                .map(\.position)

            // The matcher picks from every line. A pick that fails the filters stays out.
            let marks = [item.badge] + (item.shape.map { [$0] } ?? [])
            for mark in marks {
                for matched in OCRMatcher.matchedLines(for: mark, lines: lines) {
                    guard let position = lines.firstIndex(of: matched), kept[position] != nil, !positions.contains(position) else { continue }
                    positions.append(position)
                }
            }
            positionsByBadge[number] = Array(positions.prefix(maxOptions))
        }

        let captureLevel: [Int]? = wantsCaptureLevel
            ? Array(kept.keys.sorted(by: readsBefore).prefix(fallbackLimit))
            : nil

        // One id per line, in reading order, however many items offer it.
        let used = Set(positionsByBadge.values.flatMap { $0 }).union(captureLevel ?? [])
        let ordered = used.sorted(by: readsBefore).compactMap { position in kept[position].map { (position: position, text: $0) } }
        var idByPosition: [Int: String] = [:]
        var anchors: [AnchorLine] = []
        for (index, entry) in ordered.enumerated() {
            let anchor = AnchorLine(id: id(index + 1), text: entry.text, source: sources[entry.position], box: lines[entry.position].box)
            idByPosition[entry.position] = anchor.id
            anchors.append(anchor)
        }

        return AnchorCandidateSet(
            lines: anchors,
            itemCandidates: positionsByBadge.mapValues { $0.compactMap { idByPosition[$0] } },
            captureCandidates: captureLevel.map { $0.compactMap { idByPosition[$0] } }
        )
    }

    // MARK: Candidates from the stored OCR block

    private static func fromStoredText(capture: FeedbackCapture, items: [FeedbackItem], wantsCaptureLevel: Bool) -> AnchorCandidateSet {
        let block = capture.ocrText ?? ""
        var rows = block.components(separatedBy: .newlines)
        // A block over the stored limit was cut and ends in "...". Its last
        // line is then partial, and no code search would match it.
        if block.unicodeScalars.count > ScreenText.maxBlockLength {
            rows.removeLast()
        }
        let texts = rows.enumerated()
            .compactMap { row, raw in candidateText(raw).map { (row: row, text: $0) } }
            .prefix(fallbackLimit)
        let anchors = texts.enumerated().map { AnchorLine(id: id($0.offset + 1), text: $0.element.text, source: $0.element.row) }
        let ids = anchors.map(\.id)

        var itemCandidates: [Int: [String]] = [:]
        for item in items {
            if let number = item.badge.badge {
                itemCandidates[number] = ids
            }
        }
        return AnchorCandidateSet(lines: anchors, itemCandidates: itemCandidates, captureCandidates: wantsCaptureLevel ? ids : nil)
    }

    // MARK: Helpers

    private static func hasNote(_ capture: FeedbackCapture) -> Bool {
        guard let note = capture.note else { return false }
        return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The cleaned text of a line, or nil when the line is not a candidate:
    /// no letters, or under `minLength` characters.
    private static func candidateText(_ raw: String) -> String? {
        let text = ScreenText.clean(raw, singleLine: true, maxScalars: ScreenText.maxFieldLength)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= minLength, text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return nil
        }
        return text
    }

    /// `L001`, `L002`, and on. A capture with more than 999 lines gets longer ids.
    private static func id(_ number: Int) -> String {
        String(format: "L%03d", number)
    }

    private static func isProbability(_ value: Double) -> Bool {
        value.isFinite && (0...1).contains(value)
    }
}
