// Packages/JevKit/Sources/JevKit/Jobs/CropsAnchorsJob.swift
import CoreGraphics
import FeedbackKit
import Foundation
import ImageIO

/// Crops and anchor text (ideas 7 and 8, issue #38, flag `cropsAnchors`):
/// one edge-checked crop and one search line per item.
///
/// The design is `docs/superpowers/specs/2026-10-24-crops-anchors-design.md`.
/// The job runs the same questions in shadow and on. It reads only the
/// capture's two PNGs, writes nothing, and never throws.
///
/// - Crops: request A finds the target in a window around each item. Request
///   B (up to twice) checks each edge. With images not allowed, each crop is
///   cut around the marks and no request goes out.
/// - Search lines: request C picks one OCR line per item. It holds no image.
///
/// Every question id, state key, option name, and label is `JevCodeText`: a
/// literal with numbers and other code text in it. OCR text goes only into
/// `.screen` values under `screen_text` keys.
///
/// Each part has a sub-flag (#94): `cropsItemCrops` for the crop PNGs and
/// their lines, and `cropsSearchLines` for the search lines. The runner caps
/// each at the state of `cropsAnchors`. A part whose sub-flag is off sends no
/// request and adds nothing to the summary. A part in shadow records its
/// answers and summary, and writes no file and no line. With both off, the job
/// returns nothing.
public struct CropsAnchorsJob: JevJob {
    public let id = "cropsAnchors"
    public let flag = FeatureFlag.cropsAnchors
    /// Crops around the marks and notes need no consent beyond reviewer text.
    public let requires: JevDataKinds = []
    public let version = 2

    public var options: [FeatureFlag] { [.cropsItemCrops, .cropsSearchLines] }

    /// Request A: the lowest `target_shown` probability that counts as shown.
    static let targetShownThreshold = 0.5
    /// Request A: the lowest Box confidence that counts. A correct Box on 2026-10-24 had 0.45.
    /// A Box with no confidence counts as below it. TypeSafe's Box docs say a
    /// Box answer always carries a confidence, so nil means the answer is incomplete.
    static let targetConfidenceThreshold = 0.3
    /// Request B: the lowest probability that counts as "the thing continues past this edge".
    static let edgeCutThreshold = 0.5
    /// Request C: the lowest `anchor_fits` probability that counts as a fit.
    static let anchorFitsThreshold = 0.5
    /// Request C: the lowest Choice confidence that counts. A Choice over up to 250 lines spreads its probability.
    static let anchorConfidenceThreshold = 0.2
    /// The runner drops all output at the deadline. No request or image load
    /// starts this close to it, which leaves time to cut and encode the crop PNGs.
    static let defaultRequestMargin: Duration = .milliseconds(500)
    /// The crop PNGs are cut one item at a time. None starts this close to the deadline.
    static let defaultOutputMargin: Duration = .milliseconds(100)

    private let requestMargin: Duration
    private let outputMargin: Duration

    public init() {
        self.init(requestMargin: Self.defaultRequestMargin, outputMargin: Self.defaultOutputMargin)
    }

    /// Tests pass wider margins, so a loaded machine cannot close the window between the two (issue #91).
    init(requestMargin: Duration, outputMargin: Duration) {
        self.requestMargin = requestMargin
        self.outputMargin = outputMargin
    }

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        let cropsMode = context.optionModes[.cropsItemCrops] ?? .off
        let searchMode = context.optionModes[.cropsSearchLines] ?? .off
        guard cropsMode != .off || searchMode != .off else { return .empty }

        let items = Self.items(of: context.capture)
        let cutoff = context.deadline - requestMargin
        // Only crop files in on mode need the PNGs. They decode while the
        // requests are in flight.
        let cropFileItems = cropsMode == .on ? items : []
        async let annotated = Self.decode(context.capture.imageFile, ifAny: cropFileItems, context: context)
        async let clean = Self.decode(context.capture.cleanImageFile, ifAny: cropFileItems, context: context)
        async let crops = Self.findCrops(items, context: context, cutoff: cutoff)
        async let search = Self.findSearchLines(items, context: context, cutoff: cutoff)
        let (foundCrops, foundSearch, pngs) = await (crops, search, (annotated, clean))

        var output = Self.output(items: items, crops: foundCrops.crops, search: foundSearch, pngs: pngs, context: context, outputMargin: outputMargin)
        output.summary = Self.summary(
            items: items, crops: foundCrops.crops, search: foundSearch, captureIndex: context.capture.index,
            withCrops: cropsMode != .off, withSearch: searchMode != .off
        )
        output.failure = foundCrops.failure ?? foundSearch.failure
        return output
    }
}

// MARK: - Items and results

/// One numbered badge of the capture, with what the job needs about it.
private struct Item: Sendable {
    var captureIndex: Int
    var badge: Int
    /// The badge, its shape, and its arrow tip.
    var seed: FeedbackBox
    /// Drew's words for this badge. Nil when he wrote none.
    var note: String?
    /// The screen text under the item's marks. Nil when there is none.
    var markText: String?

    /// The item id, K.N, for question ids.
    var prefix: JevCodeText { "\(captureIndex).\(badge)" }

    /// Drew's note, or code text that says what to use in its place.
    func noteValue(missing: JevCodeText) -> JevValue {
        note.map(JevValue.reviewer) ?? .code(missing)
    }
}

/// How far a crop was checked.
private enum CropStatus: Sendable {
    case checked
    case edgesUnsure
    case marksOnly
    case notChecked
    case tooSmall
    case notWorthIt

    /// The words in the crop label. Nil when the item gets no crop lines.
    var words: JevCodeText? {
        switch self {
        case .checked: "edges checked"
        case .edgesUnsure: "edges unsure: open the full image if the crop cuts something off"
        case .marksOnly: "cut around the marks, not checked"
        case .notChecked: "not checked: open the full image if the crop cuts something off"
        case .tooSmall, .notWorthIt: nil
        }
    }

    var summary: JevSummaryValue {
        switch self {
        case .checked: "checked"
        case .edgesUnsure: "edgesUnsure"
        case .marksOnly: "marksOnly"
        case .notChecked: "notChecked"
        case .tooSmall: "tooSmall"
        case .notWorthIt: "notWorthIt"
        }
    }
}

/// Where a crop's box came from.
private enum CropSource: Sendable {
    /// Jev's Box for the target.
    case target
    /// The seed box plus a pad.
    case marks

    var summary: JevSummaryValue {
        switch self {
        case .target: "target"
        case .marks: "marks"
        }
    }
}

private struct Crop: Sendable {
    var box: FeedbackBox
    var status: CropStatus
    var source: CropSource
    /// The region sent to Jev in request A, in capture pixels. Nil when request A did not hold the item.
    var window: FeedbackBox?
    /// Jev's target in capture pixels. Nil unless the target crop was used.
    var target: FeedbackBox?
}

/// A crop that still needs an edge check.
private struct OpenCrop: Sendable {
    var item: Item
    var box: FeedbackBox
    var source: CropSource
}

private struct CropResults: Sendable {
    var crops: [Int: Crop] = [:]
    /// The first Jev error among the crop requests.
    var failure: JevError?
}

/// What came of the search line for one item.
private enum AnchorStatus: Sendable {
    case picked
    case noneFit
    /// No candidates, or screen text not allowed.
    case noScreenText
    /// The request failed or was skipped, or its answer was unusable.
    case notChecked

    var summary: JevSummaryValue {
        switch self {
        case .picked: "picked"
        case .noneFit: "noneFit"
        case .noScreenText: "noScreenText"
        case .notChecked: "notChecked"
        }
    }
}

private struct Anchor: Sendable {
    var status: AnchorStatus
    /// Set when picked.
    var line: AnchorLine?
}

private struct SearchResults: Sendable {
    /// For a capture with no badges.
    var capture: Anchor?
    var items: [Int: Anchor] = [:]
    /// The Jev error of the search request, if it failed.
    var failure: JevError?
}

/// The outcome of one request.
private enum Reply: Sendable {
    case answer(JevResponse)
    /// The cutoff passed, or the job was cancelled. Nothing failed.
    case skipped
    case failed(JevError)
}

extension CropsAnchorsJob {
    /// The capture's items by badge number. The first item of a number wins.
    private static func items(of capture: FeedbackCapture) -> [Item] {
        var numbers = Set<Int>()
        return FeedbackItems.split(capture).items.compactMap { item in
            guard let badge = item.badge.badge, numbers.insert(badge).inserted else { return nil }
            return Item(captureIndex: capture.index, badge: badge, seed: item.focus, note: item.badge.instruction, markText: item.ocrText)
        }
    }

    // MARK: - One request

    /// Sends one request. It is skipped, not failed, when the cutoff passed or
    /// the job was cancelled.
    private static func ask(_ request: JevRequest, context: JevJobContext, cutoff: ContinuousClock.Instant) async -> Reply {
        guard ContinuousClock.now < cutoff else { return .skipped }
        return await withTaskGroup(of: Reply.self) { group in
            group.addTask {
                do {
                    return .answer(try await context.jev.ask(request))
                } catch let error as JevError {
                    return .failed(error)
                } catch {
                    return .skipped
                }
            }
            group.addTask {
                try? await Task.sleep(until: cutoff, clock: .continuous)
                return .skipped
            }
            let first = await group.next() ?? .skipped
            group.cancelAll()
            return first
        }
    }

    // MARK: - Crops

    private static func findCrops(_ items: [Item], context: JevJobContext, cutoff: ContinuousClock.Instant) async -> CropResults {
        guard (context.optionModes[.cropsItemCrops] ?? .off) != .off else { return CropResults() }
        var results = await boxes(for: items, context: context, cutoff: cutoff)
        // A crop that costs over half the full image's tokens is not worth sending.
        for (badge, crop) in results.crops where crop.status != .tooSmall && !ItemCrop.isWorthIt(crop.box, imageSize: context.capture.size) {
            results.crops[badge]?.status = .notWorthIt
        }
        return results
    }

    /// Steps 1 to 3: the marks crop, or the target crop with its edge checks.
    private static func boxes(for items: [Item], context: JevJobContext, cutoff: ContinuousClock.Instant) async -> CropResults {
        let capture = context.capture
        let size = capture.size
        var results = CropResults()
        guard !items.isEmpty else { return results }

        func marksCrop(_ item: Item, _ status: CropStatus) -> Crop {
            Crop(box: ItemCrop.marksCrop(seed: item.seed, imageSize: size), status: status, source: .marks)
        }
        /// False past the cutoff, or when the job is cancelled. A load is a
        /// full PNG decode, so none starts then.
        func inTime() -> Bool {
            ContinuousClock.now < cutoff && !Task.isCancelled
        }
        func image(_ region: FeedbackBox) -> JevImage? {
            try? context.images.image(of: capture.index, .annotated, region: region)
        }
        func response(from reply: Reply) -> JevResponse? {
            switch reply {
            case .answer(let response): return response
            case .failed(let error):
                results.failure = results.failure ?? error
                return nil
            case .skipped: return nil
            }
        }

        guard context.allowed.contains(.images) else {
            for item in items {
                results.crops[item.badge] = marksCrop(item, .marksOnly)
            }
            return results
        }

        var windows: [Int: FeedbackBox] = [:]
        var targets: [Int: FeedbackBox] = [:]

        // Request A: find the target in a window around each item. The client
        // refuses a request with more images than `maxImages`, so an item
        // past that count keeps its marks crop, not checked.
        var shots: [(item: Item, image: JevImage)] = []
        for item in items {
            let window = ItemCrop.window(seed: item.seed, imageSize: size)
            if shots.count < JevRequestEncoder.maxImages, inTime(), let shot = image(ItemCrop.shaped(window, imageSize: size) ?? window) {
                shots.append((item, shot))
                windows[item.badge] = shot.sourceRegion
            } else {
                results.crops[item.badge] = marksCrop(item, .notChecked)
            }
        }

        var open: [OpenCrop] = []
        if !shots.isEmpty {
            let reply = await ask(targetRequest(shots), context: context, cutoff: cutoff)
            let answered = response(from: reply)
            for (item, shot) in shots {
                guard let answered else {
                    results.crops[item.badge] = marksCrop(item, .notChecked)
                    continue
                }
                // A Box with no confidence is incomplete, so it falls back to the marks crop.
                if let answer = answered.box(key("\(item.prefix).target")),
                   let shown = answered.noul(key("\(item.prefix).target_shown")),
                   shown >= targetShownThreshold,
                   (answer.confidence ?? 0) >= targetConfidenceThreshold {
                    let target = shot.sourceBox(for: answer.box)
                    targets[item.badge] = target
                    open.append(OpenCrop(item: item, box: ItemCrop.targetCrop(target: target, seed: item.seed, imageSize: size), source: .target))
                } else {
                    open.append(OpenCrop(item: item, box: ItemCrop.marksCrop(seed: item.seed, imageSize: size), source: .marks))
                }
            }
        }

        // Request B: check the edges, at most `maxEdgeChecks` times.
        for round in 1...ItemCrop.maxEdgeChecks {
            guard !open.isEmpty else { break }
            let isLastRound = round == ItemCrop.maxEdgeChecks
            var asked: [(entry: OpenCrop, image: JevImage)] = []
            for var entry in open {
                guard let shaped = ItemCrop.shaped(entry.box, imageSize: size) else {
                    results.crops[entry.item.badge] = Crop(box: entry.box, status: .tooSmall, source: entry.source)
                    continue
                }
                entry.box = shaped
                if inTime(), let shot = image(shaped) {
                    asked.append((entry, shot))
                } else {
                    results.crops[entry.item.badge] = Crop(box: shaped, status: .notChecked, source: entry.source)
                }
            }
            open = []
            guard !asked.isEmpty else { break }

            let reply = await ask(edgeRequest(asked, round: round), context: context, cutoff: cutoff)
            let answered = response(from: reply)
            for (entry, _) in asked {
                guard let answered else {
                    results.crops[entry.item.badge] = Crop(box: entry.box, status: .notChecked, source: entry.source)
                    continue
                }
                var edges: ItemCrop.Edges = []
                for (name, edge) in edgeNames {
                    if (answered.noul(key(edgeQuestionID(entry.item, name, round: round))) ?? 0) >= edgeCutThreshold {
                        edges.insert(edge)
                    }
                }
                if edges.isEmpty {
                    results.crops[entry.item.badge] = Crop(box: entry.box, status: .checked, source: entry.source)
                    continue
                }
                var moved = entry
                moved.box = ItemCrop.expanded(entry.box, edges: edges, imageSize: size)
                // Every named edge is already at the image border: there is nothing more to show.
                if moved.box == entry.box {
                    results.crops[entry.item.badge] = Crop(box: entry.box, status: .checked, source: entry.source)
                    continue
                }
                if isLastRound {
                    moved.box = ItemCrop.shaped(moved.box, imageSize: size) ?? moved.box
                    results.crops[entry.item.badge] = Crop(box: moved.box, status: .edgesUnsure, source: entry.source)
                } else {
                    open.append(moved)
                }
            }
        }

        for (badge, window) in windows {
            results.crops[badge]?.window = window
        }
        for (badge, target) in targets {
            results.crops[badge]?.target = target
        }
        return results
    }

    private static func targetRequest(_ shots: [(item: Item, image: JevImage)]) -> JevRequest {
        var state: [(JevCodeText, JevValue)] = []
        var questions: [(id: JevCodeText, question: JevQuestion)] = []
        for (item, image) in shots {
            let n = item.badge
            state.append(("shot_\(n)", .image(image)))
            state.append(("note_\(n)", item.noteValue(missing: noNoteForCrop(n))))
            questions.append(("\(item.prefix).target", .box(.code("the part of `shot_\(n)` that `note_\(n)` is about. The numbered badge \(n) marks it."))))
            questions.append(("\(item.prefix).target_shown", .noul(.code("Does `shot_\(n)` show the thing that `note_\(n)` is about?"))))
        }
        return JevRequest(state: .object(state), questions: questions)
    }

    private static func edgeRequest(_ asked: [(entry: OpenCrop, image: JevImage)], round: Int) -> JevRequest {
        var state: [(JevCodeText, JevValue)] = []
        var questions: [(id: JevCodeText, question: JevQuestion)] = []
        for (entry, image) in asked {
            let n = entry.item.badge
            state.append(("crop_\(n)", .image(image)))
            state.append(("note_\(n)", entry.item.noteValue(missing: noNoteForCrop(n))))
            for (name, _) in edgeNames {
                questions.append((
                    edgeQuestionID(entry.item, name, round: round),
                    .noul(.code("Does the thing that `note_\(n)` is about continue past the \(name) edge of `crop_\(n)`?"))
                ))
            }
        }
        return JevRequest(state: .object(state), questions: questions)
    }

    private static let edgeNames: [(name: JevCodeText, edge: ItemCrop.Edges)] = [
        ("left", .left), ("right", .right), ("top", .top), ("bottom", .bottom),
    ]

    /// `K.N.cut_left` in the first check, `K.N.cut_left_2` in the second.
    private static func edgeQuestionID(_ item: Item, _ name: JevCodeText, round: Int) -> JevCodeText {
        round == 1 ? "\(item.prefix).cut_\(name)" : "\(item.prefix).cut_\(name)_\(round)"
    }

    /// The key of an answer in a response, which names it by plain text.
    private static func key(_ id: JevCodeText) -> String {
        id.text
    }

    private static func noNoteForCrop(_ badge: Int) -> JevCodeText {
        "No note. Use the element that badge \(badge) sits on or points to."
    }

    // MARK: - Search lines

    private static func findSearchLines(_ items: [Item], context: JevJobContext, cutoff: ContinuousClock.Instant) async -> SearchResults {
        var found = SearchResults()
        guard (context.optionModes[.cropsSearchLines] ?? .off) != .off, context.allowed.contains(.screenText) else { return found }
        let capture = context.capture
        let set = AnchorCandidates.build(capture: capture, lines: context.screenLines)
        guard !set.lines.isEmpty else { return found }

        // Each line is offered as `line_N`, N from 1 in `set.lines`. The model
        // reads the text through the same label in `screen_text`.
        var positions: [String: Int] = [:]
        var optionLines: [String: AnchorLine] = [:]
        for (offset, line) in set.lines.enumerated() {
            positions[line.id] = offset + 1
            let name: JevCodeText = "line_\(offset + 1)"
            optionLines[name.text] = line
        }
        func options(_ ids: [String]) -> [(name: JevCodeText, description: JevValue)] {
            ids.compactMap { id in
                guard let number = positions[id] else { return nil }
                let name: JevCodeText = "line_\(number)"
                return (name: name, description: JevValue.code("The line with this id in screen_text."))
            }
        }

        var itemFields: [(JevCodeText, JevValue)] = []
        var questions: [(id: JevCodeText, question: JevQuestion)] = []
        var asked: [(prefix: JevCodeText, badge: Int?, ids: [String])] = []
        for item in items {
            guard let ids = set.itemCandidates[item.badge], !ids.isEmpty else { continue }
            var fields: [(JevCodeText, JevValue)] = [("note", item.noteValue(missing: "No note."))]
            if let markText = item.markText {
                fields.append(("screen_text", .screen(markText)))
            }
            itemFields.append(("item_\(item.badge)", .object(fields)))
            questions += anchorQuestions(
                prefix: item.prefix,
                options: options(ids),
                target: "item \(item.badge)",
                reads: "`items.item_\(item.badge).note` is the reviewer's note, and `items.item_\(item.badge).screen_text` is the screen text under its marks."
            )
            asked.append((item.prefix, item.badge, ids))
        }

        var state: [(JevCodeText, JevValue)] = [
            ("screen_text", .array(set.lines.enumerated().map { .screen("line_\($0.offset + 1)| \($0.element.text)") })),
        ]
        if !itemFields.isEmpty {
            state.append(("items", .object(itemFields)))
        }
        if let ids = set.captureCandidates, !ids.isEmpty, let note = capture.note {
            state.append(("general_note", .reviewer(note)))
            let prefix: JevCodeText = "\(capture.index)"
            questions += anchorQuestions(
                prefix: prefix,
                options: options(ids),
                target: "the thing that `general_note` is about",
                reads: "`general_note` is the reviewer's note."
            )
            asked.append((prefix, nil, ids))
        }

        // The candidates exist, so each asked item or capture has a status from here on.
        func record(_ anchor: Anchor, for entry: (prefix: JevCodeText, badge: Int?, ids: [String])) {
            if let badge = entry.badge {
                found.items[badge] = anchor
            } else {
                found.capture = anchor
            }
        }
        for entry in asked {
            record(Anchor(status: .notChecked), for: entry)
        }
        guard !questions.isEmpty else { return found }

        let reply = await ask(JevRequest(state: .object(state), questions: questions), context: context, cutoff: cutoff)
        let response: JevResponse
        switch reply {
        case .answer(let answered): response = answered
        case .failed(let error):
            found.failure = error
            return found
        case .skipped: return found
        }

        for entry in asked {
            guard let choice = response.choice(key("\(entry.prefix).anchor")),
                  let fits = response.noul(key("\(entry.prefix).anchor_fits"))
            else { continue }
            let pick = AnchorCandidates.pick(
                choice: optionLines[choice.option]?.id,
                offered: entry.ids,
                fits: fits,
                confidence: choice.confidence,
                fitsThreshold: anchorFitsThreshold,
                confidenceThreshold: anchorConfidenceThreshold,
                lines: set.lines
            )
            switch pick {
            case .picked(let id, _):
                record(Anchor(status: .picked, line: set.lines.first { $0.id == id }), for: entry)
            case .noneFit:
                record(Anchor(status: .noneFit), for: entry)
            case .invalid:
                break
            }
        }
        return found
    }

    /// The Choice and the Noul for one item, or for the whole capture.
    /// `target` finishes "to find the code for ..." and "names ...".
    private static func anchorQuestions(
        prefix: JevCodeText,
        options: [(name: JevCodeText, description: JevValue)],
        target: JevCodeText,
        reads: JevCodeText
    ) -> [(id: JevCodeText, question: JevQuestion)] {
        let choice = JevQuestion(
            instructions: .code(
                "\(JevPrompting.screenTextNotice) Which line in `screen_text` is the best text to search the app's source code for, to find the code for \(target)? \(reads) Prefer fixed interface text: labels, titles, button and menu names. Avoid counts, dates, user data, file contents, and window titles."
            ),
            kind: .choice(options: options)
        )
        let fits = JevQuestion.noul(.code(
            "\(JevPrompting.screenTextNotice) Is one of the lines in `screen_text` fixed interface text that names \(target), as the app's code would spell it?"
        ))
        return [("\(prefix).anchor", choice), ("\(prefix).anchor_fits", fits)]
    }

    // MARK: - Output

    private static func output(
        items: [Item],
        crops: [Int: Crop],
        search: SearchResults,
        pngs: (annotated: CGImage?, clean: CGImage?),
        context: JevJobContext,
        outputMargin: Duration
    ) -> JevJobOutput {
        let capture = context.capture
        var files: [JevRefinedFile] = []
        var cropLines: [Int: [JevRefinedLine]] = [:]
        // A part in shadow records its answers and summary. Only a part in
        // on writes files and lines.
        let writesCrops = context.optionModes[.cropsItemCrops] == .on
        let writesSearch = context.optionModes[.cropsSearchLines] == .on

        // A PNG that is missing or has another size gives no crops.
        let wanted = items.filter { crops[$0.badge]?.status.words != nil }
        if writesCrops, !wanted.isEmpty, let annotated = pngs.annotated, let clean = pngs.clean {
            let stopAt = context.deadline - outputMargin
            for item in wanted {
                // The runner drops all output at the deadline. Later items get no crop.
                guard ContinuousClock.now < stopAt, !Task.isCancelled else { break }
                guard let crop = crops[item.badge], let words = crop.status.words,
                      let annotatedData = pngData(annotated, box: crop.box),
                      let cleanData = pngData(clean, box: crop.box)
                else { continue }
                let names = ItemCrop.fileNames(imageFile: capture.imageFile, badge: item.badge)
                let box = crop.box
                files.append(JevRefinedFile(name: names.annotated, data: annotatedData))
                files.append(JevRefinedFile(name: names.clean, data: cleanData))
                cropLines[item.badge] = [
                    JevRefinedLine(
                        scope: .item(badge: item.badge),
                        label: "Crop of this item (\(words); px \(box.x1) \(box.y1) \(box.x2) \(box.y2) of the full image):",
                        file: names.annotated
                    ),
                    JevRefinedLine(scope: .item(badge: item.badge), label: "The same crop without marks:", file: names.clean),
                ]
            }
        }

        var lines: [JevRefinedLine] = []
        if !files.isEmpty {
            lines.append(JevRefinedLine(
                scope: .capture,
                label: "Open each item's crop before the full image. Open the full image only for layout, or when a crop line says unsure or not checked."
            ))
        }
        if writesSearch, let capturePick = search.capture, capturePick.status == .picked, let text = capturePick.line?.text {
            lines.append(JevRefinedLine(scope: .capture, label: "Search the repository for this screen text (whole capture):", screenText: text))
        }
        for item in items {
            if writesSearch, let pick = search.items[item.badge], pick.status == .picked, let text = pick.line?.text {
                lines.append(JevRefinedLine(scope: .item(badge: item.badge), label: "Search the repository for this screen text:", screenText: text))
            }
            lines += cropLines[item.badge] ?? []
        }
        return JevJobOutput(lines: lines, files: files)
    }

    // MARK: - Summary

    /// What jev.json records for the review script: one object per item, or
    /// one for the whole capture when it has no badges. Numbers and code
    /// text only. Boxes are `[x1, y1, x2, y2]` in capture pixels. A part
    /// whose sub-flag is off adds no field.
    private static func summary(
        items: [Item],
        crops: [Int: Crop],
        search: SearchResults,
        captureIndex: Int,
        withCrops: Bool,
        withSearch: Bool
    ) -> [JevSummaryField] {
        func numbers(_ box: FeedbackBox) -> JevSummaryValue {
            .numbers([box.x1, box.y1, box.x2, box.y2])
        }
        func anchorFields(_ anchor: Anchor?) -> [JevSummaryField] {
            guard withSearch else { return [] }
            var fields = [JevSummaryField(key: "anchorStatus", value: (anchor?.status ?? .noScreenText).summary)]
            if anchor?.status == .picked, let line = anchor?.line {
                fields.append(JevSummaryField(key: "anchorSource", value: .number(Double(line.source))))
                if let box = line.box {
                    fields.append(JevSummaryField(key: "anchorBox", value: numbers(box)))
                }
            }
            return fields
        }

        var objects: [JevSummaryValue] = []
        for item in items {
            var fields = [JevSummaryField(key: "item", value: "\(item.prefix)")]
            if withCrops, let crop = crops[item.badge] {
                fields.append(JevSummaryField(key: "cropStatus", value: crop.status.summary))
                fields.append(JevSummaryField(key: "cropSource", value: crop.source.summary))
                fields.append(JevSummaryField(key: "crop", value: numbers(crop.box)))
                if let window = crop.window {
                    fields.append(JevSummaryField(key: "window", value: numbers(window)))
                }
                if let target = crop.target {
                    fields.append(JevSummaryField(key: "target", value: numbers(target)))
                }
            }
            objects.append(.object(fields + anchorFields(search.items[item.badge])))
        }
        // A capture with no badges has a search line only.
        if items.isEmpty, withSearch {
            objects.append(.object([JevSummaryField(key: "item", value: "\(captureIndex)")] + anchorFields(search.capture)))
        }
        return objects.isEmpty ? [] : [JevSummaryField(key: "items", value: .array(objects))]
    }

    /// A capture PNG from the bundle folder, decoded now. Nil when there are no
    /// items, or when the file is unreadable or not the stored size.
    private static func decode(_ file: String, ifAny items: [Item], context: JevJobContext) -> CGImage? {
        guard !items.isEmpty else { return nil }
        let url = context.folderURL.appendingPathComponent(file)
        let size = context.capture.size
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options),
              image.width == size.width, image.height == size.height
        else { return nil }
        return image
    }

    /// The box cut out of `image` at its own pixels, as PNG data.
    private static func pngData(_ image: CGImage, box: FeedbackBox) -> Data? {
        let width = box.x2 - box.x1
        let height = box.y2 - box.y1
        guard width > 0, height > 0,
              let cropped = image.cropping(to: CGRect(x: box.x1, y: box.y1, width: width, height: height)),
              cropped.width == width, cropped.height == height
        else { return nil }
        return JevImagePreparation.pngData(cropped)
    }
}
