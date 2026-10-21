// Packages/FeedbackKit/Sources/FeedbackKit/FeedbackSessionStore.swift
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

/// Owns the active feedback session and its folder on disk.
///
/// Every change rewrites `feedback.json`, `manifest.md`, and `prompt.md`.
/// `<root>/.active.json` names the active session's folder, so a new store
/// on the same root resumes that session after a relaunch.
public actor FeedbackSessionStore {
    public enum StoreError: Error, Equatable {
        case sessionAlreadyActive
        case noActiveSession
        case captureNotFound(Int)
        case badgeNotFound(Int)
    }

    private struct ActiveMarker: Codable {
        var folderName: String
    }

    static let activeMarkerName = ".active.json"
    static let sessionFileName = "feedback.json"
    static let manifestFileName = "manifest.md"
    static let promptFileName = "prompt.md"

    public nonisolated let rootURL: URL
    public nonisolated let timeZone: TimeZone
    private let now: @Sendable () -> Date
    public private(set) var activeSession: FeedbackSession?

    public init(rootURL: URL, timeZone: TimeZone = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.rootURL = rootURL
        self.timeZone = timeZone
        self.now = now
        self.activeSession = Self.loadActiveSession(rootURL: rootURL)
    }

    public var activeFolderURL: URL? {
        activeSession.map(folderURL(for:))
    }

    @discardableResult
    public func start(name: String) throws -> FeedbackSession {
        guard activeSession == nil else { throw StoreError.sessionAlreadyActive }

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

        let session = FeedbackSession(name: displayName, slug: slug, folderName: folderName, startedAt: startedAt)
        try FileManager.default.createDirectory(at: folderURL(for: session), withIntermediateDirectories: true)
        try write(session)
        try Self.encoder().encode(ActiveMarker(folderName: folderName))
            .write(to: rootURL.appendingPathComponent(Self.activeMarkerName), options: .atomic)
        activeSession = session
        return session
    }

    /// The active session, or a new one when none is active. One actor call,
    /// so two quick requests cannot both try to start a session.
    @discardableResult
    public func startIfNeeded(name: String) throws -> FeedbackSession {
        if let activeSession {
            return activeSession
        }
        return try start(name: name)
    }

    @discardableResult
    public func addCapture(_ input: FeedbackCaptureInput) throws -> FeedbackCapture {
        guard var session = activeSession else { throw StoreError.noActiveSession }

        let index = (session.captures.map(\.index).max() ?? 0) + 1
        let capturedAt = input.capturedAt ?? now()
        let folder = folderURL(for: session)
        // Files are named by time and window title. A stem is taken when either
        // of its two files would match any existing file, so a window titled
        // "Foo Clean" and a window titled "Foo" never overwrite each other.
        let usedNames = Set(session.captures.flatMap { [$0.imageFile, $0.cleanImageFile] })
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
        session.captures.append(capture)
        try write(session)
        activeSession = session
        return capture
    }

    /// Replaces the capture's note. Badge instructions come from the new text
    /// only, so an instruction removed from the note is removed from its badge.
    public func updateNote(capture index: Int, text: String) throws {
        guard var session = activeSession else { throw StoreError.noActiveSession }
        guard let position = session.captures.firstIndex(where: { $0.index == index }) else {
            throw StoreError.captureNotFound(index)
        }

        var capture = session.captures[position]
        let parsed = NoteParser.parse(text, badges: capture.badgeNumbers)
        capture.note = parsed.note
        for markIndex in capture.marks.indices where capture.marks[markIndex].kind == .counter {
            capture.marks[markIndex].instruction = capture.marks[markIndex].badge.flatMap { parsed.instructions[$0] }
        }
        session.captures[position] = capture
        try write(session)
        activeSession = session
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

    private func updateCapture(_ index: Int, _ change: (inout FeedbackCapture) throws -> Void) throws {
        guard var session = activeSession else { throw StoreError.noActiveSession }
        guard let position = session.captures.firstIndex(where: { $0.index == index }) else {
            throw StoreError.captureNotFound(index)
        }
        try change(&session.captures[position])
        try write(session)
        activeSession = session
    }

    @discardableResult
    public func end() throws -> FeedbackSession {
        guard var session = activeSession else { throw StoreError.noActiveSession }

        session.endedAt = now()
        try write(session)
        let marker = rootURL.appendingPathComponent(Self.activeMarkerName)
        if FileManager.default.fileExists(atPath: marker.path) {
            try FileManager.default.removeItem(at: marker)
        }
        activeSession = nil
        return session
    }

    private func folderURL(for session: FeedbackSession) -> URL {
        rootURL.appendingPathComponent(session.folderName, isDirectory: true)
    }

    private func write(_ session: FeedbackSession) throws {
        let folder = folderURL(for: session)
        let manifest = ManifestWriter.render(session, folderPath: folder.path, timeZone: timeZone)
        let prompt = PromptBuilder.render(session, folderPath: folder.path)
        try Self.encoder().encode(session).write(to: folder.appendingPathComponent(Self.sessionFileName), options: .atomic)
        try Data(manifest.utf8).write(to: folder.appendingPathComponent(Self.manifestFileName), options: .atomic)
        try Data(prompt.utf8).write(to: folder.appendingPathComponent(Self.promptFileName), options: .atomic)
    }

    /// The session named by `.active.json`, or nil when there is none or it
    /// cannot be read. A bad marker must not block the app from starting.
    private static func loadActiveSession(rootURL: URL) -> FeedbackSession? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard
            let markerData = try? Data(contentsOf: rootURL.appendingPathComponent(activeMarkerName)),
            let marker = try? decoder.decode(ActiveMarker.self, from: markerData),
            let sessionData = try? Data(contentsOf: rootURL
                .appendingPathComponent(marker.folderName, isDirectory: true)
                .appendingPathComponent(sessionFileName)),
            let session = try? decoder.decode(FeedbackSession.self, from: sessionData),
            session.endedAt == nil
        else { return nil }
        return session
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
