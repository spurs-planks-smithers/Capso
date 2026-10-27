import CryptoKit
import FeedbackKit
import Foundation
import ImageIO

/// A support upload contains annotated images and notes only.
public enum SupportArchiveWriter {
    public static func prepare(round: FeedbackRound, folder: URL, app: SupportApp, note: String, contactEmail: String?, temporaryRoot: URL = FileManager.default.temporaryDirectory) throws -> SupportPackage {
        try SupportInput.validate(note: note, contactEmail: contactEmail)
        guard round.schemaVersion == FeedbackRound.currentSchemaVersion else { throw SupportError.invalidInput }
        guard !round.captures.isEmpty else { throw SupportError.noCaptures }
        guard round.captures.count <= SupportLimits.captures else { throw SupportError.tooLarge }
        let captures = round.captures.sorted { $0.index < $1.index }
        guard Set(captures.map(\.index)).count == captures.count, captures.allSatisfy({ $0.index > 0 }) else { throw SupportError.invalidInput }
        let text = ([note] + captures.flatMap { [$0.note ?? ""] + FeedbackItems.split($0).items.map { $0.badge.instruction ?? "" } }).joined(separator: "\n")
        guard text.utf8.count <= SupportLimits.textBytes else { throw SupportError.tooLarge }
        guard SupportPrivacy.findings(in: text).isEmpty else { throw SupportError.sensitiveContent }
        let identifier = UUID().uuidString.lowercased()
        let root = temporaryRoot.appendingPathComponent("nextshot-support-\(identifier)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: root) } }
        let contents = root.appendingPathComponent("nextshot-support", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var reduced: [SupportCapture] = []
        var totalPixels = 0
        let canonicalFolder = folder.standardizedFileURL.resolvingSymlinksInPath()
        for capture in captures {
            try Task.checkCancellation()
            guard !capture.imageFile.isEmpty, (capture.imageFile as NSString).lastPathComponent == capture.imageFile,
                  !capture.imageFile.hasPrefix("."), !capture.imageFile.contains("\\") else { throw SupportError.invalidInput }
            let sourceURL = canonicalFolder.appendingPathComponent(capture.imageFile)
            let values = try sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true,
                  sourceURL.resolvingSymlinksInPath().deletingLastPathComponent() == canonicalFolder,
                  let source = CGImageSourceCreateWithURL(sourceURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(source) == 1,
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= SupportLimits.imagePixels / height else { throw SupportError.unreadableImage }
            totalPixels += width * height
            guard totalPixels <= SupportLimits.totalPixels else { throw SupportError.tooLarge }
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw SupportError.unreadableImage }
            try SupportPrivacy.checkImage(image)
            let size = ImageSizing.resizedSize(PixelSize(width: width, height: height), limits: .standard)
            let fileName = "capture-\(capture.index).jpg"
            let jpeg = try ExportImageEncoder.jpeg(contentsOf: sourceURL, size: size, quality: 0.75)
            try jpeg.write(to: contents.appendingPathComponent(fileName), options: .atomic)
            reduced.append(SupportCapture(capture: capture, imageFile: fileName, size: size))
        }
        let manifest = SupportManifest(app: app, note: note, contactEmail: contactEmail?.isEmpty == false ? contactEmail : nil, captures: reduced)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: contents.appendingPathComponent("support.json"), options: .atomic)
        let archive = root.appendingPathComponent("support.zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: contents, options: .forUploading, error: &coordinationError) { zip in
            do { try FileManager.default.copyItem(at: zip, to: archive) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        try Task.checkCancellation()
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard data.count <= SupportLimits.uploadBytes else { throw SupportError.tooLarge }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        complete = true
        return SupportPackage(url: archive, bytes: data.count, sha256: digest, idempotencyKey: identifier, note: note, contactEmail: manifest.contactEmail, captureCount: captures.count)
    }
}
