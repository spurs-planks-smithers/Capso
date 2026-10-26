import Foundation
import Testing
import FeedbackKit
@testable import SupportKit

@Suite("Support submission boundaries")
struct SupportTests {
    @Test("Credentials and private numbers hold content without returning the value")
    func privateContent() {
        for text in ["password=do-not-share-this", "123-45-6789", "4111 1111 1111 1111", "-----BEGIN PRIVATE KEY-----"] {
            #expect(!SupportPrivacy.findings(in: text).isEmpty)
        }
        #expect(SupportPrivacy.findings(in: "Please make the button gray. Build 12345.").isEmpty)
        #expect(SupportPrivacy.findings(in: "4111 1111 1111 1112").isEmpty)
    }

    @Test("Reduced manifest excludes original screen metadata")
    func reducedManifest() throws {
        let mark = FeedbackMark(kind: .counter, badge: 2, box: FeedbackBox(x1: 0, y1: 0, x2: 10, y2: 10), ocrText: "secret-mark-ocr", instruction: "Move this button")
        let capture = FeedbackCapture(index: 3, imageFile: "window-title.png", cleanImageFile: "private-clean.png", size: PixelSize(width: 100, height: 90), capturedAt: Date(), sourceApp: "private-app", windowTitle: "private-title", note: "General note", ocrText: "private-ocr", marks: [mark])
        let reduced = SupportCapture(capture: capture, imageFile: "capture-1.jpg", size: capture.size)
        let text = String(decoding: try JSONEncoder().encode(reduced), as: UTF8.self)
        for excluded in ["window-title", "private-clean", "private-app", "private-title", "private-ocr", "secret-mark-ocr", "cleanImageFile", "capturedAt", "marks"] {
            #expect(!text.contains(excluded))
        }
        #expect(text.contains("3.2"))
        #expect(text.contains("Move this button"))
    }

    @Test("Endpoint paths cannot leave the submission API")
    func endpointPaths() throws {
        #expect(try SupportEndpoint.url(path: "/v1/reservations").host == "feedback.nextshot.dev")
        #expect(throws: SupportError.self) { try SupportEndpoint.url(path: "https://example.com/") }
        #expect(throws: SupportError.self) { try SupportEndpoint.url(path: "/v1/../download") }
        #expect(throws: SupportError.self) { try SupportEndpoint.url(path: "/v1/submissions/a?token=x") }
    }
}
