import Foundation
import Testing
@testable import FeedbackKit

@Suite("FeedbackSessionStore")
struct FeedbackSessionStoreTests {
    private let root: URL
    private let fileManager = FileManager.default

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("FeedbackKitTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func makeStore() -> FeedbackSessionStore {
        FeedbackSessionStore(rootURL: root, timeZone: FeedbackFixtures.timeZone, now: { FeedbackFixtures.date(20, 19, 12) })
    }

    private func input(badges: [Int] = [1, 2]) -> FeedbackCaptureInput {
        FeedbackCaptureInput(
            annotatedPNG: Data("annotated".utf8),
            cleanPNG: Data("clean".utf8),
            size: PixelSize(width: 800, height: 600),
            sourceApp: "Safari",
            windowTitle: "Pricing | Acme",
            ocrText: "Starter $19/mo",
            marks: badges.map { number in
                FeedbackMark(kind: .counter, badge: number, box: FeedbackBox(x1: number * 100, y1: 10, x2: number * 100 + 24, y2: 34))
            }
        )
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("Starts a session in a dated folder named after the slug")
    func startCreatesFolder() async throws {
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore()
        let session = try await store.start(name: "Pricing Page")

        #expect(session.folderName == "2026-10-20-1912-pricing-page")
        #expect(await store.activeSession?.name == "Pricing Page")
        for file in ["feedback.json", "manifest.md", "prompt.md"] {
            #expect(fileManager.fileExists(atPath: root.appendingPathComponent("\(session.folderName)/\(file)").path))
        }
    }

    @Test("Refuses to start a second session while one is active")
    func refusesSecondSession() async throws {
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore()
        try await store.start(name: "first")
        await #expect(throws: FeedbackSessionStore.StoreError.sessionAlreadyActive) {
            try await store.start(name: "second")
        }
    }

    @Test("Adds a numeric suffix when the folder already exists")
    func folderCollision() async throws {
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root.appendingPathComponent("2026-10-20-1912-feedback"), withIntermediateDirectories: true)
        let session = try await makeStore().start(name: "feedback")
        #expect(session.folderName == "2026-10-20-1912-feedback-2")
    }

    @Test("Numbers captures and writes both PNG files")
    func numbersCaptures() async throws {
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore()
        let session = try await store.start(name: "feedback")
        let first = try await store.addCapture(input())
        let second = try await store.addCapture(input())

        #expect(first.index == 1)
        #expect(second.index == 2)
        #expect(second.imageFile == "002.png")
        let folder = root.appendingPathComponent(session.folderName)
        #expect(try Data(contentsOf: folder.appendingPathComponent("001.png")) == Data("annotated".utf8))
        #expect(try Data(contentsOf: folder.appendingPathComponent("001-clean.png")) == Data("clean".utf8))
        #expect(fileManager.fileExists(atPath: folder.appendingPathComponent("002-clean.png").path))
    }

    @Test("Throws when no session is active")
    func addWithoutSession() async throws {
        defer { try? fileManager.removeItem(at: root) }
        await #expect(throws: FeedbackSessionStore.StoreError.noActiveSession) {
            try await makeStore().addCapture(input())
        }
    }

    @Test("Applies badge instructions from the note and rewrites the manifest")
    func noteSetsInstructions() async throws {
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore()
        let session = try await store.start(name: "feedback")
        try await store.addCapture(input())
        try await store.updateNote(capture: 1, text: "1: fix price")

        let capture = try #require(await store.activeSession?.captures.first)
        #expect(capture.marks.map(\.instruction) == ["fix price", nil])
        #expect(capture.note == nil)
        let manifest = try text("\(session.folderName)/manifest.md")
        #expect(manifest.contains("| 1.1 | badge (112, 22) | n/a | fix price |"))
        #expect(manifest.contains("| 1.2 | badge (212, 22) | n/a | n/a (no instruction: ask) |"))
    }

    @Test("Replaces earlier instructions when the note changes")
    func noteReplacesInstructions() async throws {
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore()
        try await store.start(name: "feedback")
        try await store.addCapture(input())
        try await store.updateNote(capture: 1, text: "1: fix price")
        try await store.updateNote(capture: 1, text: "2: bold; cards feel cramped")

        let capture = try #require(await store.activeSession?.captures.first)
        #expect(capture.marks.map(\.instruction) == [nil, "bold"])
        #expect(capture.note == "cards feel cramped")
    }

    @Test("Throws for a capture that does not exist")
    func unknownCapture() async throws {
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore()
        try await store.start(name: "feedback")
        await #expect(throws: FeedbackSessionStore.StoreError.captureNotFound(5)) {
            try await store.updateNote(capture: 5, text: "x")
        }
    }

    @Test("Resumes the active session after a restart")
    func resumes() async throws {
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore()
        try await store.start(name: "feedback")
        try await store.addCapture(input())
        try await store.updateNote(capture: 1, text: "1: fix price")
        let before = await store.activeSession

        let restarted = makeStore()
        #expect(await restarted.activeSession == before)
        #expect(await restarted.activeSession?.captures.count == 1)
    }

    @Test("Ends the session and clears the active marker")
    func endsSession() async throws {
        defer { try? fileManager.removeItem(at: root) }
        let store = makeStore()
        let session = try await store.start(name: "feedback")
        let ended = try await store.end()

        #expect(ended.endedAt == FeedbackFixtures.date(20, 19, 12))
        #expect(await store.activeSession == nil)
        #expect(!fileManager.fileExists(atPath: root.appendingPathComponent(".active.json").path))
        #expect(await makeStore().activeSession == nil)
        #expect(try text("\(session.folderName)/manifest.md").contains("Ended: 2026-10-20 19:12 PDT"))
    }

    @Test("Writes feedback.json with schemaVersion 1")
    func schemaVersion() async throws {
        defer { try? fileManager.removeItem(at: root) }
        let session = try await makeStore().start(name: "feedback")
        let data = try Data(contentsOf: root.appendingPathComponent("\(session.folderName)/feedback.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
    }
}
