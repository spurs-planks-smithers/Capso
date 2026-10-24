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
public struct CropsAnchorsJob: JevJob {
    public let id = "cropsAnchors"
    public let flag = FeatureFlag.cropsAnchors
    /// Crops around the marks and notes need no consent beyond reviewer text.
    public let requires: JevDataKinds = []
    public let version = 1

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
    static let requestMargin: Duration = .milliseconds(500)
    /// The crop PNGs are cut one item at a time. None starts this close to the deadline.
    static let outputMargin: Duration = .milliseconds(100)

    public init() {}

    public func run(_ context: JevJobContext) async throws -> JevJobOutput {
        let items = Self.items(of: context.capture)
        let cutoff = context.deadline - Self.requestMargin
        // The PNGs decode while the requests are in flight.
        async let annotated = Self.decode(context.capture.imageFile, ifAny: items, context: context)
        async let clean = Self.decode(context.capture.cleanImageFile, ifAny: items, context: context)
        async let crops = Self.findCrops(items, context: context, cutoff: cutoff)
        async let search = Self.findSearchLines(items, context: context, cutoff: cutoff)
        let (foundCrops, foundSearch, pngs) = await (crops, search, (annotated, clean))
        return Self.output(items: items, crops: foundCrops, search: foundSearch, pngs: pngs, context: context)
    }
}

// MARK: - Items and results

/// One numbered badge of the capture, with what the job needs about it.
private struct Item: Sendable {
    var badge: Int
    /// The item id prefix, K.N, for question ids.
    var prefix: String
    /// The badge, its shape, and its arrow tip.
    var seed: FeedbackBox
    /// Drew's words for this badge. Nil when he wrote none.
    var note: String?
    /// The screen text under the item's marks. Nil when there is none.
    var markText: String?

    /// Drew's note, or code text that says what to use in its place.
    func noteValue(missing: String) -> JevValue {
        note.map(JevValue.reviewer) ?? .code(missing)
    }
}

/// How far a crop was checked. The raw values are for a later jev.json summary.
private enum CropStatus: String, Sendable {
    case checked
    case edgesUnsure
    case marksOnly
    case notChecked
    case tooSmall
    case notWorthIt

    /// The words in the crop label. Nil when the item gets no crop lines.
    var words: String? {
        switch self {
        case .checked: "edges checked"
        case .edgesUnsure: "edges unsure: open the full image if the crop cuts something off"
        case .marksOnly: "cut around the marks, not checked"
        case .notChecked: "not checked: open the full image if the crop cuts something off"
        case .tooSmall, .notWorthIt: nil
        }
    }
}

/// Where a crop's box came from.
private enum CropSource: String, Sendable {
    /// Jev's Box for the target.
    case target
    /// The seed box plus a pad.
    case marks
}

private struct Crop: Sendable {
    var box: FeedbackBox
    var status: CropStatus
    var source: CropSource
}

/// A crop that still needs an edge check.
private struct OpenCrop: Sendable {
    var item: Item
    var box: FeedbackBox
    var source: CropSource
}

private struct SearchLines: Sendable {
    /// For a capture with no badges.
    var capture: String?
    var items: [Int: String] = [:]
}

extension CropsAnchorsJob {
    /// The capture's items by badge number. The first item of a number wins.
    private static func items(of capture: FeedbackCapture) -> [Item] {
        var numbers = Set<Int>()
        return FeedbackItems.split(capture).items.compactMap { item in
            guard let badge = item.badge.badge, numbers.insert(badge).inserted else { return nil }
            return Item(badge: badge, prefix: item.id, seed: item.focus, note: item.badge.instruction, markText: item.ocrText)
        }
    }

    // MARK: - One request

    /// Sends one request, or nil. Nil means the cutoff passed, the request
    /// failed, or the job was cancelled.
    private static func ask(_ request: JevRequest, context: JevJobContext, cutoff: ContinuousClock.Instant) async -> JevResponse? {
        guard ContinuousClock.now < cutoff else { return nil }
        return await withTaskGroup(of: JevResponse?.self) { group in
            group.addTask {
                try? await context.jev.ask(request)
            }
            group.addTask {
                try? await Task.sleep(until: cutoff, clock: .continuous)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Crops

    private static func findCrops(_ items: [Item], context: JevJobContext, cutoff: ContinuousClock.Instant) async -> [Int: Crop] {
        var crops = await boxes(for: items, context: context, cutoff: cutoff)
        // A crop that costs over half the full image's tokens is not worth sending.
        for (badge, crop) in crops where crop.status != .tooSmall && !ItemCrop.isWorthIt(crop.box, imageSize: context.capture.size) {
            crops[badge]?.status = .notWorthIt
        }
        return crops
    }

    /// Steps 1 to 3: the marks crop, or the target crop with its edge checks.
    private static func boxes(for items: [Item], context: JevJobContext, cutoff: ContinuousClock.Instant) async -> [Int: Crop] {
        let capture = context.capture
        let size = capture.size
        var crops: [Int: Crop] = [:]
        guard !items.isEmpty else { return crops }

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

        guard context.allowed.contains(.images) else {
            for item in items {
                crops[item.badge] = marksCrop(item, .marksOnly)
            }
            return crops
        }

        // Request A: find the target in a window around each item. The client
        // refuses a request with more images than `maxImages`, so an item
        // past that count keeps its marks crop, not checked.
        var shots: [(item: Item, image: JevImage)] = []
        for item in items {
            let window = ItemCrop.window(seed: item.seed, imageSize: size)
            if shots.count < JevRequestEncoder.maxImages, inTime(), let shot = image(ItemCrop.shaped(window, imageSize: size) ?? window) {
                shots.append((item, shot))
            } else {
                crops[item.badge] = marksCrop(item, .notChecked)
            }
        }

        var open: [OpenCrop] = []
        if !shots.isEmpty {
            let response = await ask(targetRequest(shots), context: context, cutoff: cutoff)
            for (item, shot) in shots {
                guard let response else {
                    crops[item.badge] = marksCrop(item, .notChecked)
                    continue
                }
                // A Box with no confidence is incomplete, so it falls back to the marks crop.
                if let answer = response.box("\(item.prefix).target"),
                   let shown = response.noul("\(item.prefix).target_shown"),
                   shown >= targetShownThreshold,
                   (answer.confidence ?? 0) >= targetConfidenceThreshold {
                    let target = shot.sourceBox(for: answer.box)
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
                    crops[entry.item.badge] = Crop(box: entry.box, status: .tooSmall, source: entry.source)
                    continue
                }
                entry.box = shaped
                if inTime(), let shot = image(shaped) {
                    asked.append((entry, shot))
                } else {
                    crops[entry.item.badge] = Crop(box: shaped, status: .notChecked, source: entry.source)
                }
            }
            open = []
            guard !asked.isEmpty else { break }

            let response = await ask(edgeRequest(asked, round: round), context: context, cutoff: cutoff)
            for (entry, _) in asked {
                guard let response else {
                    crops[entry.item.badge] = Crop(box: entry.box, status: .notChecked, source: entry.source)
                    continue
                }
                var edges: ItemCrop.Edges = []
                for (name, edge) in edgeNames {
                    if (response.noul(edgeQuestionID(entry.item, name, round: round)) ?? 0) >= edgeCutThreshold {
                        edges.insert(edge)
                    }
                }
                if edges.isEmpty {
                    crops[entry.item.badge] = Crop(box: entry.box, status: .checked, source: entry.source)
                    continue
                }
                var moved = entry
                moved.box = ItemCrop.expanded(entry.box, edges: edges, imageSize: size)
                // Every named edge is already at the image border: there is nothing more to show.
                if moved.box == entry.box {
                    crops[entry.item.badge] = Crop(box: entry.box, status: .checked, source: entry.source)
                    continue
                }
                if isLastRound {
                    moved.box = ItemCrop.shaped(moved.box, imageSize: size) ?? moved.box
                    crops[entry.item.badge] = Crop(box: moved.box, status: .edgesUnsure, source: entry.source)
                } else {
                    open.append(moved)
                }
            }
        }
        return crops
    }

    private static func targetRequest(_ shots: [(item: Item, image: JevImage)]) -> JevRequest {
        var state: [(String, JevValue)] = []
        var questions: [(id: String, question: JevQuestion)] = []
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
        var state: [(String, JevValue)] = []
        var questions: [(id: String, question: JevQuestion)] = []
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

    private static let edgeNames: [(name: String, edge: ItemCrop.Edges)] = [
        ("left", .left), ("right", .right), ("top", .top), ("bottom", .bottom),
    ]

    /// `K.N.cut_left` in the first check, `K.N.cut_left_2` in the second.
    private static func edgeQuestionID(_ item: Item, _ name: String, round: Int) -> String {
        "\(item.prefix).cut_\(name)" + (round == 1 ? "" : "_\(round)")
    }

    private static func noNoteForCrop(_ badge: Int) -> String {
        "No note. Use the element that badge \(badge) sits on or points to."
    }

    // MARK: - Search lines

    private static func findSearchLines(_ items: [Item], context: JevJobContext, cutoff: ContinuousClock.Instant) async -> SearchLines {
        var found = SearchLines()
        guard context.allowed.contains(.screenText) else { return found }
        let capture = context.capture
        let set = AnchorCandidates.build(capture: capture, lines: nil)
        guard !set.lines.isEmpty else { return found }

        var itemFields: [(String, JevValue)] = []
        var questions: [(id: String, question: JevQuestion)] = []
        var asked: [(prefix: String, badge: Int?, ids: [String])] = []
        for item in items {
            guard let ids = set.itemCandidates[item.badge], !ids.isEmpty else { continue }
            var fields: [(String, JevValue)] = [("note", item.noteValue(missing: "No note."))]
            if let markText = item.markText {
                fields.append(("screen_text", .screen(markText)))
            }
            itemFields.append(("item_\(item.badge)", .object(fields)))
            questions += anchorQuestions(
                prefix: item.prefix,
                ids: ids,
                target: "item \(item.badge)",
                reads: "`items.item_\(item.badge).note` is the reviewer's note, and `items.item_\(item.badge).screen_text` is the screen text under its marks."
            )
            asked.append((item.prefix, item.badge, ids))
        }

        var state: [(String, JevValue)] = [("screen_text", .array(set.lines.map { .screen("\($0.id)| \($0.text)") }))]
        if !itemFields.isEmpty {
            state.append(("items", .object(itemFields)))
        }
        if let ids = set.captureCandidates, !ids.isEmpty, let note = capture.note {
            state.append(("general_note", .reviewer(note)))
            let prefix = "\(capture.index)"
            questions += anchorQuestions(
                prefix: prefix,
                ids: ids,
                target: "the thing that `general_note` is about",
                reads: "`general_note` is the reviewer's note."
            )
            asked.append((prefix, nil, ids))
        }

        guard !questions.isEmpty,
              let response = await ask(JevRequest(state: .object(state), questions: questions), context: context, cutoff: cutoff)
        else { return found }

        for entry in asked {
            guard let choice = response.choice("\(entry.prefix).anchor"),
                  let fits = response.noul("\(entry.prefix).anchor_fits")
            else { continue }
            let pick = AnchorCandidates.pick(
                choice: choice.option,
                offered: entry.ids,
                fits: fits,
                confidence: choice.confidence,
                fitsThreshold: anchorFitsThreshold,
                confidenceThreshold: anchorConfidenceThreshold,
                lines: set.lines
            )
            guard case .picked(_, let text) = pick else { continue }
            if let badge = entry.badge {
                found.items[badge] = text
            } else {
                found.capture = text
            }
        }
        return found
    }

    /// The Choice and the Noul for one item, or for the whole capture.
    /// `target` finishes "to find the code for ..." and "names ...".
    private static func anchorQuestions(prefix: String, ids: [String], target: String, reads: String) -> [(id: String, question: JevQuestion)] {
        let choice = JevQuestion(
            instructions: .code(
                JevPrompting.screenTextNotice
                    + " Which line in `screen_text` is the best text to search the app's source code for, to find the code for \(target)? \(reads)"
                    + " Prefer fixed interface text: labels, titles, button and menu names. Avoid counts, dates, user data, file contents, and window titles."
            ),
            kind: .choice(options: ids.map { (name: $0, description: JevValue.code("The line with this id in screen_text.")) })
        )
        let fits = JevQuestion.noul(.code(
            JevPrompting.screenTextNotice
                + " Is one of the lines in `screen_text` fixed interface text that names \(target), as the app's code would spell it?"
        ))
        return [("\(prefix).anchor", choice), ("\(prefix).anchor_fits", fits)]
    }

    // MARK: - Output

    private static func output(
        items: [Item],
        crops: [Int: Crop],
        search: SearchLines,
        pngs: (annotated: CGImage?, clean: CGImage?),
        context: JevJobContext
    ) -> JevJobOutput {
        let capture = context.capture
        var files: [JevRefinedFile] = []
        var cropLines: [Int: [JevRefinedLine]] = [:]

        // A PNG that is missing or has another size gives no crops.
        let wanted = items.filter { crops[$0.badge]?.status.words != nil }
        if !wanted.isEmpty, let annotated = pngs.annotated, let clean = pngs.clean {
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
        if let text = search.capture {
            lines.append(JevRefinedLine(scope: .capture, label: "Search the repository for this screen text (whole capture):", screenText: text))
        }
        for item in items {
            if let text = search.items[item.badge] {
                lines.append(JevRefinedLine(scope: .item(badge: item.badge), label: "Search the repository for this screen text:", screenText: text))
            }
            lines += cropLines[item.badge] ?? []
        }
        return JevJobOutput(lines: lines, files: files)
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
