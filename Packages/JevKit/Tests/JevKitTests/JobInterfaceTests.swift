import FeedbackKit
import Foundation
import Testing
@testable import JevKit

/// A context for a job test. Feature sessions can copy this: the asker
/// records each request and returns the canned response, and the image
/// loader returns a blank image of the size the job asks for.
func makeContext(
    capture: FeedbackCapture = sampleCapture(),
    allowed: JevDataKinds = .reviewerText,
    response: JevResponse = JevResponse(model: JevEndpoint.model, answers: [:], inputTokens: 0, outputTokens: 0),
    sent: RequestLog = RequestLog()
) -> JevJobContext {
    let round = FeedbackRound(
        name: "feedback",
        slug: "feedback",
        folderName: "2026-10-24-1028-feedback",
        startedAt: Date(timeIntervalSince1970: 1_792_000_000),
        captures: [capture]
    )
    return JevJobContext(
        round: round,
        capture: capture,
        folderURL: URL(fileURLWithPath: "/tmp/nextshot-test/\(round.folderName)", isDirectory: true),
        allowed: allowed,
        deadline: .now + .seconds(2),
        jev: JevAsker { request in
            await sent.append(request)
            return response
        },
        images: JevImageLoader { _, _, region in
            let box = region ?? FeedbackBox(x1: 0, y1: 0, x2: capture.size.width, y2: capture.size.height)
            return JevImage(
                png: Data(),
                size: PixelSize(width: 400, height: 300),
                sourceRegion: box,
                contentRect: FeedbackBox(x1: 0, y1: 0, x2: 400, y2: 300)
            )
        }
    )
}

func sampleCapture() -> FeedbackCapture {
    FeedbackCapture(
        index: 1,
        imageFile: "1028-claude.png",
        cleanImageFile: "1028-claude-clean.png",
        size: PixelSize(width: 800, height: 600),
        capturedAt: Date(timeIntervalSince1970: 1_792_000_000),
        sourceApp: "Claude",
        windowTitle: "Claude",
        note: "general note",
        ocrText: "Copy Last Capture Prompt",
        marks: [
            FeedbackMark(kind: .counter, badge: 1, box: FeedbackBox(x1: 100, y1: 100, x2: 130, y2: 130), instruction: "make it brighter"),
        ]
    )
}

actor RequestLog {
    private(set) var requests: [JevRequest] = []

    func append(_ request: JevRequest) {
        requests.append(request)
    }

    var count: Int { requests.count }
}

@Suite("Job interface")
struct JobInterfaceTests {
    @Test("The registry lists one job per planned feature, with distinct ids and flags")
    func registryLines() {
        let jobs = JevJobRegistry.all
        #expect(jobs.map(\.id) == ["noteCoach", "cropsAnchors", "dupesConflicts", "oneBreath", "promptLanes", "dataGuard"])
        #expect(jobs.map(\.flag) == [.noteCoach, .cropsAnchors, .dupesConflicts, .oneBreath, .promptLanes, .dataGuard])
        #expect(Set(jobs.map(\.id)).count == jobs.count)
    }

    @Test("Each job's id matches its flag's name, so jev.json and the flags read alike")
    func idsMatchFlags() {
        for job in JevJobRegistry.all {
            #expect(job.id == job.flag.rawValue)
        }
    }

    @Test("A stub job sends nothing and returns no lines")
    func stubsSendNothing() async throws {
        for job in JevJobRegistry.all where job.version == 0 {
            let sent = RequestLog()
            let output = try await job.run(makeContext(sent: sent))
            #expect(output == .empty, "\(job.id) stub returned output")
            #expect(await sent.count == 0, "\(job.id) stub sent a request")
        }
    }

    @Test("A request lists every data kind it holds, at any depth")
    func requestKinds() {
        let image = JevImage(png: Data([1]), size: PixelSize(width: 300, height: 300), sourceRegion: FeedbackBox(x1: 0, y1: 0, x2: 300, y2: 300), contentRect: FeedbackBox(x1: 0, y1: 0, x2: 300, y2: 300))
        let textOnly = JevRequest(state: .fields(["note": .reviewer("brighter")]), questions: ["1.1.clear": .noul("Does `note` name a change?")])
        #expect(textOnly.kinds == .reviewerText)
        #expect(!textOnly.needsImagesHeader)

        let nested = JevRequest(
            state: .fields(["items": .array([.fields(["screen_text": .screen("OK"), "shot": .image(image)])])]),
            questions: ["q": .choice("Which?", options: ["a": .code("first"), "b": .reviewer("second")])]
        )
        #expect(nested.kinds == [.reviewerText, .screenText, .images])
        #expect(nested.images.map(\.id) == [image.id])
        #expect(nested.needsImagesHeader)
    }

    @Test("A Box question needs the images header even before an image is added")
    func boxNeedsHeader() {
        let request = JevRequest(state: "text", questions: ["where": .box("the button")])
        #expect(request.needsImagesHeader)
    }

    @Test("The same image used twice is one image in the request")
    func imagesAreDistinct() {
        let image = JevImage(png: Data([1]), size: PixelSize(width: 300, height: 300), sourceRegion: FeedbackBox(x1: 0, y1: 0, x2: 300, y2: 300), contentRect: FeedbackBox(x1: 0, y1: 0, x2: 300, y2: 300))
        let request = JevRequest(state: .array([.image(image), .image(image)]), questions: ["q": .noul(.fields(["see": .image(image)]))])
        #expect(request.images.count == 1)
    }

    @Test("A Box maps back to capture pixels through scaling and padding")
    func boxMapsToSource() {
        // A 200 x 100 region scaled 2x into 400 x 200, padded to 400 x 280.
        let image = JevImage(
            png: Data(),
            size: PixelSize(width: 400, height: 280),
            sourceRegion: FeedbackBox(x1: 50, y1: 60, x2: 250, y2: 160),
            contentRect: FeedbackBox(x1: 0, y1: 40, x2: 400, y2: 240)
        )
        let box = image.sourceBox(for: JevBox(top: 40.0 / 280, bottom: 240.0 / 280, left: 0.25, right: 0.75))
        #expect(box == FeedbackBox(x1: 100, y1: 60, x2: 200, y2: 160))
        // A box in the padding clamps to the region's edge.
        let padding = image.sourceBox(for: JevBox(top: 0, bottom: 0.1, left: 0, right: 1))
        #expect(padding.y1 == 60 && padding.y2 == 60)
    }
}
