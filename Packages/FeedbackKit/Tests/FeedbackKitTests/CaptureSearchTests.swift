import Foundation
import Testing
@testable import FeedbackKit

/// The Find Capture search (#125): every query word must appear in a field,
/// case and diacritics fold, OCR text never matches, and results come newest
/// first in a fixed order.
@Suite("CaptureSearch")
struct CaptureSearchTests {
    private static func capture(
        index: Int,
        minute: Int,
        app: String? = nil,
        window: String? = nil,
        instructions: [String] = [],
        note: String? = nil,
        ocr: String? = nil,
        markOCR: String? = nil
    ) -> FeedbackCapture {
        let marks = instructions.enumerated().map { offset, text in
            FeedbackMark(
                kind: .counter, badge: offset + 1,
                box: FeedbackBox(x1: 0, y1: 0, x2: 10, y2: 10),
                ocrText: markOCR,
                instruction: text
            )
        }
        return FeedbackCapture(
            index: index,
            imageFile: "\(index).png",
            cleanImageFile: "\(index)-clean.png",
            size: PixelSize(width: 100, height: 100),
            capturedAt: FeedbackFixtures.date(20, 10, minute),
            sourceApp: app,
            windowTitle: window,
            note: note,
            ocrText: ocr,
            marks: marks
        )
    }

    private static func entry(
        _ id: String,
        _ capture: FeedbackCapture,
        roundName: String? = nil,
        captureName: String? = nil
    ) -> CaptureSearch.Entry<String> {
        CaptureSearch.Entry(
            value: id,
            date: capture.capturedAt,
            tieBreak: id,
            fields: CaptureSearch.Fields(capture: capture, roundName: roundName, captureName: captureName)
        )
    }

    private static let sample: [CaptureSearch.Entry<String>] = [
        entry("pricing", capture(index: 1, minute: 1, app: "Safari", window: "Pricing | Acme",
                                 instructions: ["Price is wrong"], note: "Cards feel cramped"),
              roundName: "Pricing page review", captureName: "Fix the price"),
        entry("cafe", capture(index: 2, minute: 2, app: "Google Chrome", window: "Café menu",
                              instructions: ["Make the logo bigger"]),
              roundName: "Menu pass", captureName: "Bigger logo"),
        entry("cursor", capture(index: 3, minute: 3, app: "Cursor", window: "main.swift",
                                note: "Rename this helper", ocr: "secret screen words", markOCR: "badge ocr words"),
              roundName: "Code cleanup", captureName: "Rename helper"),
    ]

    @Test("An empty or blank query returns every capture, newest first")
    func emptyQuery() {
        for query in ["", " ", "\n\t  "] {
            #expect(CaptureSearch.results(Self.sample, query: query) == ["cursor", "cafe", "pricing"], "query '\(query)'")
        }
        #expect(CaptureSearch.words(in: "   ").isEmpty)
    }

    @Test("Case and diacritics fold in both directions")
    func folding() {
        #expect(CaptureSearch.results(Self.sample, query: "cafe") == ["cafe"])
        #expect(CaptureSearch.results(Self.sample, query: "CAFÉ") == ["cafe"])
        #expect(CaptureSearch.results(Self.sample, query: "SAFARI") == ["pricing"])
    }

    @Test("Every word must match, and the words may match different fields")
    func everyWordAcrossFields() {
        // "chrome" is the app, "logo" is a mark instruction, "menu" is the round name.
        #expect(CaptureSearch.results(Self.sample, query: "chrome logo menu") == ["cafe"])
        // "safari" is the app and "cramped" is the note.
        #expect(CaptureSearch.results(Self.sample, query: "safari cramped") == ["pricing"])
    }

    @Test("One missing word gives no match")
    func missingWord() {
        #expect(CaptureSearch.results(Self.sample, query: "chrome logo zebra").isEmpty)
        #expect(CaptureSearch.results(Self.sample, query: "safari logo").isEmpty)
    }

    @Test("Each field matches on its own")
    func eachField() {
        let capture = Self.capture(index: 1, minute: 0, app: "Appword", window: "Windowword",
                                   instructions: ["first", "Instructionword"], note: "Noteword")
        let fields = CaptureSearch.Fields(capture: capture, roundName: "Roundword", captureName: "Captureword")
        for word in ["appword", "windowword", "instructionword", "noteword", "roundword", "captureword"] {
            #expect(CaptureSearch.matches(fields, words: CaptureSearch.words(in: word)), "\(word)")
        }
        let empty = CaptureSearch.Fields(capture: Self.capture(index: 1, minute: 0), roundName: nil, captureName: nil)
        #expect(empty.texts.isEmpty)
        #expect(!CaptureSearch.matches(empty, words: ["appword"]))
        #expect(CaptureSearch.matches(empty, words: []))
    }

    @Test("OCR text of the capture and of its marks never matches")
    func ocrNeverMatches() {
        #expect(CaptureSearch.results(Self.sample, query: "secret").isEmpty)
        #expect(CaptureSearch.results(Self.sample, query: "badge ocr").isEmpty)
        // The same capture still matches its own words.
        #expect(CaptureSearch.results(Self.sample, query: "rename") == ["cursor"])
        // The pricing fixture holds OCR text on every badge.
        let pricing = CaptureSearch.Fields(capture: FeedbackFixtures.pricingCapture(), roundName: nil, captureName: nil)
        #expect(!CaptureSearch.matches(pricing, words: CaptureSearch.words(in: "Starter")))
        #expect(CaptureSearch.matches(pricing, words: CaptureSearch.words(in: "primary button")))
    }

    @Test("Results are newest first, and the tie-break key orders equal dates")
    func order() {
        let date = FeedbackFixtures.date(20, 10, 0)
        let fields = CaptureSearch.Fields(appName: "Safari", windowTitle: nil, marks: [], note: nil, roundName: nil, captureName: nil)
        let entries = [
            CaptureSearch.Entry(value: "b", date: date, tieBreak: "round:b:1", fields: fields),
            CaptureSearch.Entry(value: "newest", date: date.addingTimeInterval(60), tieBreak: "round:z:1", fields: fields),
            CaptureSearch.Entry(value: "a", date: date, tieBreak: "round:a:1", fields: fields),
            CaptureSearch.Entry(value: "oldest", date: date.addingTimeInterval(-60), tieBreak: "round:a:0", fields: fields),
        ]
        let expected = ["newest", "a", "b", "oldest"]
        #expect(CaptureSearch.results(entries, query: "safari") == expected)
        #expect(CaptureSearch.results(entries.reversed(), query: "safari") == expected)
        #expect(CaptureSearch.results(entries.shuffled(), query: "") == expected)
    }
}
