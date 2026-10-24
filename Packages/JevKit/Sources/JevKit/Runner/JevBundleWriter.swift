// Packages/JevKit/Sources/JevKit/Runner/JevBundleWriter.swift
import FeedbackKit
import Foundation

/// Writes `jev.json`, the refined files, and the extra files jobs return.
/// One actor, so two writes to a bundle never overlap. Every file is written
/// atomically, so a reader never sees half a file.
actor JevBundleWriter {
    let rootURL: URL
    let jobOrder: [String]

    init(rootURL: URL, jobOrder: [String]) {
        self.rootURL = rootURL
        self.jobOrder = jobOrder
    }

    /// One finished job, as the runner hands it over. `output` is set only
    /// for a job in the `on` state that returned.
    struct Finished: Sendable {
        var record: JevJobRecord
        var output: JevJobOutput?
    }

    /// Stores one capture's jobs, writes any extra files, and renders the
    /// capture's refined file and refined.md.
    func record(folderName: String, round: FeedbackRound, capture: FeedbackCapture, jobs: [Finished]) throws {
        let folder = rootURL.appendingPathComponent(folderName, isDirectory: true)
        var file = load(folder)

        var records: [JevJobRecord] = []
        for finished in jobs {
            var record = finished.record
            if let output = finished.output {
                do {
                    try Self.check(output, for: capture)
                    for extra in output.files {
                        try extra.data.write(to: folder.appendingPathComponent(extra.name), options: .atomic)
                    }
                    record.lines = output.lines.map(JevLineRecord.init)
                    record.files = output.files.map(\.name)
                } catch {
                    record.status = .notRefined
                    record.reason = .jobError
                    record.lines = []
                    record.files = []
                }
            }
            records.append(record)
        }

        if let position = file.captures.firstIndex(where: { $0.capture == capture.index }) {
            var existing = file.captures[position].jobs
            for record in records {
                existing.removeAll { $0.job == record.job }
                existing.append(record)
            }
            file.captures[position].jobs = existing
        } else {
            file.captures.append(JevCaptureRecord(capture: capture.index, jobs: records))
            file.captures.sort { $0.capture < $1.capture }
        }
        try save(file, in: folder)

        let path = folder.path
        let captureRecord = file.captures.first { $0.capture == capture.index }
        if let text = JevRefinedRenderer.capture(capture, record: captureRecord, folderPath: path, jobOrder: jobOrder) {
            try Data(text.utf8).write(to: folder.appendingPathComponent(JevRefinedRenderer.captureFileName(for: capture)), options: .atomic)
        }
        try writeRound(round, file: file, folder: folder, running: [])
    }

    /// Renders refined.md with the captures still running marked, when the
    /// round prompt is copied.
    func settle(folderName: String, running: Set<Int>) throws {
        let folder = rootURL.appendingPathComponent(folderName, isDirectory: true)
        guard let round = FeedbackLibrary.round(named: folderName, in: rootURL) else { return }
        try writeRound(round, file: load(folder), folder: folder, running: running)
    }

    private func writeRound(_ round: FeedbackRound, file: JevRecordFile, folder: URL, running: Set<Int>) throws {
        guard let text = JevRefinedRenderer.round(round, file: file, folderPath: folder.path, jobOrder: jobOrder, running: running) else { return }
        try Data(text.utf8).write(to: folder.appendingPathComponent(JevRefinedRenderer.refinedRoundFileName), options: .atomic)
    }

    /// The bundle's jev.json, or a new one. A file this build cannot read is
    /// replaced: it holds only Jev results, never Drew's words.
    private func load(_ folder: URL) -> JevRecordFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(JevRecordFile.fileName)),
              let file = try? decoder.decode(JevRecordFile.self, from: data),
              file.schemaVersion == JevRecordFile.currentSchemaVersion
        else { return JevRecordFile() }
        return file
    }

    private func save(_ file: JevRecordFile, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(file).write(to: folder.appendingPathComponent(JevRecordFile.fileName), options: .atomic)
    }

    /// The bundle's own files. No job may write over one.
    static func reservedNames(for capture: FeedbackCapture) -> Set<String> {
        [
            "feedback.json", "manifest.md", "prompt.md", ".active.json",
            JevRecordFile.fileName, JevRefinedRenderer.refinedRoundFileName,
            capture.imageFile, capture.cleanImageFile, capture.promptFile,
            JevRefinedRenderer.captureFileName(for: capture),
        ]
    }

    /// A job's output must name only its own new files, and refer only to
    /// badges the capture has. Anything else is a bug in the job.
    static func check(_ output: JevJobOutput, for capture: FeedbackCapture) throws {
        let stem = JevRefinedRenderer.stem(of: capture)
        let reserved = reservedNames(for: capture)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        var names = Set<String>()
        for file in output.files {
            let name = file.name
            guard name.hasPrefix("\(stem)-"),
                  name.hasSuffix(".png") || name.hasSuffix(".md"),
                  name.count <= 120,
                  !name.contains(".."),
                  name.unicodeScalars.allSatisfy(allowed.contains),
                  !reserved.contains(name),
                  names.insert(name).inserted
            else { throw JevError(.jobError) }
        }
        let badges = capture.badgeNumbers
        for line in output.lines {
            if case .item(let badge) = line.scope, !badges.contains(badge) {
                throw JevError(.jobError)
            }
            if let file = line.file, !names.contains(file) {
                throw JevError(.jobError)
            }
        }
    }
}
