import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import FeedbackKit
import SupportKit
@testable import Capso

@MainActor
final class FeedbackSupportSubmissionTests: XCTestCase {
    @MainActor private final class Panel: FeedbackSupportPresenting {
        var onSubmit: ((String, String) -> Void)?
        var onClosed: (() -> Void)?
        var receipts: [String] = []
        func show(captureCount: Int) {}
        func bringForward() {}
        func setSending(_ status: String) {}
        func fail(_ status: String, prepared: Bool) {}
        func received(_ identifier: String) { receipts.append(identifier) }
    }

    @MainActor private final class Gate {
        var started = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            started = true
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { XCTFail("Operation did not reach the expected state"); return }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private func fixture() throws -> (root: URL, folder: URL, round: FeedbackRound, first: SupportPackage, second: SupportPackage) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("round", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(folder.appendingPathComponent("image.png") as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let capture = FeedbackCapture(index: 1, imageFile: "image.png", cleanImageFile: "unused.png", size: PixelSize(width: 40, height: 40), capturedAt: Date())
        let round = FeedbackRound(name: "feedback", slug: "feedback", folderName: "round", startedAt: Date(), captures: [capture])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(round).write(to: folder.appendingPathComponent("feedback.json"))
        let app = SupportApp(version: "0.3.0-dev", build: "1", channel: "dev", osVersion: "macOS")
        let first = try SupportArchiveWriter.prepare(round: round, folder: folder, app: app, note: "A", contactEmail: nil)
        let second = try SupportArchiveWriter.prepare(round: round, folder: folder, app: app, note: "B", contactEmail: nil)
        return (root, folder, round, first, second)
    }

    func testCancelledPreparationCannotClearTheReopenedSubmission() async throws {
        let fixture = try fixture()
        defer { fixture.first.remove(); fixture.second.remove(); try? FileManager.default.removeItem(at: fixture.root) }
        let firstPanel = Panel(), secondPanel = Panel()
        var panels = [firstPanel, secondPanel]
        let firstPreparation = Gate(), secondUpload = Gate()
        var preparationCount = 0
        var sendCount = 0
        let receipt = try JSONDecoder().decode(SupportReceipt.self, from: Data(#"{"id":"receipt-b","status":"received"}"#.utf8))
        let submission = FeedbackSupportSubmission(
            rootURL: fixture.root,
            waitForSaves: {}, captureIsOpen: { false }, showToast: { _ in }, isEnabled: { true },
            makePanel: { panels.removeFirst() },
            prepare: { _, _, _, note, _ in
                preparationCount += 1
                if note == "A" { await firstPreparation.wait(); return fixture.first }
                return fixture.second
            },
            send: { _ in
                sendCount += 1
                if sendCount == 1 { await secondUpload.wait() }
                return receipt
            }
        )
        submission.show(round: fixture.round)
        firstPanel.onSubmit?("A", "")
        try await waitUntil { firstPreparation.started }
        firstPanel.onClosed?()
        submission.show(round: fixture.round)
        secondPanel.onSubmit?("B", "")
        try await waitUntil { secondUpload.started }

        firstPanel.onClosed?()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.second.url.path), "A repeated close from panel A must not cancel panel B")
        firstPreparation.release()
        try await waitUntil { !FileManager.default.fileExists(atPath: fixture.first.url.path) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.second.url.path), "Cancelled preparation A must not delete package B")
        secondPanel.onSubmit?("B", "")
        // A still-running upload must ignore a repeated click after A finishes.
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(preparationCount, 2)
        XCTAssertEqual(sendCount, 1)

        secondUpload.release()
        try await waitUntil { secondPanel.receipts.count == 1 }
        XCTAssertEqual(secondPanel.receipts, ["receipt-b"])
        XCTAssertTrue(firstPanel.receipts.isEmpty)
        secondPanel.onClosed?()
    }
}
