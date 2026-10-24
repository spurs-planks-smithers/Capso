// Packages/FeedbackKit/Sources/FeedbackKit/FeedbackRoundStore.swift
import Foundation

/// The PNG data and marks for one capture, already sized for export.
/// Coordinates in `marks` are pixels of the exported PNG.
public struct FeedbackCaptureInput: Sendable {
    public var annotatedPNG: Data
    public var cleanPNG: Data
    public var size: PixelSize
    /// When the screen was captured. Nil means the time `addCapture` runs.
    public var capturedAt: Date?
    public var sourceApp: String?
    public var windowTitle: String?
    public var ocrText: String?
    public var marks: [FeedbackMark]

    public init(
        annotatedPNG: Data,
        cleanPNG: Data,
        size: PixelSize,
        capturedAt: Date? = nil,
        sourceApp: String? = nil,
        windowTitle: String? = nil,
        ocrText: String? = nil,
        marks: [FeedbackMark] = []
    ) {
        self.annotatedPNG = annotatedPNG
        self.cleanPNG = cleanPNG
        self.size = size
        self.capturedAt = capturedAt
        self.sourceApp = sourceApp
        self.windowTitle = windowTitle
        self.ocrText = ocrText
        self.marks = marks
    }
}

/// Owns the active feedback round and its folder on disk.
///
/// Every change rewrites `feedback.json`, `manifest.md`, and `prompt.md`.
/// `<root>/.active.json` names the active round's folder, so a new store
/// on the same root resumes that round after a relaunch.
public actor FeedbackRoundStore {
    public enum StoreError: Error, Equatable {
        case roundAlreadyActive
        case noActiveRound
        case captureNotFound(Int)
        case badgeNotFound(Int)
        case markCountMismatch
        case roundNotFound(String)
    }

    private struct ActiveMarker: Codable {
        var folderName: String
    }

    static let activeMarkerName = ".active.json"
    static let roundFileName = "feedback.json"
    static let manifestFileName = "manifest.md"
    static let promptFileName = "prompt.md"

    public nonisolated let rootURL: URL
    public nonisolated let timeZone: TimeZone
    private let now: @Sendable () -> Date
    public private(set) var activeRound: FeedbackRound?

    public init(rootURL: URL, timeZone: TimeZone = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.rootURL = rootURL
        self.timeZone = timeZone
        self.now = now
        self.activeRound = Self.loadActiveRound(rootURL: rootURL)
    }

    public var activeFolderURL: URL? {
        activeRound.map(folderURL(for:))
    }

    @discardableResult
    public func start(name: String) throws -> FeedbackRound {
        guard activeRound == nil else { throw StoreError.roundAlreadyActive }

        // A Shortcuts input can carry any text, so the name gets the same
        // cleaning as screen text and stays on one line.
        let displayName = ScreenText.field(name, maxScalars: ScreenText.maxNameLength)?
            .trimmingCharacters(in: .whitespaces) ?? FeedbackNaming.defaultSlug
        let slug = FeedbackNaming.slug(from: displayName)
        let startedAt = now()
        let base = FeedbackNaming.folderName(startedAt: startedAt, slug: slug, timeZone: timeZone)
        let rootURL = rootURL
        let folderName = FeedbackNaming.uniqueName(base) {
            FileManager.default.fileExists(atPath: rootURL.appendingPathComponent($0).path)
        }

        let round = FeedbackRound(name: displayName, slug: slug, folderName: folderName, startedAt: startedAt)
        try FileManager.default.createDirectory(at: folderURL(for: round), withIntermediateDirectories: true)
        try write(round)
        try writeActiveMarker(folderName: folderName)
        activeRound = round
        return round
    }

    /// Reopens an ended round, so new captures continue its numbering. The
    /// bundle files are rewritten, so the paths in them name the current folder.
    @discardableResult
    public func resume(folderName: String) throws -> FeedbackRound {
        guard activeRound == nil else { throw StoreError.roundAlreadyActive }
        guard var round = FeedbackLibrary.round(named: folderName, in: rootURL) else {
            throw StoreError.roundNotFound(folderName)
        }

        // The folder that was read is the one to write back to, even if the
        // folder name saved inside feedback.json is out of date.
        round.folderName = folderName
        round.endedAt = nil
        try write(round)
        try writeActiveMarker(folderName: folderName)
        activeRound = round
        return round
    }

    /// Rewrites the bundle files of a round on disk, so the paths in them
    /// name the current folder. It changes no round field except
    /// `folderName`, which becomes the directory name. The active round is
    /// written from memory, so a repair never reverts a newer change. It never
    /// changes `activeRound` or `.active.json`.
    public func repairBundleFiles(folderName: String) throws {
        guard var round = FeedbackLibrary.round(named: folderName, in: rootURL) else {
            throw StoreError.roundNotFound(folderName)
        }
        if let activeRound, activeRound.folderName == folderName {
            try write(activeRound)
            return
        }
        round.folderName = folderName
        try write(round)
    }

    /// The active round, or a new one when none is active. One actor call,
    /// so two quick requests cannot both try to start a round.
    @discardableResult
    public func startIfNeeded(name: String) throws -> FeedbackRound {
        if let activeRound {
            return activeRound
        }
        return try start(name: name)
    }

    @discardableResult
    public func addCapture(_ input: FeedbackCaptureInput) throws -> FeedbackCapture {
        guard var round = activeRound else { throw StoreError.noActiveRound }

        let index = (round.captures.map(\.index).max() ?? 0) + 1
        let capturedAt = input.capturedAt ?? now()
        let folder = folderURL(for: round)
        // Files are named by time and window title. A stem is taken when either
        // of its two files would match any existing file, so a window titled
        // "Foo Clean" and a window titled "Foo" never overwrite each other.
        let usedNames = Set(round.captures.flatMap { [$0.imageFile, $0.cleanImageFile] })
        let stem = FeedbackNaming.uniqueName(FeedbackNaming.captureFileStem(
            windowTitle: input.windowTitle,
            sourceApp: input.sourceApp,
            capturedAt: capturedAt,
            timeZone: timeZone
        )) { candidate in
            ["\(candidate).png", "\(candidate)-clean.png"].contains { name in
                usedNames.contains(name)
                    || FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
            }
        }
        let capture = FeedbackCapture(
            index: index,
            imageFile: "\(stem).png",
            cleanImageFile: "\(stem)-clean.png",
            size: input.size,
            capturedAt: capturedAt,
            // Screen text is cleaned once here, so every bundle file gets clean text.
            sourceApp: ScreenText.field(input.sourceApp),
            windowTitle: ScreenText.field(input.windowTitle),
            ocrText: ScreenText.field(input.ocrText, singleLine: false, maxScalars: ScreenText.maxBlockLength),
            marks: input.marks.map { mark in
                var mark = mark
                mark.ocrText = ScreenText.field(mark.ocrText)
                return mark
            }
        )

        try input.annotatedPNG.write(to: folder.appendingPathComponent(capture.imageFile), options: .atomic)
        try input.cleanPNG.write(to: folder.appendingPathComponent(capture.cleanImageFile), options: .atomic)
        round.captures.append(capture)
        try write(round)
        activeRound = round
        return capture
    }

    /// Replaces the capture's note. Badge instructions come from the new text
    /// only, so an instruction removed from the note is removed from its badge.
    public func updateNote(capture index: Int, text: String) throws {
        guard var round = activeRound else { throw StoreError.noActiveRound }
        guard let position = round.captures.firstIndex(where: { $0.index == index }) else {
            throw StoreError.captureNotFound(index)
        }

        var capture = round.captures[position]
        let parsed = NoteParser.parse(text, badges: capture.badgeNumbers)
        capture.note = parsed.note
        for markIndex in capture.marks.indices where capture.marks[markIndex].kind == .counter {
            capture.marks[markIndex].instruction = capture.marks[markIndex].badge.flatMap { parsed.instructions[$0] }
        }
        round.captures[position] = capture
        try write(round)
        activeRound = round
    }

    /// Sets one circle's instruction as written. Blank text clears it. Other
    /// circles keep their instructions.
    public func setInstruction(capture index: Int, badge: Int, text: String) throws {
        try updateCapture(index) { capture in
            let targets = capture.marks.indices.filter { capture.marks[$0].kind == .counter && capture.marks[$0].badge == badge }
            guard !targets.isEmpty else { throw StoreError.badgeNotFound(badge) }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            for target in targets {
                capture.marks[target].instruction = trimmed.isEmpty ? nil : trimmed
            }
        }
    }

    /// Sets the capture's general note as written. Blank text clears it.
    /// Circle instructions stay as they are.
    public func setNote(capture index: Int, text: String) throws {
        try updateCapture(index) { capture in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            capture.note = trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Sets the screen text that OCR finds after the capture is stored. Entry
    /// N of `markTexts` belongs to mark N. The text gets the same cleaning as
    /// in `addCapture`. Instructions and the note stay as they are.
    public func setScreenText(capture index: Int, ocrText: String?, markTexts: [String?]) throws {
        try updateCapture(index) { capture in
            guard markTexts.count == capture.marks.count else { throw StoreError.markCountMismatch }
            capture.ocrText = ScreenText.field(ocrText, singleLine: false, maxScalars: ScreenText.maxBlockLength)
            for position in capture.marks.indices {
                capture.marks[position].ocrText = ScreenText.field(markTexts[position])
            }
        }
    }

    private func updateCapture(_ index: Int, _ change: (inout FeedbackCapture) throws -> Void) throws {
        guard var round = activeRound else { throw StoreError.noActiveRound }
        guard let position = round.captures.firstIndex(where: { $0.index == index }) else {
            throw StoreError.captureNotFound(index)
        }
        try change(&round.captures[position])
        try write(round)
        activeRound = round
    }

    @discardableResult
    public func end() throws -> FeedbackRound {
        guard var round = activeRound else { throw StoreError.noActiveRound }

        round.endedAt = now()
        try write(round)
        let marker = rootURL.appendingPathComponent(Self.activeMarkerName)
        if FileManager.default.fileExists(atPath: marker.path) {
            try FileManager.default.removeItem(at: marker)
        }
        activeRound = nil
        return round
    }

    private func folderURL(for round: FeedbackRound) -> URL {
        rootURL.appendingPathComponent(round.folderName, isDirectory: true)
    }

    private func writeActiveMarker(folderName: String) throws {
        try Self.encoder().encode(ActiveMarker(folderName: folderName))
            .write(to: rootURL.appendingPathComponent(Self.activeMarkerName), options: .atomic)
    }

    private func write(_ round: FeedbackRound) throws {
        let folder = folderURL(for: round)
        let manifest = ManifestWriter.render(round, folderPath: folder.path, timeZone: timeZone)
        let prompt = PromptBuilder.render(round, folderPath: folder.path)
        try Self.encoder().encode(round).write(to: folder.appendingPathComponent(Self.roundFileName), options: .atomic)
        try Data(manifest.utf8).write(to: folder.appendingPathComponent(Self.manifestFileName), options: .atomic)
        try Data(prompt.utf8).write(to: folder.appendingPathComponent(Self.promptFileName), options: .atomic)
        // Each capture's own prompt, so it can be pasted again after the
        // clipboard changes (dictation tools paste through the clipboard).
        // A copy for convenience: a failed write here must not fail the save,
        // because feedback.json above already holds the change.
        for capture in round.captures {
            let capturePrompt = PromptBuilder.renderCapture(capture, folderPath: folder.path)
            try? Data(capturePrompt.utf8).write(to: folder.appendingPathComponent(capture.promptFile), options: .atomic)
        }
    }

    /// The round named by `.active.json`, or nil when there is none or it
    /// cannot be read. A bad marker must not block the app from starting.
    private static func loadActiveRound(rootURL: URL) -> FeedbackRound? {
        let decoder = Self.decoder()
        guard
            let markerData = try? Data(contentsOf: rootURL.appendingPathComponent(activeMarkerName)),
            let marker = try? decoder.decode(ActiveMarker.self, from: markerData),
            let roundData = try? Data(contentsOf: rootURL
                .appendingPathComponent(marker.folderName, isDirectory: true)
                .appendingPathComponent(roundFileName)),
            let round = try? decoder.decode(FeedbackRound.self, from: roundData),
            round.endedAt == nil
        else { return nil }
        return round
    }

    /// Reads `feedback.json` and `.active.json`. `FeedbackLibrary` uses it too.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
