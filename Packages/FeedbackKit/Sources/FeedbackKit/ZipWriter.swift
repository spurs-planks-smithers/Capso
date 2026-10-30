// Packages/FeedbackKit/Sources/FeedbackKit/ZipWriter.swift
import Foundation

public struct ZipResult: Sendable, Equatable {
    public var url: URL
    /// The real size of the zip file.
    public var bytes: Int
    /// The ladder step that the zip was written at.
    public var stepIndex: Int
    /// True when the zip is over the budget at the floor.
    public var overBudget: Bool
    public var captureCount: Int
    /// Captures left out: an image file was not found, or the checked
    /// capture was not found at all.
    public var missing: [FeedbackBasketKey]
}

public enum ZipError: Error, Equatable {
    /// No capture has both of its images, so there is nothing to zip.
    case noCaptures
}

/// Writes a zip export (#85): a folder of JPEGs, `README.md`, `manifest.md`,
/// `feedback.json`, and the capture prompts, zipped with Foundation.
///
/// `NSFileCoordinator` with `.forUploading` zips a folder with no
/// `__MACOSX/` or `._` entries, even for files with extended attributes
/// (tested 2026-10-25). Fork code may not start a child process, so
/// `ditto` is not an option (`NetworkSourceScanTests`).
public enum ZipWriter {
    /// Builds the zip in a staging folder under `stagingRoot`, steps down the
    /// size ladder until the zip fits `budget` or the ladder ends, then moves
    /// it into `destination` under a name no file there has. Never overwrites.
    /// `unresolved` are checked captures that were not found. The README
    /// names them, so a zip never drops a capture without saying so.
    public static func write(
        kind: ZipKind,
        entries: [FeedbackSelectionEntry],
        unresolved: [FeedbackBasketKey] = [],
        into destination: URL,
        now: Date,
        timeZone: TimeZone,
        budget: Int = ZipLadder.budgetBytes,
        stagingRoot: URL = FileManager.default.temporaryDirectory
    ) throws -> ZipResult {
        let fileManager = FileManager.default
        var present: [FeedbackSelectionEntry] = []
        var missing: [FeedbackBasketKey] = []
        for entry in entries {
            let folder = URL(fileURLWithPath: entry.folderPath, isDirectory: true)
            let files = [entry.capture.imageFile, entry.capture.cleanImageFile]
            if files.allSatisfy({ fileManager.fileExists(atPath: folder.appendingPathComponent($0).path) }) {
                present.append(entry)
            } else {
                missing.append(FeedbackBasketKey(folderName: folder.lastPathComponent, captureIndex: entry.capture.index))
            }
        }
        guard let first = present.first else { throw ZipError.noCaptures }

        let time = kind == .round ? first.round.startedAt : now
        let base = ZipName.base(kind: kind, time: time, captureCount: present.count, timeZone: timeZone)
        // A folder left from an earlier unzip takes the name too: Archive
        // Utility would unzip into "<name> 2", and the person would open the
        // old folder.
        let name = FeedbackNaming.uniqueName(base) {
            fileManager.fileExists(atPath: destination.appendingPathComponent("\($0).zip").path)
                || fileManager.fileExists(atPath: destination.appendingPathComponent($0, isDirectory: true).path)
        }

        let staging = stagingRoot.appendingPathComponent("nextshot-zip-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        var stepIndex = 0
        while true {
            let step = ZipLadder.step(stepIndex)
            let plan = ZipPlanner.plan(kind: kind, entries: present, folderName: name, zipTime: now, pixelScale: step.pixelScale)
            let folder = staging.appendingPathComponent(name, isDirectory: true)
            try? fileManager.removeItem(at: folder)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeFiles(plan, kind: kind, step: step, missing: missing, unresolved: unresolved, timeZone: timeZone, into: folder)

            let zipURL = staging.appendingPathComponent("\(name).zip")
            try? fileManager.removeItem(at: zipURL)
            try zip(folder, to: zipURL)
            let bytes = try fileSize(zipURL)
            // Quality steps 0 to 2 always run before the floor can end the
            // ladder, so a round of small images still gets them.
            let ladderDone = stepIndex >= 2 && plan.atFloor
            if bytes <= budget || ladderDone {
                let target = destination.appendingPathComponent("\(name).zip")
                try fileManager.moveItem(at: zipURL, to: target)
                return ZipResult(
                    url: target,
                    bytes: bytes,
                    stepIndex: stepIndex,
                    overBudget: bytes > budget,
                    captureCount: present.count,
                    missing: missing + unresolved
                )
            }
            stepIndex += 1
        }
    }

    private static func writeFiles(
        _ plan: ZipPlan,
        kind: ZipKind,
        step: ZipStep,
        missing: [FeedbackBasketKey],
        unresolved: [FeedbackBasketKey],
        timeZone: TimeZone,
        into folder: URL
    ) throws {
        let paths = BundlePathMode.relative(exportFolderName: plan.round.folderName)
        let headerLines = plan.sourceRoundLines.isEmpty ? [] : ["Source rounds:"] + plan.sourceRoundLines
        let texts: [(String, String)] = [
            ("README.md", ZipReadme.render(plan, kind: kind, missing: missing, unresolved: unresolved)),
            ("manifest.md", ManifestWriter.render(plan.round, paths: paths, timeZone: timeZone, headerLines: headerLines)),
        ] + plan.round.captures.map {
            ($0.promptFile, PromptBuilder.renderCapture($0, paths: paths, redo: true))
        }
        for (name, text) in texts {
            try Data(text.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
        }
        try FeedbackRoundStore.encoder().encode(plan.round).write(to: folder.appendingPathComponent("feedback.json"), options: .atomic)

        for image in plan.images {
            let quality = image.isClean ? step.cleanQuality : step.annotatedQuality
            let data = try ExportImageEncoder.jpeg(contentsOf: image.sourceURL, size: image.size, quality: quality)
            try data.write(to: folder.appendingPathComponent(image.fileName), options: .atomic)
        }
        for attachment in plan.attachments {
            if let capture = plan.round.captures.first(where: { $0.browserEvidenceFile == attachment.name }),
               var object = try JSONSerialization.jsonObject(with: Data(contentsOf: attachment.source)) as? [String: Any] {
                object["exportedImages"] = ["annotated": capture.imageFile, "clean": capture.cleanImageFile, "width": capture.size.width, "height": capture.size.height]
                try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
                    .write(to: folder.appendingPathComponent(attachment.name), options: .atomic)
            } else {
                try FileManager.default.copyItem(at: attachment.source, to: folder.appendingPathComponent(attachment.name))
            }
        }
    }

    /// Zips `folder` into `target`. The zip's entries start with the folder's name.
    static func zip(_ folder: URL, to target: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            // The coordinator deletes its zip after this block, so copy it out.
            do {
                try FileManager.default.copyItem(at: zipped, to: target)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError {
            throw error
        }
    }

    private static func fileSize(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}
