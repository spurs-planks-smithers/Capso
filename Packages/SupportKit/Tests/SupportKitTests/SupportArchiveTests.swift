import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import FeedbackKit
@testable import SupportKit

@Suite("Reduced support archives")
struct SupportArchiveTests {
    private let app = SupportApp(version: "0.3.0-dev", build: "123", channel: "dev", osVersion: "macOS")

    private func fixture() throws -> (URL, FeedbackRound) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = try #require(CGContext(data: nil, width: 100, height: 90, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 100, height: 90))
        let image = try #require(context.makeImage())
        let target = folder.appendingPathComponent("private-window.png")
        let destination = try #require(CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "private-metadata"]] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        let capture = FeedbackCapture(index: 2, imageFile: "private-window.png", cleanImageFile: "does-not-exist.png", size: PixelSize(width: 100, height: 90), capturedAt: Date(), sourceApp: "PrivateApp", windowTitle: "private-title", note: "Please move the control", ocrText: "private-stored-ocr")
        return (folder, FeedbackRound(name: "private-round", slug: "private-slug", folderName: folder.lastPathComponent, startedAt: Date(), captures: [capture]))
    }

    private func unzip(_ archive: URL, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments + [archive.path]
        let output = Pipe(); process.standardOutput = output
        let error = Pipe(); process.standardError = error
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return bytes
    }

    @Test("Archive has only generic annotated JPEG and reduced JSON, without requiring a clean copy")
    func archiveContents() throws {
        let (folder, round) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let package = try SupportArchiveWriter.prepare(round: round, folder: folder, app: app, note: "", contactEmail: nil)
        defer { package.remove() }
        let list = String(decoding: try unzip(package.url, arguments: ["-Z1"]), as: UTF8.self)
        let files = Set(list.split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/") })
        try #require(!files.isEmpty)
        #expect(files == ["nextshot-support/support.json", "nextshot-support/capture-2.jpg"])
        let allBytes = try unzip(package.url, arguments: ["-p"])
        let text = String(decoding: allBytes, as: UTF8.self)
        for privateValue in ["private-window", "private-title", "PrivateApp", "private-stored-ocr", "private-metadata", "private-round", "private-slug", "does-not-exist"] {
            #expect(!text.contains(privateValue))
        }
        #expect(package.bytes <= SupportLimits.uploadBytes)
        #expect(package.sha256.count == 64)
    }

    @Test("A symlink cannot upload an image outside the round")
    func noSymlink() throws {
        let (folder, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.png"), withDestinationURL: folder.appendingPathComponent("private-window.png"))
        var round = original; round.captures[0].imageFile = "link.png"
        #expect(throws: SupportError.unreadableImage) { try SupportArchiveWriter.prepare(round: round, folder: folder, app: app, note: "", contactEmail: nil) }
        round.captures[0].imageFile = "../outside.png"
        #expect(throws: SupportError.invalidInput) { try SupportArchiveWriter.prepare(round: round, folder: folder, app: app, note: "", contactEmail: nil) }
    }

    @Test("A sensitive note fails before any archive survives")
    func sensitiveNote() throws {
        let (folder, round) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: SupportError.sensitiveContent) { try SupportArchiveWriter.prepare(round: round, folder: folder, app: app, note: "api_key=private-key-12345", contactEmail: nil) }
        #expect(throws: SupportError.invalidInput) { try SupportInput.validate(note: "one\ntwo", contactEmail: nil) }
        #expect(throws: SupportError.invalidInput) { try SupportInput.validate(note: "", contactEmail: "test@example.com\r\nBcc:other@example.com") }
    }
}
