// Packages/JevKit/Tests/JevKitTests/CropsAnchorsJobTests.swift
import CoreGraphics
import FeedbackKit
import Foundation
import ImageIO
import Synchronization
import Testing
@testable import JevKit

// MARK: - Fixtures

/// One numbered badge for a crops test.
struct CropsMark {
    var number: Int
    var box: FeedbackBox
    var note: String? = "make it brighter"
    var text: String?
}

let cropsOCR = """
Copy Last Capture Prompt
Copy Prompt and End Round
Open Round Folder
End Round
"""

/// A badge in the middle of a 1000 by 800 capture, so no crop touches an edge.
let centerBadge = FeedbackBox(x1: 480, y1: 380, x2: 510, y2: 410)
let cornerBadge = FeedbackBox(x1: 150, y1: 600, x2: 180, y2: 630)

/// The crop of `centerBadge` in the default fixture: the seed plus 120 pixels. The default
/// Box answer gives a smaller target crop, and a target crop is never smaller than the
/// marks crop (Drew, 2026-10-24), so this is also the crop after Jev's target.
let defaultCrop = FeedbackBox(x1: 360, y1: 260, x2: 630, y2: 530)

/// A Box over most of the 430 pixel window around `centerBadge`. Its target crop is far larger
/// than the marks crop, so a crop that came from it cannot pass for the marks crop.
let wideBox = JevBox(top: 0.05, bottom: 0.95, left: 0.05, right: 0.95)

/// `shapes` are rectangles. A rectangle that touches a badge widens that item's seed box.
func cropsCapture(
    size: PixelSize = PixelSize(width: 1000, height: 800),
    marks: [CropsMark] = [CropsMark(number: 1, box: centerBadge)],
    shapes: [FeedbackBox] = [],
    note: String? = "general note",
    ocr: String? = cropsOCR,
    sourceApp: String = "Yak Application 4410",
    windowTitle: String = "Wombat Window Title 7731"
) -> FeedbackCapture {
    FeedbackCapture(
        index: 1,
        imageFile: "1028-claude.png",
        cleanImageFile: "1028-claude-clean.png",
        size: size,
        capturedAt: Date(timeIntervalSince1970: 1_792_000_000),
        sourceApp: sourceApp,
        windowTitle: windowTitle,
        note: note,
        ocrText: ocr,
        marks: marks.map { FeedbackMark(kind: .counter, badge: $0.number, box: $0.box, ocrText: $0.text, instruction: $0.note) }
            + shapes.map { FeedbackMark(kind: .rectangle, box: $0) }
    )
}

/// Answers every question of a request by its kind. A Noul answer comes from
/// `noul`, by the full id or by the id without its "K.N." prefix (for example
/// "cut_left_2"), and is 0.1 when the key is missing.
struct CropsScript: Sendable {
    var noul: [String: Double] = [:]
    var box = JevBoxAnswer(box: JevBox(top: 0.25, bottom: 0.75, left: 0.25, right: 0.75), confidence: 0.9)
    /// The option a Choice picks, by full id or short id. The default is the first option.
    var choice: [String: String] = [:]
    var choiceConfidence = 0.9
    /// Makes every request throw this error.
    var failure: JevError?
    /// Makes a request that holds screen text throw this error, when `failure` is nil.
    var failureOnText: JevError?
    /// Makes a request that holds an image throw this error, when `failure` is nil.
    var failureOnImages: JevError?
    /// Makes every request wait this long before it answers.
    var delay: Duration?

    static func shortID(_ id: String) -> String {
        id.split(separator: ".").drop(while: { $0.allSatisfy(\.isNumber) }).joined(separator: ".")
    }

    func answer(_ request: JevRequest) -> JevResponse {
        var answers: [String: JevAnswer] = [:]
        for (id, question) in request.questions {
            let key = id.text
            let short = Self.shortID(key)
            switch question.kind {
            case .noul:
                answers[key] = .noul(noul[key] ?? noul[short] ?? 0.1)
            case .box:
                answers[key] = .box(box)
            case .choice(let options):
                let names = options.map(\.name.text)
                let picked = (choice[key] ?? choice[short]).flatMap { names.contains($0) ? $0 : nil } ?? names[0]
                let share = 1.0 / Double(names.count)
                answers[key] = .choice(JevChoiceAnswer(
                    option: picked,
                    confidence: choiceConfidence,
                    probabilities: Dictionary(uniqueKeysWithValues: names.map { ($0, share) })
                ))
            case .score:
                answers[key] = .score(JevScoreAnswer(score: 0, confidence: 0.9, probabilities: [1]))
            }
        }
        return JevResponse(model: JevEndpoint.model, answers: answers, inputTokens: 10, outputTokens: 1)
    }
}

/// Counts calls from any thread.
final class CropsCounter: Sendable {
    private let value = Mutex(0)

    /// Adds one and returns the new count.
    @discardableResult
    func next() -> Int {
        value.withLock { count in
            count += 1
            return count
        }
    }

    var count: Int { value.withLock { $0 } }
}

struct CropsRun {
    var output: JevJobOutput
    var requests: [JevRequest]
    var round: FeedbackRound
    /// How many times the job asked the image loader for a region.
    var loads: Int
    var deadline: ContinuousClock.Instant
    /// When `run` returned.
    var finishedAt: ContinuousClock.Instant

    /// Fails the test, instead of trapping, when the request was not sent.
    func request(_ index: Int) throws -> JevRequest {
        try #require(requests.indices.contains(index) ? requests[index] : nil, "request \(index) was not sent")
    }
}

/// A PNG of one color with the boxes (origin top-left) in another color.
func paintedPNG(size: PixelSize, background: [CGFloat], boxes: [FeedbackBox], boxColor: [CGFloat]) -> Data? {
    guard let context = CGContext(
        data: nil,
        width: size.width,
        height: size.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    context.setFillColor(red: background[0], green: background[1], blue: background[2], alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
    context.setFillColor(red: boxColor[0], green: boxColor[1], blue: boxColor[2], alpha: 1)
    for box in boxes {
        // CoreGraphics puts the origin at the bottom left.
        context.fill(CGRect(x: box.x1, y: size.height - box.y2, width: box.x2 - box.x1, height: box.y2 - box.y1))
    }
    return context.makeImage().flatMap { JevImagePreparation.pngData($0) }
}

/// The colors (red, green, blue) at the four corners and the center of a PNG.
func samplePixels(_ data: Data) -> [[Int]] {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(
              data: nil,
              width: image.width,
              height: image.height,
              bitsPerComponent: 8,
              bytesPerRow: image.width * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          ),
          let memory = context.data
    else { return [] }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = memory.assumingMemoryBound(to: UInt8.self)
    let points = [(0, 0), (image.width - 1, 0), (0, image.height - 1), (image.width - 1, image.height - 1), (image.width / 2, image.height / 2)]
    return points.map { x, y in
        let offset = y * image.width * 4 + x * 4
        return [Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])]
    }
}

/// True when every sampled color is within 40 of `color` on each channel.
func allPixels(_ data: Data, near color: [Int]) -> Bool {
    let samples = samplePixels(data)
    return samples.count == 5 && samples.allSatisfy { sample in zip(sample, color).allSatisfy { abs($0 - $1) <= 40 } }
}

/// Runs the real job on real PNGs in a fresh folder, with a scripted asker.
/// Every output must pass the writer's check, so every test covers it.
func runCropsJob(
    _ capture: FeedbackCapture,
    allowed: JevDataKinds,
    script: CropsScript = CropsScript(),
    budget: Duration = .seconds(5),
    pngSize: PixelSize? = nil,
    highlights: [FeedbackBox] = [],
    screenLines: [FeedbackTextLine]? = nil,
    optionModes: [FeatureFlag: FlagState] = cropsAllOn,
    loadHook: (@Sendable (Int) throws -> Void)? = nil
) async throws -> CropsRun {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("jev-crops-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let size = pngSize ?? capture.size
    // The annotated PNG is red with green boxes. The clean PNG is blue with white boxes.
    let annotated = try #require(paintedPNG(size: size, background: [1, 0, 0], boxes: highlights, boxColor: [0, 1, 0]))
    let clean = try #require(paintedPNG(size: size, background: [0, 0, 1], boxes: highlights, boxColor: [1, 1, 1]))
    try annotated.write(to: folder.appendingPathComponent(capture.imageFile))
    try clean.write(to: folder.appendingPathComponent(capture.cleanImageFile))

    let round = FeedbackRound(
        name: "feedback",
        slug: "feedback",
        folderName: folder.lastPathComponent,
        startedAt: Date(timeIntervalSince1970: 1_792_000_000),
        captures: [capture]
    )
    let log = RequestLog()
    let loads = CropsCounter()
    let bundleLoader = JevImageLoader.bundle(folderURL: folder, round: round)
    // The deadline starts here, after the PNGs are written.
    let deadline = ContinuousClock.now + budget
    let context = JevJobContext(
        round: round,
        capture: capture,
        folderURL: folder,
        allowed: allowed,
        deadline: deadline,
        jev: JevAsker { request in
            await log.append(request)
            if let delay = script.delay {
                try await Task.sleep(for: delay)
            }
            if let failure = script.failure { throw failure }
            if let failure = script.failureOnText, request.kinds.contains(.screenText) { throw failure }
            if let failure = script.failureOnImages, request.kinds.contains(.images) { throw failure }
            return script.answer(request)
        },
        images: JevImageLoader { index, variant, region in
            let call = loads.next()
            try loadHook?(call)
            return try bundleLoader.image(of: index, variant, region: region)
        },
        screenLines: screenLines,
        optionModes: optionModes
    )
    let output = try await CropsAnchorsJob().run(context)
    let finishedAt = ContinuousClock.now
    try JevBundleWriter.check(output, for: capture, in: round)
    // The client's own checks: ids, option counts, image count and sizes.
    let requests = await log.requests
    for request in requests {
        _ = try JevRequestEncoder.encode(request)
    }
    return CropsRun(output: output, requests: requests, round: round, loads: loads.count, deadline: deadline, finishedAt: finishedAt)
}

/// Both sub-flags on, as a trial with `feature cropsAnchors on` runs the job.
let cropsAllOn: [FeatureFlag: FlagState] = [.cropsItemCrops: .on, .cropsSearchLines: .on]

let cropsRuleLine = JevRefinedLine(
    scope: .capture,
    label: "Open each item's crop before the full image. Open the full image only for layout, or when a crop line says unsure or not checked."
)

func cropLine(_ badge: Int, _ words: JevCodeText, _ box: FeedbackBox, file: String) -> JevRefinedLine {
    JevRefinedLine(
        scope: .item(badge: badge),
        label: "Crop of this item (\(words); px \(box.x1) \(box.y1) \(box.x2) \(box.y2) of the full image):",
        file: file
    )
}

func cleanLine(_ badge: Int, file: String) -> JevRefinedLine {
    JevRefinedLine(scope: .item(badge: badge), label: "The same crop without marks:", file: file)
}

func searchLine(_ badge: Int, _ text: String) -> JevRefinedLine {
    JevRefinedLine(scope: .item(badge: badge), label: "Search the repository for this screen text:", screenText: text)
}

/// The "px x1 y1 x2 y2" box in a crop label.
func cropPixelBox(_ label: String) -> FeedbackBox? {
    guard let range = label.range(of: "px ") else { return nil }
    let numbers = label[range.upperBound...].split(separator: " ").prefix(4).compactMap { Int($0) }
    guard numbers.count == 4 else { return nil }
    return FeedbackBox(x1: numbers[0], y1: numbers[1], x2: numbers[2], y2: numbers[3])
}

func decodedSize(_ data: Data) -> PixelSize? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return PixelSize(width: image.width, height: image.height)
}

func stateField(_ request: JevRequest, _ key: String) -> JevValue? {
    guard case .object(let fields) = request.state else { return nil }
    return fields.first { $0.0.text == key }?.1
}

/// The key each `.screen` value sits under. An array's items sit under the array's key.
func screenKeys(in value: JevValue, key: String? = nil) -> [String?] {
    switch value {
    case .screen: [key]
    case .object(let fields): fields.flatMap { screenKeys(in: $0.1, key: $0.0.text) }
    case .array(let items): items.flatMap { screenKeys(in: $0, key: key) }
    case .reviewer, .code, .number, .bool, .image: []
    }
}

extension JevJobOutput {
    var cropLabels: [String] { lines.map(\.label.text).filter { $0.hasPrefix("Crop of this item") } }
    var searchLines: [JevRefinedLine] { lines.filter { $0.label.text.hasPrefix("Search the repository") } }
}

private let allKinds: JevDataKinds = [.reviewerText, .screenText, .images]

// MARK: - The job

@Suite("Crops and anchors: job")
struct CropsAnchorsJobTests {
    @Test("Reviewer text only: no request, a marks crop per item, two files each, and the rule line first")
    func reviewerTextOnly() async throws {
        let capture = cropsCapture(marks: [CropsMark(number: 1, box: centerBadge), CropsMark(number: 2, box: cornerBadge)])
        // Paint the two marks crops, so a crop from the wrong place or the wrong PNG shows.
        let boxes = [FeedbackBox(x1: 360, y1: 260, x2: 630, y2: 530), FeedbackBox(x1: 30, y1: 480, x2: 300, y2: 750)]
        let run = try await runCropsJob(capture, allowed: .reviewerText, highlights: boxes)

        #expect(run.requests.isEmpty)
        let names = [
            "1028-claude-item-1.png", "1028-claude-item-1-clean.png",
            "1028-claude-item-2.png", "1028-claude-item-2-clean.png",
        ]
        #expect(run.output.files.map(\.name) == names)
        // The seed plus 120 pixels on each side: 270 by 270.
        for file in run.output.files {
            #expect(decodedSize(file.data) == PixelSize(width: 270, height: 270), "\(file.name)")
            // Annotated crops come from the annotated PNG, clean crops from the clean PNG.
            #expect(allPixels(file.data, near: file.name.hasSuffix("-clean.png") ? [255, 255, 255] : [0, 255, 0]), "\(file.name)")
        }
        let words: JevCodeText = "cut around the marks, not checked"
        let expected = [
            cropsRuleLine,
            cropLine(1, words, FeedbackBox(x1: 360, y1: 260, x2: 630, y2: 530), file: names[0]),
            cleanLine(1, file: names[1]),
            cropLine(2, words, FeedbackBox(x1: 30, y1: 480, x2: 300, y2: 750), file: names[2]),
            cleanLine(2, file: names[3]),
        ]
        #expect(run.output.lines == expected)
    }

    @Test("Screen text only: one text request with no image, screen text under screen_text keys, and the exact line")
    func screenTextOnly() async throws {
        let marks = [CropsMark(number: 1, box: centerBadge, text: "Copy Prompt")]
        let run = try await runCropsJob(
            cropsCapture(marks: marks),
            allowed: [.reviewerText, .screenText],
            script: CropsScript(noul: ["anchor_fits": 0.9], choice: ["anchor": "line_2"])
        )

        #expect(run.requests.count == 1)
        let request = try #require(run.requests.first)
        #expect(request.images.isEmpty)
        #expect(!request.needsImagesHeader)
        #expect(request.kinds == [.reviewerText, .screenText])
        #expect(request.questions.map(\.id) == ["1.1.anchor", "1.1.anchor_fits"])

        let keys = screenKeys(in: request.state)
        #expect(keys.count == 5)
        #expect(keys.allSatisfy { $0 == "screen_text" })

        for (id, question) in request.questions {
            #expect(!question.kinds.contains(.screenText), "\(id) holds screen text")
            if case .code(let text) = question.instructions {
                #expect(text.text.hasPrefix(JevPrompting.screenTextNotice.text), "\(id)")
            } else {
                Issue.record("\(id) instructions are not code text")
            }
            if case .choice(let options) = question.kind {
                #expect(options.count == 4)
                for option in options {
                    let name = option.name.text
                    #expect(name.hasPrefix("line_") && name.count > 5 && name.dropFirst(5).allSatisfy(\.isNumber), "\(name)")
                }
            }
        }

        let set = AnchorCandidates.build(capture: cropsCapture(marks: marks), lines: nil)
        let candidate = try #require(set.lines.first { $0.id == "L002" })
        #expect(candidate.text == "Copy Prompt and End Round")
        #expect(run.output.lines.dropFirst().first == searchLine(1, candidate.text))
        #expect(run.output.searchLines == [searchLine(1, "Copy Prompt and End Round")])
    }

    @Test("Images only: requests A and B, no screen text in any, and edges checked")
    func imagesOnly() async throws {
        let run = try await runCropsJob(
            cropsCapture(),
            allowed: [.reviewerText, .images],
            script: CropsScript(noul: ["target_shown": 0.9])
        )

        #expect(run.requests.count == 2)
        #expect(run.requests.allSatisfy { !$0.kinds.contains(.screenText) })
        #expect(run.requests.allSatisfy { $0.needsImagesHeader })
        #expect(try run.request(0).questions.map(\.id) == ["1.1.target", "1.1.target_shown"])
        #expect(try run.request(1).questions.map(\.id) == ["1.1.cut_left", "1.1.cut_right", "1.1.cut_top", "1.1.cut_bottom"])

        // Jev's target (388, 288, 603, 503) in the 430 pixel window, plus 24 pixels, is inside
        // the marks crop, so the crop is the marks crop. The source is still the target.
        let object = try #require(summaryItem(run.output, "1.1"))
        #expect(summaryNumbers(object["target"]) == [388, 288, 603, 503])
        #expect(summaryCode(object["cropSource"]) == "target")
        #expect(run.output.lines == [
            cropsRuleLine,
            cropLine(1, "edges checked", defaultCrop, file: "1028-claude-item-1.png"),
            cleanLine(1, file: "1028-claude-item-1-clean.png"),
        ])
        #expect(run.output.searchLines.isEmpty)
    }

    @Test("An edge yes in round 1 and no in round 2: three requests, the left edge moved out, edges checked")
    func edgeMovesOnce() async throws {
        let marks = [CropsMark(number: 1, box: centerBadge), CropsMark(number: 2, box: cornerBadge)]
        let script = CropsScript(noul: ["target_shown": 0.9, "1.1.cut_left": 0.9])
        let run = try await runCropsJob(cropsCapture(marks: marks), allowed: [.reviewerText, .images], script: script)

        #expect(run.requests.count == 3)
        #expect(try run.request(1).questions.count == 8)
        // Only item 1 is asked again, with the second-check ids.
        #expect(try run.request(2).questions.map(\.id) == ["1.1.cut_left_2", "1.1.cut_right_2", "1.1.cut_top_2", "1.1.cut_bottom_2"])

        let base = defaultCrop
        let moved = ItemCrop.expanded(base, edges: .left, imageSize: PixelSize(width: 1000, height: 800))
        #expect(moved.x1 < base.x1)
        #expect(moved.y1 == base.y1 && moved.x2 == base.x2 && moved.y2 == base.y2)

        let labels = run.output.cropLabels
        #expect(labels.count == 2)
        #expect(labels.first == "Crop of this item (edges checked; px \(moved.x1) \(moved.y1) \(moved.x2) \(moved.y2) of the full image):")
        #expect(labels.last?.contains("edges checked") == true)
        let first = try #require(run.output.files.first)
        #expect(decodedSize(first.data) == PixelSize(width: moved.x2 - moved.x1, height: moved.y2 - moved.y1))
    }

    @Test("An edge yes in both rounds: the crop moves twice and says edges unsure")
    func edgeStaysCut() async throws {
        let script = CropsScript(noul: ["target_shown": 0.9, "cut_left": 0.9, "cut_left_2": 0.9])
        let run = try await runCropsJob(cropsCapture(), allowed: [.reviewerText, .images], script: script)

        #expect(run.requests.count == 3)
        let size = PixelSize(width: 1000, height: 800)
        let once = ItemCrop.expanded(defaultCrop, edges: .left, imageSize: size)
        let twice = ItemCrop.expanded(once, edges: .left, imageSize: size)
        #expect(twice.x1 < once.x1)
        #expect(run.output.cropLabels.first == "Crop of this item (edges unsure: open the full image if the crop cuts something off; px \(twice.x1) \(twice.y1) \(twice.x2) \(twice.y2) of the full image):")
    }

    @Test("A low target_shown or a low Box confidence gives the marks crop, and the edge check still runs")
    func marksCropAfterLowTarget() async throws {
        var lowShown = CropsScript(noul: ["target_shown": 0.1])
        lowShown.box = JevBoxAnswer(box: wideBox, confidence: 0.9)
        var lowConfidence = CropsScript(noul: ["target_shown": 0.9])
        lowConfidence.box = JevBoxAnswer(box: wideBox, confidence: 0.1)
        for script in [lowShown, lowConfidence] {
            let run = try await runCropsJob(cropsCapture(), allowed: [.reviewerText, .images], script: script)
            #expect(run.requests.count == 2)
            #expect(try run.request(1).questions.count == 4)
            let label = try #require(run.output.cropLabels.first)
            #expect(label.contains("edges checked"))
            #expect(cropPixelBox(label) == defaultCrop)
            let object = try #require(summaryItem(run.output, "1.1"))
            #expect(summaryCode(object["cropSource"]) == "marks")
            #expect(object["target"] == nil)
        }
    }

    @Test("When every request fails the job does not throw, and the crops say not checked")
    func requestsFail() async throws {
        var script = CropsScript()
        script.failure = JevError(.timeout)
        let run = try await runCropsJob(cropsCapture(), allowed: allKinds, script: script)

        #expect(run.requests.count == 2)
        #expect(run.output.files.count == 2)
        #expect(run.output.searchLines.isEmpty)
        #expect(run.output.lines == [
            cropsRuleLine,
            cropLine(1, "not checked: open the full image if the crop cuts something off", FeedbackBox(x1: 360, y1: 260, x2: 630, y2: 530), file: "1028-claude-item-1.png"),
            cleanLine(1, file: "1028-claude-item-1-clean.png"),
        ])
    }

    @Test("A request that does not answer before the cutoff ends the job before the deadline")
    func slowRequestStopsAtCutoff() async throws {
        var script = CropsScript()
        script.delay = .seconds(30)
        let run = try await runCropsJob(cropsCapture(), allowed: allKinds, script: script, budget: .milliseconds(1500))

        #expect(run.finishedAt < run.deadline)
        #expect(run.output.cropLabels.first?.contains("not checked: open the full image") == true)
        #expect(run.output.files.count == 2)
    }

    @Test("A low anchor_fits or a low Choice confidence gives no Search line")
    func noSearchLine() async throws {
        var lowConfidence = CropsScript(noul: ["anchor_fits": 0.9])
        lowConfidence.choiceConfidence = 0.1
        for script in [CropsScript(noul: ["anchor_fits": 0.1]), lowConfidence] {
            let run = try await runCropsJob(cropsCapture(), allowed: [.reviewerText, .screenText], script: script)
            #expect(run.requests.count == 1)
            #expect(run.output.searchLines.isEmpty)
        }
        // The same capture with good answers does get one.
        let good = try await runCropsJob(cropsCapture(), allowed: [.reviewerText, .screenText], script: CropsScript(noul: ["anchor_fits": 0.9]))
        #expect(good.output.searchLines == [searchLine(1, "Copy Last Capture Prompt")])
    }

    @Test("A capture with no badges and a note gets one whole-capture Search line, and no crop")
    func noBadges() async throws {
        let capture = cropsCapture(marks: [], note: "the title is wrong")
        let run = try await runCropsJob(capture, allowed: allKinds, script: CropsScript(noul: ["anchor_fits": 0.9], choice: ["anchor": "line_3"]))

        #expect(run.requests.count == 1)
        let request = try #require(run.requests.first)
        #expect(request.questions.map(\.id) == ["1.anchor", "1.anchor_fits"])
        #expect(request.images.isEmpty)
        if case .reviewer(let note)? = stateField(request, "general_note") {
            #expect(note == "the title is wrong")
        } else {
            Issue.record("general_note is not reviewer text")
        }
        #expect(stateField(request, "items") == nil)
        #expect(run.output.files.isEmpty)
        #expect(run.output.lines == [
            JevRefinedLine(scope: .capture, label: "Search the repository for this screen text (whole capture):", screenText: "Open Round Folder"),
        ])
    }

    @Test("A capture with no badges and no note sends nothing")
    func noBadgesNoNote() async throws {
        let run = try await runCropsJob(cropsCapture(marks: [], note: nil), allowed: allKinds)
        #expect(run.requests.isEmpty)
        #expect(run.output.lines.isEmpty && run.output.files.isEmpty)
        // The summary still has one object for the capture.
        let object = try #require(summaryItem(run.output, "1"))
        #expect(summaryCode(object["anchorStatus"]) == "noScreenText")
        #expect(object["cropStatus"] == nil)
    }

    @Test("A crop over half the full image's tokens gives no crop lines and no files")
    func notWorthIt() async throws {
        // The marks crop is 270 by 270 in a 300 by 300 image.
        let capture = cropsCapture(size: PixelSize(width: 300, height: 300), marks: [CropsMark(number: 1, box: FeedbackBox(x1: 135, y1: 135, x2: 165, y2: 165))])
        let run = try await runCropsJob(capture, allowed: .reviewerText)
        #expect(run.requests.isEmpty)
        #expect(run.output.lines.isEmpty)
        #expect(run.output.files.isEmpty)
    }

    @Test("Six items with images and screen text allowed take at most four requests")
    func sixItems() async throws {
        let corners = [(200, 200), (500, 200), (800, 200), (200, 600), (500, 600), (800, 600)]
        let marks = corners.enumerated().map { index, corner in
            CropsMark(number: index + 1, box: FeedbackBox(x1: corner.0, y1: corner.1, x2: corner.0 + 30, y2: corner.1 + 30))
        }
        let script = CropsScript(noul: ["target_shown": 0.9, "cut_left": 0.9, "anchor_fits": 0.9])
        let run = try await runCropsJob(cropsCapture(marks: marks), allowed: allKinds, script: script)

        #expect(run.requests.count <= 4)
        #expect(run.requests.count == 4)
        #expect(run.requests.filter { $0.questions.count == 12 }.count >= 2)
        // The text request holds no image. The image requests hold no screen text.
        let text = run.requests.filter { $0.kinds.contains(.screenText) }
        #expect(text.count == 1)
        #expect(text.allSatisfy { $0.images.isEmpty })
        #expect(run.requests.filter { $0.kinds.contains(.images) }.allSatisfy { !$0.kinds.contains(.screenText) })
        #expect(run.output.files.count == 12)
        #expect(run.output.searchLines.count == 6)
    }

    @Test("More items than the client allows images in a request: the extra items keep their marks crop, not checked")
    func moreItemsThanImages() async throws {
        let marks = (0..<10).map { index in
            let x = 100 + (index % 5) * 180
            let y = 150 + (index / 5) * 400
            return CropsMark(number: index + 1, box: FeedbackBox(x1: x, y1: y, x2: x + 30, y2: y + 30))
        }
        let run = try await runCropsJob(
            cropsCapture(marks: marks),
            allowed: [.reviewerText, .images],
            script: CropsScript(noul: ["target_shown": 0.9])
        )

        #expect(run.requests.count == 2)
        #expect(run.requests.allSatisfy { $0.images.count <= JevRequestEncoder.maxImages })
        #expect(try run.request(0).questions.count == 2 * JevRequestEncoder.maxImages)
        let labels = run.output.cropLabels
        #expect(labels.count == 10)
        #expect(labels.prefix(8).allSatisfy { $0.contains("edges checked") })
        #expect(labels.suffix(2).allSatisfy { $0.contains("not checked: open the full image") })
        #expect(run.output.files.count == 20)
    }

    @Test("A deadline that has passed loads no image, sends nothing, writes no crop, and does not throw")
    func deadlinePassed() async throws {
        let run = try await runCropsJob(cropsCapture(), allowed: allKinds, budget: .seconds(-1))
        #expect(run.requests.isEmpty)
        #expect(run.loads == 0)
        #expect(run.output.lines.isEmpty && run.output.files.isEmpty)
        #expect(run.output.failure == nil)
        #expect(summaryCode(summaryItem(run.output, "1.1")?["cropStatus"]) == "notChecked")
    }

    @Test("Past the request cutoff but before the crop stop: no load and no request, and the crops say not checked")
    func pastCutoffBeforeStop() async throws {
        // The cutoff is 500 ms before the deadline and the crops stop 100 ms before it.
        let run = try await runCropsJob(cropsCapture(), allowed: allKinds, budget: .milliseconds(450))
        #expect(run.requests.isEmpty)
        #expect(run.loads == 0)
        #expect(run.output.cropLabels.first?.contains("not checked: open the full image") == true)
        #expect(run.output.files.count == 2)
        #expect(run.output.searchLines.isEmpty)
    }

    @Test("Every combination of consent gives output that passes the writer's check")
    func outputPassesCheck() async throws {
        let marks = [CropsMark(number: 1, box: centerBadge, text: "Copy Prompt"), CropsMark(number: 2, box: cornerBadge, note: nil)]
        let kinds: [JevDataKinds] = [.reviewerText, [.reviewerText, .images], [.reviewerText, .screenText], allKinds]
        for allowed in kinds {
            let capture = cropsCapture(marks: marks)
            let script = CropsScript(noul: ["target_shown": 0.9])
            // runCropsJob calls JevBundleWriter.check; this repeats it with the output in hand.
            let run = try await runCropsJob(capture, allowed: allowed, script: script)
            try JevBundleWriter.check(run.output, for: capture, in: run.round)
            #expect(run.requests.allSatisfy { $0.kinds.isSubset(of: allowed) }, "\(allowed)")
        }
    }

    @Test("Two badges with the same number make one item, the first")
    func duplicateBadgeNumbers() async throws {
        let marks = [CropsMark(number: 1, box: centerBadge), CropsMark(number: 1, box: cornerBadge)]
        let run = try await runCropsJob(cropsCapture(marks: marks), allowed: .reviewerText)
        #expect(run.output.files.count == 2)
        #expect(run.output.cropLabels.compactMap(cropPixelBox) == [FeedbackBox(x1: 360, y1: 260, x2: 630, y2: 530)])
    }

    @Test("An item with no note gets code text in its place, in both kinds of request")
    func missingNote() async throws {
        let marks = [CropsMark(number: 1, box: centerBadge, note: nil)]
        let run = try await runCropsJob(cropsCapture(marks: marks), allowed: allKinds)

        let crops = try #require(run.requests.first { $0.kinds.contains(.images) })
        if case .code(let text)? = stateField(crops, "note_1") {
            #expect(text == "No note. Use the element that badge 1 sits on or points to.")
        } else {
            Issue.record("note_1 is not code text")
        }
        let search = try #require(run.requests.first { $0.kinds.contains(.screenText) })
        if case .object(let items)? = stateField(search, "items"), case .object(let item)? = items.first?.1,
           case .code(let text)? = item.first(where: { $0.0 == "note" })?.1 {
            #expect(text == "No note.")
        } else {
            Issue.record("items.item_1.note is not code text")
        }
        #expect(!run.requests.contains { $0.kinds.contains(.reviewerText) })
    }

    @Test("A capture PNG with another size than the stored one gives no crop files and no crop lines")
    func pngSizeMismatch() async throws {
        let run = try await runCropsJob(cropsCapture(), allowed: .reviewerText, pngSize: PixelSize(width: 500, height: 400))
        #expect(run.output.lines.isEmpty && run.output.files.isEmpty)
        #expect(summaryCode(summaryItem(run.output, "1.1")?["cropStatus"]) == "marksOnly")
    }
}

// MARK: - Helpers for the checks below

/// Every string in a decoded JSON value, with the key it sits under. An array's items sit under the array's key.
func jsonLeaves(_ value: Any, key: String? = nil) -> [(key: String?, text: String)] {
    if let text = value as? String { return [(key, text)] }
    if let object = value as? [String: Any] { return object.flatMap { jsonLeaves($0.value, key: $0.key) } }
    if let array = value as? [Any] { return array.flatMap { jsonLeaves($0, key: key) } }
    return []
}

func jsonKeys(_ value: Any) -> [String] {
    if let object = value as? [String: Any] { return object.flatMap { [$0.key] + jsonKeys($0.value) } }
    if let array = value as? [Any] { return array.flatMap { jsonKeys($0) } }
    return []
}

func bodyContains(_ body: Data, _ text: String) -> Bool {
    body.range(of: Data(text.utf8)) != nil
}

/// A 3000 by 100 capture with one badge and a box `seedWidth` wide that holds it.
/// Its crops are wide and thin, and the capture is too short to reshape a wide one.
func thinCapture(seedWidth: Int) -> FeedbackCapture {
    cropsCapture(
        size: PixelSize(width: 3000, height: 100),
        marks: [CropsMark(number: 1, box: FeedbackBox(x1: 1000, y1: 62, x2: 1030, y2: 92))],
        shapes: [FeedbackBox(x1: 1000, y1: 62, x2: 1000 + seedWidth, y2: 92)]
    )
}

private let edgesByName: [String: ItemCrop.Edges] = ["left": .left, "right": .right, "top": .top, "bottom": .bottom]

// MARK: - Deadlines, edges, and the state machine

@Suite("Crops and anchors: deadlines, edges, and mapping")
struct CropsAnchorsStateTests {
    @Test("A large capture with eight items and slow answers and loads returns before the deadline")
    func largeCaptureReturnsInTime() async throws {
        let marks = (0..<8).map { index in
            let x = 300 + (index % 4) * 700
            let y = 450 + (index / 4) * 800
            return CropsMark(number: index + 1, box: FeedbackBox(x1: x, y1: y, x2: x + 30, y2: y + 30))
        }
        var script = CropsScript(noul: ["target_shown": 0.9, "cut_left": 0.9, "cut_left_2": 0.9, "anchor_fits": 0.9])
        script.delay = .milliseconds(350)
        // Each load is a full decode of a 2880 by 1800 PNG. Slow it down more.
        let run = try await runCropsJob(
            cropsCapture(size: PixelSize(width: 2880, height: 1800), marks: marks),
            allowed: allKinds,
            script: script,
            budget: .seconds(2),
            loadHook: { _ in Thread.sleep(forTimeInterval: 0.1) }
        )

        #expect(run.finishedAt < run.deadline)
        #expect(run.requests.count <= 4)
        // Eight items need up to 24 loads. The cutoff stops them, and some items are left not checked.
        #expect(run.loads < 24)
    }

    @Test("An edge yes at the image border moves nothing, so the item is checked after one edge request")
    func edgeAtBorder() async throws {
        let badge = FeedbackBox(x1: 10, y1: 380, x2: 40, y2: 410)
        let script = CropsScript(noul: ["target_shown": 0.9, "cut_left": 0.9, "cut_left_2": 0.9])
        let run = try await runCropsJob(
            cropsCapture(marks: [CropsMark(number: 1, box: badge)]),
            allowed: [.reviewerText, .images],
            script: script
        )

        #expect(run.requests.count == 2)
        let label = try #require(run.output.cropLabels.first)
        #expect(label.contains("edges checked"))
        #expect(cropPixelBox(label)?.x1 == 0)
    }

    @Test("Each edge yes moves only its own edge", arguments: ["left", "right", "top", "bottom"])
    func eachEdgeMovesAlone(name: String) async throws {
        let size = PixelSize(width: 1000, height: 800)
        let base = defaultCrop
        let edge = try #require(edgesByName[name])
        let run = try await runCropsJob(
            cropsCapture(),
            allowed: [.reviewerText, .images],
            script: CropsScript(noul: ["target_shown": 0.9, "cut_\(name)": 0.9])
        )

        #expect(run.requests.count == 3)
        let box = try #require(run.output.cropLabels.first.flatMap(cropPixelBox))
        #expect(box == ItemCrop.expanded(base, edges: edge, imageSize: size))
        let changed = [box.x1 != base.x1, box.y1 != base.y1, box.x2 != base.x2, box.y2 != base.y2]
        #expect(changed.filter { $0 }.count == 1)
        #expect(run.output.cropLabels.first?.contains("edges checked") == true)
    }

    @Test("A crop the capture cannot reshape is too small in round 1, and gets no crop")
    func tooSmallInRoundOne() async throws {
        // The crop is 648 by 100, and the capture is only 100 pixels high.
        let run = try await runCropsJob(
            thinCapture(seedWidth: 600),
            allowed: [.reviewerText, .images],
            script: CropsScript(noul: ["target_shown": 0.9])
        )
        #expect(run.requests.count == 1)
        #expect(run.output.lines.isEmpty && run.output.files.isEmpty)
        #expect(summaryCode(summaryItem(run.output, "1.1")?["cropStatus"]) == "tooSmall")
    }

    @Test("A crop that an edge yes makes too wide to reshape is too small in round 2, and gets no crop")
    func tooSmallInRoundTwo() async throws {
        // The crop is the marks crop, 540 by 100: it fits the shape limit of 5.6. Both sides move out
        // by 135 pixels, to 810 by 100, and the capture is too short to grow it to 145.
        let script = CropsScript(noul: ["target_shown": 0.9, "cut_left": 0.9, "cut_right": 0.9])
        let run = try await runCropsJob(thinCapture(seedWidth: 300), allowed: [.reviewerText, .images], script: script)

        #expect(run.requests.count == 2)
        #expect(run.output.lines.isEmpty && run.output.files.isEmpty)
        #expect(summaryCode(summaryItem(run.output, "1.1")?["cropStatus"]) == "tooSmall")
    }

    @Test("In the last round the moved crop is reshaped, and the item says edges unsure")
    func lastRoundReshapes() async throws {
        // The marks crop is at least 270 pixels high, so a crop that the reshape can change is very
        // wide: a 1400 pixel shape in a 2400 by 1200 capture.
        let size = PixelSize(width: 2400, height: 1200)
        let seed = FeedbackBox(x1: 500, y1: 585, x2: 1900, y2: 615)
        // A flat strip across the window: a wide, short target.
        var script = CropsScript(noul: ["target_shown": 0.9, "cut_top": 0.9, "cut_left_2": 0.9, "cut_right_2": 0.9])
        script.box = JevBoxAnswer(box: JevBox(top: 0.45, bottom: 0.55, left: 0.05, right: 0.95), confidence: 0.9)
        let capture = cropsCapture(size: size, marks: [CropsMark(number: 1, box: FeedbackBox(x1: 1180, y1: 585, x2: 1210, y2: 615))], shapes: [seed])
        let run = try await runCropsJob(capture, allowed: [.reviewerText, .images], script: script)

        #expect(run.requests.count == 3)
        let image = try #require(try run.request(0).images.first)
        let target = image.sourceBox(for: script.box.box)
        // Round 1 shapes the target crop, and the top edge moves out. Round 2 shapes it again, and both sides move out.
        let first = try #require(ItemCrop.shaped(ItemCrop.targetCrop(target: target, seed: seed, imageSize: size), imageSize: size))
        let second = try #require(ItemCrop.shaped(ItemCrop.expanded(first, edges: .top, imageSize: size), imageSize: size))
        let moved = ItemCrop.expanded(second, edges: [.left, .right], imageSize: size)
        let reshaped = try #require(ItemCrop.shaped(moved, imageSize: size))
        // The case is only a test of the reshape if the reshape changes the box.
        #expect(reshaped != moved)

        let label = try #require(run.output.cropLabels.first)
        #expect(label.contains("edges unsure"))
        #expect(cropPixelBox(label) == reshaped)
    }

    @Test("A Jev target crop over half the full image's tokens ends not worth it, after its edge check")
    func targetCropNotWorthIt() async throws {
        let capture = cropsCapture(
            size: PixelSize(width: 600, height: 500),
            marks: [CropsMark(number: 1, box: FeedbackBox(x1: 285, y1: 235, x2: 315, y2: 265))]
        )
        var script = CropsScript(noul: ["target_shown": 0.9])
        script.box = JevBoxAnswer(box: JevBox(top: 0.02, bottom: 0.98, left: 0.02, right: 0.98), confidence: 0.9)
        let run = try await runCropsJob(capture, allowed: [.reviewerText, .images], script: script)

        #expect(run.requests.count == 2)
        #expect(run.output.lines.isEmpty && run.output.files.isEmpty)
        #expect(summaryCode(summaryItem(run.output, "1.1")?["cropStatus"]) == "notWorthIt")
    }

    @Test("An image that fails to load leaves that item not checked, and the others go on")
    func loaderFailsForOneItem() async throws {
        let marks = [CropsMark(number: 1, box: centerBadge), CropsMark(number: 2, box: cornerBadge)]
        // Load 1 is item 1's window, load 2 is item 2's window.
        let run = try await runCropsJob(
            cropsCapture(marks: marks),
            allowed: [.reviewerText, .images],
            script: CropsScript(noul: ["target_shown": 0.9]),
            loadHook: { call in if call == 2 { throw JevError(.jobError) } }
        )

        #expect(run.requests.count == 2)
        #expect(try run.request(0).questions.map(\.id) == ["1.1.target", "1.1.target_shown"])
        #expect(try run.request(1).questions.count == 4)
        let notChecked: JevCodeText = "not checked: open the full image if the crop cuts something off"
        #expect(run.output.lines == [
            cropsRuleLine,
            cropLine(1, "edges checked", defaultCrop, file: "1028-claude-item-1.png"),
            cleanLine(1, file: "1028-claude-item-1-clean.png"),
            cropLine(2, notChecked, FeedbackBox(x1: 30, y1: 480, x2: 300, y2: 750), file: "1028-claude-item-2.png"),
            cleanLine(2, file: "1028-claude-item-2-clean.png"),
        ])
    }

    @Test("An edge-check image that fails to load leaves the item not checked, with its crop")
    func loaderFailsInEdgeCheck() async throws {
        // Load 1 is the window, load 2 is the crop for the edge check.
        let run = try await runCropsJob(
            cropsCapture(),
            allowed: [.reviewerText, .images],
            script: CropsScript(noul: ["target_shown": 0.9]),
            loadHook: { call in if call == 2 { throw JevError(.jobError) } }
        )

        #expect(run.requests.count == 1)
        let label = try #require(run.output.cropLabels.first)
        #expect(label.contains("not checked: open the full image"))
        #expect(cropPixelBox(label) == defaultCrop)
    }

    @Test("A tight Box near the badge gives exactly the marks crop, and the source is still the target")
    func tightBoxGivesMarksCrop() async throws {
        var script = CropsScript(noul: ["target_shown": 0.9])
        // Fractions of the 430 pixel window around the badge: a box of about 43 pixels at its center.
        script.box = JevBoxAnswer(box: JevBox(top: 0.45, bottom: 0.55, left: 0.45, right: 0.55), confidence: 0.9)
        let run = try await runCropsJob(cropsCapture(), allowed: [.reviewerText, .images], script: script)

        let object = try #require(summaryItem(run.output, "1.1"))
        let target = try #require(summaryNumbers(object["target"]))
        // The target is a small box inside the marks crop, and the padded target is inside it too.
        #expect(target[2] - target[0] < 60 && target[3] - target[1] < 60)
        #expect(summaryCode(object["cropSource"]) == "target")
        let marksCrop = ItemCrop.marksCrop(seed: centerBadge, imageSize: PixelSize(width: 1000, height: 800))
        #expect(summaryNumbers(object["crop"]) == boxNumbers(marksCrop))
        #expect(marksCrop == defaultCrop)
        #expect(run.output.cropLabels.compactMap(cropPixelBox) == [marksCrop])
        #expect(run.output.cropLabels.first?.contains("edges checked") == true)
    }

    @Test("A Box with no confidence is incomplete: the marks crop, and the edge check still runs")
    func nilBoxConfidence() async throws {
        var script = CropsScript(noul: ["target_shown": 0.9])
        script.box = JevBoxAnswer(box: wideBox, confidence: nil)
        let run = try await runCropsJob(cropsCapture(), allowed: [.reviewerText, .images], script: script)

        #expect(run.requests.count == 2)
        #expect(try run.request(1).questions.count == 4)
        let label = try #require(run.output.cropLabels.first)
        #expect(label.contains("edges checked"))
        #expect(cropPixelBox(label) == defaultCrop)
        let object = try #require(summaryItem(run.output, "1.1"))
        #expect(summaryCode(object["cropSource"]) == "marks")
        #expect(object["target"] == nil)
    }

    @Test("The reviewer's note goes into requests A and B exactly as stored")
    func noteGoesInExactly() async throws {
        let notes = ["Brighter, \"2x\"  bigger (see 'Copy')\n  and more", "  Move it left  "]
        let marks = [
            CropsMark(number: 1, box: centerBadge, note: notes[0]),
            CropsMark(number: 2, box: cornerBadge, note: notes[1]),
        ]
        let run = try await runCropsJob(
            cropsCapture(marks: marks),
            allowed: [.reviewerText, .images],
            script: CropsScript(noul: ["target_shown": 0.9])
        )

        #expect(run.requests.count == 2)
        for index in 0..<2 {
            let request = try run.request(index)
            for (offset, note) in notes.enumerated() {
                if case .reviewer(let text)? = stateField(request, "note_\(offset + 1)") {
                    #expect(text == note, "request \(index) note_\(offset + 1)")
                } else {
                    Issue.record("request \(index) note_\(offset + 1) is not reviewer text")
                }
            }
        }
    }

    @Test("An asymmetric Box gives exact capture pixels for two items whose windows differ")
    func asymmetricBox() async throws {
        let marks = [CropsMark(number: 1, box: centerBadge), CropsMark(number: 2, box: cornerBadge)]
        var script = CropsScript(noul: ["target_shown": 0.9])
        script.box = JevBoxAnswer(box: JevBox(top: 0.1, bottom: 0.4, left: 0.6, right: 0.9), confidence: 0.9)
        let run = try await runCropsJob(cropsCapture(marks: marks), allowed: [.reviewerText, .images], script: script)

        // Item 1: window (280, 180, 710, 610) gives the target (538, 223, 667, 352).
        // Item 2: window (0, 400, 380, 800) gives the target (228, 440, 342, 560).
        let targets = [FeedbackBox(x1: 538, y1: 223, x2: 667, y2: 352), FeedbackBox(x1: 228, y1: 440, x2: 342, y2: 560)]
        let images = try run.request(0).images
        #expect(images.count == 2)
        #expect(images[0].sourceRegion != images[1].sourceRegion)
        #expect(zip(images, targets).allSatisfy { $0.sourceBox(for: script.box.box) == $1 })
        // The summary records each target in capture pixels.
        #expect(summaryNumbers(summaryItem(run.output, "1.1")?["target"]) == boxNumbers(targets[0]))
        #expect(summaryNumbers(summaryItem(run.output, "1.2")?["target"]) == boxNumbers(targets[1]))

        // Each crop joins the target with its seed box, adds 24 pixels, and keeps the marks crop.
        let size = PixelSize(width: 1000, height: 800)
        let expected = zip(targets, [centerBadge, cornerBadge]).map { ItemCrop.targetCrop(target: $0, seed: $1, imageSize: size) }
        #expect(expected == [FeedbackBox(x1: 360, y1: 199, x2: 691, y2: 530), FeedbackBox(x1: 30, y1: 416, x2: 366, y2: 750)])
        #expect(run.output.cropLabels.compactMap(cropPixelBox) == expected)
    }

    @Test("A window the loader pads is mapped through the padding")
    func paddedWindow() async throws {
        // The window is 700 by 100, and the capture is too short to grow it to 125.
        // So the job sends the raw window, and the loader pads it to 1568 by 280.
        let seed = FeedbackBox(x1: 1000, y1: 62, x2: 1300, y2: 92)
        let capture = thinCapture(seedWidth: 300)
        var script = CropsScript(noul: ["target_shown": 0.9])
        script.box = JevBoxAnswer(box: JevBox(top: 0.3, bottom: 0.41, left: 0.35, right: 0.45), confidence: 0.9)
        let run = try await runCropsJob(capture, allowed: [.reviewerText, .images], script: script)

        let image = try #require(try run.request(0).images.first)
        #expect(image.size == PixelSize(width: 1568, height: 280))
        #expect(image.contentRect.y1 > 0)
        #expect(image.sourceRegion == FeedbackBox(x1: 800, y1: 0, x2: 1500, y2: 100))

        let target = image.sourceBox(for: script.box.box)
        #expect(target == FeedbackBox(x1: 1045, y1: 25, x2: 1115, y2: 39))
        // The summary records that target. Read as plain fractions of the 100 pixel region,
        // the same Box would give (1045, 30, 1115, 41).
        let object = try #require(summaryItem(run.output, "1.1"))
        #expect(summaryNumbers(object["target"]) == boxNumbers(target))
        #expect(summaryNumbers(object["target"]) != [1045, 30, 1115, 41])
        // The crop is the target crop. Here the marks crop (880, 0, 1420, 100) holds it.
        let expected = ItemCrop.targetCrop(target: target, seed: seed, imageSize: capture.size)
        #expect(expected == FeedbackBox(x1: 880, y1: 0, x2: 1420, y2: 100))
        #expect(run.output.cropLabels.compactMap(cropPixelBox) == [expected])
    }

    @Test("Screen text and the window title leave only as screen_text values")
    func screenTextStaysInItsFields() async throws {
        let lines = ["Zebra Quartz Menu", "Quill Orbit Toggle", "Nimbus Harbor Panel"]
        let markText = "Plover Mark Snippet"
        let secrets = lines + [markText]
        let titles = ["Wombat Window Title 7731", "Yak Application 4410"]
        let capture = cropsCapture(
            marks: [CropsMark(number: 1, box: centerBadge, text: markText), CropsMark(number: 2, box: cornerBadge)],
            ocr: lines.joined(separator: "\n")
        )
        let combos: [JevDataKinds] = [.reviewerText, [.reviewerText, .images], [.reviewerText, .screenText], allKinds]
        for allowed in combos {
            let script = CropsScript(noul: ["target_shown": 0.9, "anchor_fits": 0.9])
            let run = try await runCropsJob(capture, allowed: allowed, script: script)
            if allowed == .reviewerText {
                #expect(run.requests.isEmpty)
            }
            // The summary holds numbers and code text only: no screen text, title, or note.
            let summary = String(decoding: try JSONEncoder().encode(JevSummaryValue.object(run.output.summary)), as: UTF8.self)
            for text in secrets + titles + ["make it brighter", "general note"] {
                #expect(!summary.contains(text), "\(text) in the summary with \(allowed)")
            }
            var inScreenText = Set<String>()
            for request in run.requests {
                let body = try JevRequestEncoder.encode(request).body
                for title in titles {
                    #expect(!bodyContains(body, title), "\(title) in a request with \(allowed)")
                }
                guard request.kinds.contains(.screenText) else {
                    for secret in secrets {
                        #expect(!bodyContains(body, secret), "\(secret) in a request with \(allowed)")
                    }
                    continue
                }
                // Request C is JSON. Read the instructions, option names, and keys from the decoded body.
                #expect(request.images.isEmpty)
                let json = try JSONSerialization.jsonObject(with: body)
                for key in jsonKeys(json) {
                    for secret in secrets {
                        #expect(!key.contains(secret), "\(secret) is a key")
                    }
                }
                for leaf in jsonLeaves(json) {
                    for secret in secrets where leaf.text.contains(secret) {
                        #expect(leaf.key == "screen_text", "\(secret) sits under \(leaf.key ?? "no key")")
                        inScreenText.insert(secret)
                    }
                }
            }
            if allowed.contains(.screenText) {
                #expect(inScreenText == Set(secrets))
            } else {
                #expect(inScreenText.isEmpty)
            }
        }
    }
}

// MARK: - Summary helpers

/// The summary objects, one per item (or one for a capture with no badges), by key.
func summaryObjects(_ output: JevJobOutput) -> [[String: JevSummaryValue]] {
    guard let field = output.summary.first(where: { $0.key.text == "items" }), case .array(let objects) = field.value else { return [] }
    return objects.compactMap { value in
        guard case .object(let fields) = value else { return nil }
        return Dictionary(fields.map { ($0.key.text, $0.value) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The summary object whose "item" is `id`, for example "1.2".
func summaryItem(_ output: JevJobOutput, _ id: String) -> [String: JevSummaryValue]? {
    summaryObjects(output).first { summaryCode($0["item"]) == id }
}

/// The keys of the summary object whose "item" is `id`, in order.
func summaryKeys(_ output: JevJobOutput, _ id: String) -> [String] {
    guard let field = output.summary.first(where: { $0.key.text == "items" }), case .array(let objects) = field.value else { return [] }
    for value in objects {
        if case .object(let fields) = value, fields.contains(where: { $0.key.text == "item" && summaryCode($0.value) == id }) {
            return fields.map { $0.key.text }
        }
    }
    return []
}

func summaryCode(_ value: JevSummaryValue?) -> String? {
    if case .code(let text)? = value { return text.text }
    return nil
}

func summaryNumbers(_ value: JevSummaryValue?) -> [Int]? {
    guard case .array(let items)? = value else { return nil }
    let numbers = items.compactMap { item -> Int? in
        if case .number(let number) = item { return Int(number) }
        return nil
    }
    return numbers.count == items.count ? numbers : nil
}

func boxNumbers(_ box: FeedbackBox) -> [Int] {
    [box.x1, box.y1, box.x2, box.y2]
}

// MARK: - Summary, failure, and search lines

@Suite("Crops and anchors: summary, failure, and search lines")
struct CropsAnchorsSummaryTests {
    @Test("The summary holds one object per item with the crop, window, target, and anchor facts")
    func summaryRecordsFacts() async throws {
        let marks = [CropsMark(number: 1, box: centerBadge), CropsMark(number: 2, box: cornerBadge)]
        var script = CropsScript(noul: ["target_shown": 0.9, "anchor_fits": 0.9], choice: ["1.2.anchor": "line_3"])
        script.box = JevBoxAnswer(box: JevBox(top: 0.1, bottom: 0.4, left: 0.6, right: 0.9), confidence: 0.9)
        let run = try await runCropsJob(cropsCapture(marks: marks), allowed: allKinds, script: script)

        // Requests A and C run together, so find A by its first question.
        let requestA = try #require(run.requests.first { $0.questions.first?.id.text == "1.1.target" })
        let images = requestA.images
        #expect(summaryObjects(run.output).count == 2)
        for (offset, id) in ["1.1", "1.2"].enumerated() {
            let object = try #require(summaryItem(run.output, id))
            let label = try #require(run.output.lines.first {
                $0.scope == .item(badge: offset + 1) && $0.label.text.hasPrefix("Crop of this item")
            }?.label.text)
            // The crop in the summary is the crop in the label.
            #expect(summaryNumbers(object["crop"]) == boxNumbers(try #require(cropPixelBox(label))))
            #expect(summaryCode(object["cropStatus"]) == "checked")
            #expect(summaryCode(object["cropSource"]) == "target")
            // The window is the region request A sent. The target is Jev's Box in capture pixels.
            #expect(summaryNumbers(object["window"]) == boxNumbers(images[offset].sourceRegion))
            #expect(summaryNumbers(object["target"]) == boxNumbers(images[offset].sourceBox(for: script.box.box)))
            #expect(summaryCode(object["anchorStatus"]) == "picked")
        }
        // The fallback has no line boxes. Item 1 picks the first row, item 2 the third.
        let first = try #require(summaryItem(run.output, "1.1"))
        let second = try #require(summaryItem(run.output, "1.2"))
        #expect(first["anchorSource"] == .number(0) && first["anchorBox"] == nil)
        #expect(second["anchorSource"] == .number(2) && second["anchorBox"] == nil)
        #expect(summaryKeys(run.output, "1.1") == ["item", "cropStatus", "cropSource", "crop", "window", "target", "anchorStatus", "anchorSource"])
    }

    @Test("Without images the summary has the marks crop and no window or target, and without screen text no anchor")
    func summaryWithoutImagesOrText() async throws {
        let run = try await runCropsJob(cropsCapture(), allowed: .reviewerText)
        let object = try #require(summaryItem(run.output, "1.1"))
        #expect(summaryCode(object["cropStatus"]) == "marksOnly")
        #expect(summaryCode(object["cropSource"]) == "marks")
        #expect(summaryNumbers(object["crop"]) == [360, 260, 630, 530])
        #expect(object["window"] == nil && object["target"] == nil)
        #expect(summaryCode(object["anchorStatus"]) == "noScreenText")
        #expect(object["anchorSource"] == nil && object["anchorBox"] == nil)
        #expect(summaryKeys(run.output, "1.1") == ["item", "cropStatus", "cropSource", "crop", "anchorStatus"])
    }

    @Test("Anchor statuses: noneFit for a low fit, notChecked for a failed request")
    func anchorStatuses() async throws {
        let lowFit = try await runCropsJob(cropsCapture(), allowed: [.reviewerText, .screenText], script: CropsScript(noul: ["anchor_fits": 0.1]))
        #expect(summaryCode(summaryItem(lowFit.output, "1.1")?["anchorStatus"]) == "noneFit")

        var failing = CropsScript()
        failing.failure = JevError(.server, status: 503)
        let failed = try await runCropsJob(cropsCapture(), allowed: [.reviewerText, .screenText], script: failing)
        #expect(summaryCode(summaryItem(failed.output, "1.1")?["anchorStatus"]) == "notChecked")

        // A capture with no screen text has nothing to offer.
        let none = try await runCropsJob(cropsCapture(ocr: nil), allowed: [.reviewerText, .screenText])
        #expect(none.requests.isEmpty)
        #expect(summaryCode(summaryItem(none.output, "1.1")?["anchorStatus"]) == "noScreenText")
    }

    @Test("A capture with no badges has one summary object with its anchor facts")
    func summaryForCaptureLevel() async throws {
        let capture = cropsCapture(marks: [], note: "the title is wrong")
        let script = CropsScript(noul: ["anchor_fits": 0.9], choice: ["anchor": "line_3"])
        let run = try await runCropsJob(capture, allowed: allKinds, script: script)

        #expect(summaryObjects(run.output).count == 1)
        let object = try #require(summaryItem(run.output, "1"))
        #expect(summaryCode(object["anchorStatus"]) == "picked")
        #expect(object["anchorSource"] == .number(2))
        #expect(object["cropStatus"] == nil)
    }

    @Test("Lines with boxes: candidates come nearest first, and the summary records the line's source and box")
    func screenLinesWithBoxes() async throws {
        func box(_ x: Int, _ y: Int) -> FeedbackBox { FeedbackBox(x1: x, y1: y, x2: x + 100, y2: y + 20) }
        let lines = [
            FeedbackTextLine(text: "Outside Label", box: box(10, 10)),
            FeedbackTextLine(text: "Middle Label", box: box(600, 385)),
            FeedbackTextLine(text: "Far Label", box: box(300, 200)),
            FeedbackTextLine(text: "Nearest Label", box: box(520, 385)),
        ]
        // Ids follow reading order: Far, Nearest, Middle. The item's list is nearest first: Nearest, Middle, Far.
        let script = CropsScript(noul: ["anchor_fits": 0.9], choice: ["anchor": "line_3"])
        let run = try await runCropsJob(cropsCapture(), allowed: [.reviewerText, .screenText], script: script, screenLines: lines)

        let request = try run.request(0)
        let anchor = try #require(request.questions.first { $0.id.text == "1.1.anchor" })
        guard case .choice(let options) = anchor.question.kind else {
            Issue.record("the anchor question is not a Choice")
            return
        }
        #expect(options.map(\.name.text) == ["line_2", "line_3", "line_1"])
        guard case .array(let sent)? = stateField(request, "screen_text") else {
            Issue.record("screen_text is not an array")
            return
        }
        let texts = sent.compactMap { value -> String? in
            if case .screen(let text) = value { return text }
            return nil
        }
        #expect(texts == ["line_1| Far Label", "line_2| Nearest Label", "line_3| Middle Label"])

        // line_3 is "Middle Label", the second line of the input.
        #expect(run.output.searchLines == [searchLine(1, "Middle Label")])
        let object = try #require(summaryItem(run.output, "1.1"))
        #expect(summaryCode(object["anchorStatus"]) == "picked")
        #expect(object["anchorSource"] == .number(1))
        #expect(summaryNumbers(object["anchorBox"]) == boxNumbers(box(600, 385)))
    }

    @Test("A failed request sets the failure, and the lines, files, and summary still return")
    func failureIsSet() async throws {
        var script = CropsScript()
        script.failure = JevError(.timeout)
        let run = try await runCropsJob(cropsCapture(), allowed: allKinds, script: script)

        #expect(run.output.failure == JevError(.timeout))
        #expect(run.output.files.count == 2)
        #expect(!run.output.lines.isEmpty)
        #expect(summaryCode(summaryItem(run.output, "1.1")?["cropStatus"]) == "notChecked")
        #expect(summaryCode(summaryItem(run.output, "1.1")?["anchorStatus"]) == "notChecked")
    }

    @Test("The first failure is reported: a crop request before the search request")
    func firstFailure() async throws {
        let mixed = CropsScript(noul: ["target_shown": 0.9], failureOnText: JevError(.server, status: 503))
        let searchOnly = try await runCropsJob(cropsCapture(), allowed: allKinds, script: mixed)
        #expect(searchOnly.output.failure == JevError(.server, status: 503))
        // The crops went through.
        #expect(summaryCode(summaryItem(searchOnly.output, "1.1")?["cropStatus"]) == "checked")

        // Only the crop requests fail: their error is reported, and the search line still comes.
        let cropsOnly = CropsScript(noul: ["anchor_fits": 0.9], failureOnImages: JevError(.timeout))
        let cropsFail = try await runCropsJob(cropsCapture(), allowed: allKinds, script: cropsOnly)
        #expect(cropsFail.output.failure == JevError(.timeout))
        #expect(cropsFail.output.searchLines == [searchLine(1, "Copy Last Capture Prompt")])

        // Both fail: the crop error comes first, whichever request ends first.
        let both = CropsScript(failureOnText: JevError(.server, status: 503), failureOnImages: JevError(.timeout))
        let bothFail = try await runCropsJob(cropsCapture(), allowed: allKinds, script: both)
        #expect(bothFail.output.failure == JevError(.timeout))
    }

    @Test("No failure when every request succeeds, or when a request is skipped at the cutoff")
    func noFailure() async throws {
        let ok = try await runCropsJob(cropsCapture(), allowed: allKinds, script: CropsScript(noul: ["target_shown": 0.9, "anchor_fits": 0.9]))
        #expect(ok.requests.count == 3)
        #expect(ok.output.failure == nil)

        let skipped = try await runCropsJob(cropsCapture(), allowed: allKinds, budget: .milliseconds(450))
        #expect(skipped.requests.isEmpty)
        #expect(skipped.output.failure == nil)

        var slow = CropsScript()
        slow.delay = .seconds(30)
        let late = try await runCropsJob(cropsCapture(), allowed: allKinds, script: slow, budget: .milliseconds(1500))
        #expect(late.output.failure == nil)
    }

    @Test("The job leaves the review file empty")
    func noReview() async throws {
        let run = try await runCropsJob(cropsCapture(), allowed: allKinds)
        #expect(run.output.review == nil)
    }
}

// MARK: - The sub-flags

@Suite("Crops and anchors: sub-flags")
struct CropsAnchorsSubFlagTests {
    private static let script = CropsScript(noul: ["target_shown": 0.9, "anchor_fits": 0.9], choice: ["anchor": "line_2"])

    private static func run(_ modes: [FeatureFlag: FlagState], allowed: JevDataKinds = allKinds) async throws -> CropsRun {
        let capture = cropsCapture(marks: [CropsMark(number: 1, box: centerBadge, text: "Copy Prompt")])
        return try await runCropsJob(capture, allowed: allowed, script: script, optionModes: modes)
    }

    private static let cropFiles = ["1028-claude-item-1.png", "1028-claude-item-1-clean.png"]

    @Test("The job is registered at version 2, and its options are its sub-flags")
    func identity() {
        let job = CropsAnchorsJob()
        #expect(job.version == 2)
        #expect(job.options == [.cropsItemCrops, .cropsSearchLines])
        #expect(job.options == FeatureFlag.subFlags(of: job.flag))
    }

    @Test("cropsItemCrops on alone: the two image requests, the crop files and lines, and no search request")
    func cropsOnly() async throws {
        let run = try await Self.run([.cropsItemCrops: .on])

        #expect(run.requests.count == 2)
        #expect(run.requests.allSatisfy { $0.needsImagesHeader && !$0.kinds.contains(.screenText) })
        #expect(run.output.files.map(\.name) == Self.cropFiles)
        #expect(run.output.lines.first == cropsRuleLine)
        #expect(run.output.cropLabels.count == 1)
        #expect(run.output.searchLines.isEmpty)
        // The summary has the crop fields and no anchor field.
        let keys = summaryKeys(run.output, "1.1")
        #expect(keys.contains("cropStatus") && !keys.contains("anchorStatus"))
    }

    @Test("cropsSearchLines on alone: one text request, no image load, no file, and the search line")
    func searchOnly() async throws {
        let run = try await Self.run([.cropsSearchLines: .on])

        #expect(run.requests.count == 1)
        #expect(run.requests.allSatisfy { $0.images.isEmpty && !$0.needsImagesHeader })
        #expect(run.loads == 0)
        #expect(run.output.files.isEmpty)
        #expect(run.output.cropLabels.isEmpty)
        #expect(run.output.lines == run.output.searchLines)
        #expect(run.output.searchLines.count == 1)
        let keys = summaryKeys(run.output, "1.1")
        #expect(keys.contains("anchorStatus") && !keys.contains("cropStatus"))
    }

    @Test("Both sub-flags off: no request, no image load, and an empty output")
    func bothOff() async throws {
        for modes: [FeatureFlag: FlagState] in [[:], [.cropsItemCrops: .off, .cropsSearchLines: .off]] {
            let run = try await Self.run(modes)
            #expect(run.requests.isEmpty, "\(modes)")
            #expect(run.loads == 0, "\(modes)")
            #expect(run.output == .empty, "\(modes)")
        }
    }

    @Test("cropsSearchLines on still needs screen text consent, and cropsItemCrops on still works with reviewer text only")
    func consentStillApplies() async throws {
        let search = try await Self.run([.cropsSearchLines: .on], allowed: [.reviewerText, .images])
        #expect(search.requests.isEmpty)
        #expect(search.output.lines.isEmpty && search.output.files.isEmpty)

        let crops = try await Self.run([.cropsItemCrops: .on], allowed: .reviewerText)
        #expect(crops.requests.isEmpty)
        #expect(crops.output.files.map(\.name) == Self.cropFiles)
    }

    @Test("A sub-flag in shadow records its answers and summary, and writes no file and no line")
    func shadowWritesNothing() async throws {
        let both = try await Self.run([.cropsItemCrops: .shadow, .cropsSearchLines: .shadow])
        #expect(both.requests.count == 3)
        #expect(both.output.files.isEmpty && both.output.lines.isEmpty)
        let keys = summaryKeys(both.output, "1.1")
        #expect(keys.contains("cropStatus") && keys.contains("anchorStatus"))

        // Crops on and search in shadow: the files and crop lines, and no search line.
        let cropsOn = try await Self.run([.cropsItemCrops: .on, .cropsSearchLines: .shadow])
        #expect(cropsOn.requests.count == 3)
        #expect(cropsOn.output.files.map(\.name) == Self.cropFiles)
        #expect(cropsOn.output.searchLines.isEmpty)
        #expect(summaryKeys(cropsOn.output, "1.1").contains("anchorStatus"))

        // Search on and crops in shadow: the search line, and no file and no crop line.
        let searchOn = try await Self.run([.cropsItemCrops: .shadow, .cropsSearchLines: .on])
        #expect(searchOn.requests.count == 3)
        #expect(searchOn.output.files.isEmpty && searchOn.output.cropLabels.isEmpty)
        #expect(searchOn.output.lines == searchOn.output.searchLines)
        #expect(searchOn.output.searchLines.count == 1)
        #expect(summaryKeys(searchOn.output, "1.1").contains("cropStatus"))
    }

    @Test("Shadow reports the same crop status, box, and requests as on, also where on writes no file")
    func shadowMatchesOn() async throws {
        // Where the crop status comes from: the size and worth-it checks, and the edge
        // checks. None of them reads the capture PNG that the crop files are cut from,
        // so skipping the PNG decode in shadow cannot change a status.
        var wide = CropsScript(noul: ["target_shown": 0.9])
        wide.box = JevBoxAnswer(box: JevBox(top: 0.02, bottom: 0.98, left: 0.02, right: 0.98), confidence: 0.9)
        let smallImage = cropsCapture(size: PixelSize(width: 300, height: 300), marks: [CropsMark(number: 1, box: FeedbackBox(x1: 135, y1: 135, x2: 165, y2: 165))])
        let mediumImage = cropsCapture(
            size: PixelSize(width: 600, height: 500),
            marks: [CropsMark(number: 1, box: FeedbackBox(x1: 285, y1: 235, x2: 315, y2: 265))]
        )
        let images: JevDataKinds = [.reviewerText, .images]
        let scenarios: [(name: String, capture: FeedbackCapture, allowed: JevDataKinds, script: CropsScript, pngSize: PixelSize?, status: String, writesFiles: Bool)] = [
            ("a normal crop", cropsCapture(), images, CropsScript(noul: ["target_shown": 0.9]), nil, "checked", true),
            ("a PNG of another size", cropsCapture(), .reviewerText, CropsScript(), PixelSize(width: 500, height: 400), "marksOnly", false),
            ("a crop that is not worth its tokens", smallImage, .reviewerText, CropsScript(), nil, "notWorthIt", false),
            ("a Jev target that is not worth its tokens", mediumImage, images, wide, nil, "notWorthIt", false),
            ("a crop that is too small", thinCapture(seedWidth: 600), images, CropsScript(noul: ["target_shown": 0.9]), nil, "tooSmall", false),
        ]
        for scenario in scenarios {
            let on = try await runCropsJob(scenario.capture, allowed: scenario.allowed, script: scenario.script, pngSize: scenario.pngSize, optionModes: [.cropsItemCrops: .on])
            let shadow = try await runCropsJob(scenario.capture, allowed: scenario.allowed, script: scenario.script, pngSize: scenario.pngSize, optionModes: [.cropsItemCrops: .shadow])

            #expect(summaryCode(summaryItem(on.output, "1.1")?["cropStatus"]) == scenario.status, "\(scenario.name): on")
            #expect(on.output.files.isEmpty != scenario.writesFiles, "\(scenario.name): on files")
            #expect(shadow.output.summary == on.output.summary, "\(scenario.name): shadow reports another summary than on")
            #expect(shadow.requests.count == on.requests.count, "\(scenario.name): shadow sends other requests than on")
            #expect(shadow.output.files.isEmpty && shadow.output.lines.isEmpty, "\(scenario.name): shadow writes a file or a line")
        }
    }
}

// MARK: - The runner

@Suite("Crops and anchors: runner")
struct CropsAnchorsRunnerTests {
    private static func body(_ answers: String) -> Result<JevHTTPResponse, JevError> {
        jsonResponse(#"{"model":"\#(JevEndpoint.model)","answers":{\#(answers)},"usage":{"input_tokens":10,"output_tokens":1}}"#)
    }

    /// Request A, then request B, for the one item of `Bundle.make()`.
    private static func imageResponses() -> [Result<JevHTTPResponse, JevError>] {
        [
            body(#""1.1.target":{"type":"box","box":{"top":0.25,"bottom":0.75,"left":0.25,"right":0.75},"confidence":0.9},"1.1.target_shown":{"type":"noul","noul":0.9}"#),
            body(["left", "right", "top", "bottom"].map { #""1.1.cut_\#($0)":{"type":"noul","noul":0.1}"# }.joined(separator: ",")),
        ]
    }

    @Test("With cropsAnchors off and jevBase on, nothing is sent and nothing is written")
    func off() async throws {
        let bundle = try await Bundle.make()
        let transport = StubTransport(Self.imageResponses())
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .jevSendImages: .on, .jevSendScreenText: .on]
        let runner = makeRunner(bundle, jobs: [CropsAnchorsJob()], flags: flags, transport: transport)
        await runCapture(runner, bundle)

        #expect(await transport.count == 0)
        #expect(!bundle.exists("jev.json"))
        let names = ItemCrop.fileNames(imageFile: bundle.capture.imageFile, badge: 1)
        #expect(!bundle.exists(names.annotated) && !bundle.exists(names.clean))
    }

    @Test("In shadow the job records its answers and writes no crop and no refined file")
    func shadow() async throws {
        let bundle = try await Bundle.make()
        let transport = StubTransport(Self.imageResponses())
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .cropsAnchors: .shadow, .cropsItemCrops: .on, .cropsSearchLines: .on, .jevSendImages: .on]
        let runner = makeRunner(bundle, jobs: [CropsAnchorsJob()], flags: flags, transport: transport)
        await runCapture(runner, bundle)

        let record = try #require(try bundle.record(1))
        #expect(record.job == "cropsAnchors" && record.mode == "shadow" && record.status == .done)
        #expect(record.jobVersion == 2)
        #expect(record.requests == 2)
        #expect(record.answers.map(\.id) == ["1.1.target", "1.1.target_shown", "1.1.cut_left", "1.1.cut_right", "1.1.cut_top", "1.1.cut_bottom"])
        #expect(record.lines.isEmpty && record.files.isEmpty)

        let names = ItemCrop.fileNames(imageFile: bundle.capture.imageFile, badge: 1)
        #expect(!bundle.exists(names.annotated) && !bundle.exists(names.clean))
        #expect(!bundle.exists(JevRefinedRenderer.captureFileName(for: bundle.capture)))
        #expect(!bundle.exists("refined.md"))
    }

    @Test("When on, the crop PNGs and the refined file are written to the bundle")
    func on() async throws {
        let bundle = try await Bundle.make()
        let transport = StubTransport(Self.imageResponses())
        let flags: [FeatureFlag: FlagState] = [.jevBase: .on, .cropsAnchors: .on, .cropsItemCrops: .on, .cropsSearchLines: .on, .jevSendImages: .on]
        let runner = makeRunner(bundle, jobs: [CropsAnchorsJob()], flags: flags, transport: transport)
        await runCapture(runner, bundle)

        let record = try #require(try bundle.record(1))
        #expect(record.mode == "on" && record.status == .done)
        let names = ItemCrop.fileNames(imageFile: bundle.capture.imageFile, badge: 1)
        #expect(record.files == [names.annotated, names.clean])
        for name in [names.annotated, names.clean] {
            #expect(bundle.exists(name), "\(name)")
            let data = try Data(contentsOf: bundle.folder.appendingPathComponent(name))
            #expect(decodedSize(data) != nil, "\(name) is not a PNG")
        }

        let refined = try bundle.text(JevRefinedRenderer.captureFileName(for: bundle.capture))
        #expect(refined.contains("Open each item's crop before the full image."))
        #expect(refined.contains("Item 1.1:\n- Crop of this item (edges checked; px "))
        #expect(refined.contains("`\(bundle.folder.path)/\(names.annotated)`"))
        #expect(refined.contains("- The same crop without marks: `\(bundle.folder.path)/\(names.clean)`"))
    }
}
