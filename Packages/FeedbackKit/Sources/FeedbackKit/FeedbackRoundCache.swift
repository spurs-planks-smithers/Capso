// Packages/FeedbackKit/Sources/FeedbackKit/FeedbackRoundCache.swift
import Foundation

/// Lists recent rounds like `FeedbackLibrary.recent(in:)`, and keeps each
/// decoded `feedback.json` between calls. A file is decoded again only when
/// its modification date or size differs from the last read, so a menu that
/// lists rounds on every open does not decode them all each time.
///
/// A change that keeps both the size and the modification date goes unseen.
/// The store always writes a whole new file, so its changes move the date.
public struct FeedbackRoundCache: Sendable {
    private struct Stamp: Equatable, Sendable {
        var modified: Date
        var size: Int64
    }

    private struct Entry: Sendable {
        var stamp: Stamp
        var read: FeedbackLibrary.RoundRead
    }

    private var rootURL: URL?
    /// Keyed by folder name.
    private var entries: [String: Entry] = [:]

    public init() {}

    /// The same rules as `FeedbackLibrary.recent(in:limit:)`: ended rounds
    /// that hold at least one capture, newest end first, at most `limit`. The
    /// active round has no end time, so it is left out. A folder with no
    /// `feedback.json` is not a round and is ignored. A folder whose
    /// `feedback.json` fails to decode is named in `unreadable`.
    public mutating func recent(in rootURL: URL, limit: Int = 5) -> FeedbackLibrary.Listing {
        // Folder names repeat across roots, so entries never carry over.
        if self.rootURL != rootURL {
            self.rootURL = rootURL
            entries = [:]
        }

        let fileManager = FileManager.default
        let folders = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []

        var kept: [String: Entry] = [:]
        var rounds: [FeedbackRound] = []
        var unreadable: [String] = []
        var newerSchema: [String] = []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let file = folder.appendingPathComponent(FeedbackRoundStore.roundFileName)
            guard fileManager.fileExists(atPath: file.path) else { continue }

            // The stamp is read before the file, so a write between the two
            // reads leaves an old stamp and the next call decodes again.
            let name = folder.lastPathComponent
            let stamp = Self.stamp(of: file)
            let read: FeedbackLibrary.RoundRead
            if let stamp, let cached = entries[name], cached.stamp == stamp {
                read = cached.read
                kept[name] = cached
            } else {
                read = FeedbackLibrary.read(file: file)
                if let stamp {
                    kept[name] = Entry(stamp: stamp, read: read)
                }
            }

            let round: FeedbackRound
            switch read {
            case .round(let decoded):
                round = decoded
            case .unreadable:
                unreadable.append(name)
                continue
            case .newerSchema:
                newerSchema.append(name)
                continue
            }
            if round.endedAt != nil, !round.captures.isEmpty {
                rounds.append(round)
            }
        }
        // Entries of folders that are gone are not carried forward.
        entries = kept

        // Every kept round has an end time. The folder name breaks a tie, so
        // the order never depends on directory order.
        rounds.sort { lhs, rhs in
            let lhsEnd = lhs.endedAt ?? .distantPast
            let rhsEnd = rhs.endedAt ?? .distantPast
            return lhsEnd != rhsEnd ? lhsEnd > rhsEnd : lhs.folderName > rhs.folderName
        }
        return FeedbackLibrary.Listing(
            rounds: Array(rounds.prefix(max(limit, 0))),
            unreadable: unreadable.sorted(),
            newerSchema: newerSchema.sorted()
        )
    }

    /// Nil when the file's date or size cannot be read. The file is then
    /// decoded on every call.
    private static func stamp(of file: URL) -> Stamp? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
            let modified = attributes[.modificationDate] as? Date,
            let size = (attributes[.size] as? NSNumber)?.int64Value
        else { return nil }
        return Stamp(modified: modified, size: size)
    }
}
