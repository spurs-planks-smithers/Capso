// Packages/FeedbackKit/Sources/FeedbackKit/FeedbackBasket.swift
import Foundation

/// One capture in a past session: the session folder name and the capture's
/// 1-based `index`. The store gives a capture the next free index and never
/// renumbers, so a key stays valid after a session is resumed.
public struct FeedbackBasketKey: Hashable, Sendable {
    public var folderName: String
    public var captureIndex: Int

    public init(folderName: String, captureIndex: Int) {
        self.folderName = folderName
        self.captureIndex = captureIndex
    }
}

/// The captures a user has checked in the Recent menu, across sessions. It
/// holds keys only. `FeedbackLibrary.entries(for:in:)` reads the sessions again
/// when the basket is copied, so the basket never holds stale data.
public struct FeedbackBasket: Equatable, Sendable {
    public private(set) var keys: Set<FeedbackBasketKey>

    public init() {
        keys = []
    }

    /// Adds the key, or removes it when it is already in the basket.
    public mutating func toggle(_ key: FeedbackBasketKey) {
        if keys.contains(key) {
            keys.remove(key)
        } else {
            keys.insert(key)
        }
    }

    public func contains(_ key: FeedbackBasketKey) -> Bool {
        keys.contains(key)
    }

    public var count: Int {
        keys.count
    }

    /// How many captures of one session are in the basket.
    public func count(inFolder folderName: String) -> Int {
        keys.reduce(0) { $0 + ($1.folderName == folderName ? 1 : 0) }
    }

    public mutating func removeAll() {
        keys.removeAll()
    }
}

/// A basket key resolved against its session folder.
public struct FeedbackSelectionEntry: Equatable, Sendable {
    public var session: FeedbackSession
    public var capture: FeedbackCapture
    /// The absolute path of the session folder that was read.
    public var folderPath: String

    public init(session: FeedbackSession, capture: FeedbackCapture, folderPath: String) {
        self.session = session
        self.capture = capture
        self.folderPath = folderPath
    }
}

extension FeedbackLibrary {
    /// Resolves each key of `basket` against the session folders under
    /// `rootURL`. Each folder is read once. `entries` are in capture-time
    /// order: ties go by folder, then capture index. `missing` holds the keys
    /// whose folder, `feedback.json`, or capture could not be found, sorted
    /// the same way by folder and capture index.
    public static func entries(
        for basket: FeedbackBasket,
        in rootURL: URL
    ) -> (entries: [FeedbackSelectionEntry], missing: [FeedbackBasketKey]) {
        var entries: [FeedbackSelectionEntry] = []
        var missing: [FeedbackBasketKey] = []

        for (folderName, keys) in Dictionary(grouping: basket.keys, by: \.folderName) {
            guard let session = session(named: folderName, in: rootURL) else {
                missing.append(contentsOf: keys)
                continue
            }
            let folderPath = rootURL.appendingPathComponent(folderName).path
            for key in keys {
                if let capture = session.captures.first(where: { $0.index == key.captureIndex }) {
                    entries.append(FeedbackSelectionEntry(session: session, capture: capture, folderPath: folderPath))
                } else {
                    missing.append(key)
                }
            }
        }

        // The folder path stands for the folder name here: every path shares
        // the root. It also stays unique when two folders hold equal copies of
        // a session, so the order never depends on set or dictionary order.
        entries.sort { lhs, rhs in
            if lhs.capture.capturedAt != rhs.capture.capturedAt {
                return lhs.capture.capturedAt < rhs.capture.capturedAt
            }
            if lhs.folderPath != rhs.folderPath {
                return lhs.folderPath < rhs.folderPath
            }
            return lhs.capture.index < rhs.capture.index
        }
        missing.sort { lhs, rhs in
            lhs.folderName != rhs.folderName
                ? lhs.folderName < rhs.folderName
                : lhs.captureIndex < rhs.captureIndex
        }
        return (entries, missing)
    }
}
