import Foundation
import Testing
@testable import FeedbackKit

@Suite("FeedbackBasket")
struct FeedbackBasketTests {
    private let root: URL
    private let fileManager = FileManager.default

    init() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("FeedbackBasketTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func key(_ folderName: String, _ captureIndex: Int) -> FeedbackBasketKey {
        FeedbackBasketKey(folderName: folderName, captureIndex: captureIndex)
    }

    private func capture(_ index: Int, at capturedAt: Date) -> FeedbackCapture {
        FeedbackCapture(
            index: index,
            imageFile: "capture-\(index).png",
            cleanImageFile: "capture-\(index)-clean.png",
            size: PixelSize(width: 800, height: 600),
            capturedAt: capturedAt
        )
    }

    /// Writes `root/<folderName>/feedback.json`, the way the store does.
    @discardableResult
    private func write(_ session: FeedbackSession) throws -> FeedbackSession {
        let folder = root.appendingPathComponent(session.folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(session).write(to: folder.appendingPathComponent("feedback.json"))
        return session
    }

    /// Session A started on the 20th. Its folder name sorts after B's, so a
    /// sort by folder name alone would put B first.
    private func sessionA() -> FeedbackSession {
        FeedbackSession(
            name: "pricing page",
            slug: "pricing-page",
            folderName: "2026-10-20-1912-pricing-page",
            startedAt: FeedbackFixtures.date(20, 19, 12),
            endedAt: FeedbackFixtures.date(20, 19, 30),
            captures: [
                FeedbackFixtures.pricingCapture(index: 1),
                FeedbackFixtures.pricingCapture(index: 2),
                FeedbackFixtures.pricingCapture(index: 3),
            ]
        )
    }

    /// Session B started on the 19th and was resumed on the 21st.
    private func sessionB() -> FeedbackSession {
        FeedbackSession(
            name: "checkout",
            slug: "checkout",
            folderName: "2026-10-19-0900-checkout",
            startedAt: FeedbackFixtures.date(19, 9, 0),
            endedAt: FeedbackFixtures.date(21, 16, 0),
            captures: [
                capture(1, at: FeedbackFixtures.date(19, 9, 5)),
                capture(2, at: FeedbackFixtures.date(21, 15, 43)),
            ]
        )
    }

    @Test("Toggling a key twice removes it")
    func togglesTwice() {
        var basket = FeedbackBasket()
        let k = key("A", 2)
        #expect(!basket.contains(k))

        basket.toggle(k)
        #expect(basket.contains(k))
        #expect(basket.count == 1)

        basket.toggle(k)
        #expect(!basket.contains(k))
        #expect(basket.count == 0)
        #expect(basket.keys.isEmpty)
    }

    @Test("Counts keys per session folder")
    func countsPerFolder() {
        var basket = FeedbackBasket()
        basket.toggle(key("A", 2))
        basket.toggle(key("A", 3))
        basket.toggle(key("B", 1))

        #expect(basket.count == 3)
        #expect(basket.count(inFolder: "A") == 2)
        #expect(basket.count(inFolder: "B") == 1)
        #expect(basket.count(inFolder: "C") == 0)
    }

    @Test("Removes every key")
    func removesAll() {
        var basket = FeedbackBasket()
        basket.toggle(key("A", 2))
        basket.toggle(key("B", 1))
        basket.removeAll()

        #expect(basket == FeedbackBasket())
        #expect(basket.count == 0)
    }

    @Test("Resolves keys across sessions in capture-time order")
    func resolvesInCaptureTimeOrder() throws {
        defer { try? fileManager.removeItem(at: root) }
        let a = try write(sessionA())
        let b = try write(sessionB())

        var basket = FeedbackBasket()
        basket.toggle(key(b.folderName, 2))
        basket.toggle(key(a.folderName, 2))

        let result = FeedbackLibrary.entries(for: basket, in: root)
        #expect(result.missing.isEmpty)
        #expect(result.entries.count == 2)
        #expect(result.entries.map(\.capture.capturedAt) == result.entries.map(\.capture.capturedAt).sorted())
        #expect(result.entries.first?.folderPath == root.appendingPathComponent(a.folderName).path)
        #expect(result.entries.first?.session == a)
        #expect(result.entries.first?.capture.index == 2)
        #expect(result.entries.last?.folderPath == root.appendingPathComponent(b.folderName).path)
        #expect(result.entries.last?.session == b)
        #expect(result.entries.last?.capture == b.captures[1])
    }

    @Test("Breaks a capture-time tie by folder name, then capture index")
    func breaksTies() throws {
        defer { try? fileManager.removeItem(at: root) }
        let moment = FeedbackFixtures.date(21, 10, 0)
        func session(_ folderName: String) -> FeedbackSession {
            FeedbackSession(
                name: folderName,
                slug: folderName,
                folderName: folderName,
                startedAt: moment,
                endedAt: moment,
                captures: [capture(1, at: moment), capture(2, at: moment)]
            )
        }
        try write(session("beta"))
        try write(session("alpha"))

        var basket = FeedbackBasket()
        for k in [key("beta", 1), key("alpha", 2), key("beta", 2), key("alpha", 1)] {
            basket.toggle(k)
        }

        let result = FeedbackLibrary.entries(for: basket, in: root)
        #expect(result.entries.map { "\($0.session.folderName)#\($0.capture.index)" } == [
            "alpha#1", "alpha#2", "beta#1", "beta#2",
        ])
    }

    @Test("Reports keys whose folder or capture is gone")
    func reportsMissing() throws {
        defer { try? fileManager.removeItem(at: root) }
        let a = try write(sessionA())

        var basket = FeedbackBasket()
        basket.toggle(key("deleted-folder", 1))
        basket.toggle(key(a.folderName, 99))
        basket.toggle(key(a.folderName, 1))

        let result = FeedbackLibrary.entries(for: basket, in: root)
        #expect(Set(result.missing) == [key("deleted-folder", 1), key(a.folderName, 99)])
        #expect(result.missing.count == 2)
        #expect(result.entries.map(\.capture.index) == [1])
        #expect(result.entries.first?.session == a)
    }

    @Test("Resolves an empty basket to nothing")
    func emptyBasket() {
        defer { try? fileManager.removeItem(at: root) }
        let result = FeedbackLibrary.entries(for: FeedbackBasket(), in: root)
        #expect(result.entries.isEmpty)
        #expect(result.missing.isEmpty)
    }
}
