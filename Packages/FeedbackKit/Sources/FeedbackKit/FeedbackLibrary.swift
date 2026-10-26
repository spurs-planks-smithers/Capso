// Packages/FeedbackKit/Sources/FeedbackKit/FeedbackLibrary.swift
import Foundation

/// Reads past rounds from the store's root folder and words the menu rows
/// that list them. Read-only: it never writes to a round folder.
public enum FeedbackLibrary {
    /// The rounds found by `recent(in:)`.
    public struct Listing: Equatable, Sendable {
        /// Newest end first.
        public var rounds: [FeedbackRound]
        /// Folder names whose `feedback.json` could not be read or decoded.
        public var unreadable: [String]
        /// Folder names whose `feedback.json` has a newer `schemaVersion` than
        /// this copy knows. Another copy of Nextshot wrote them. This copy
        /// leaves them alone: loading one and saving it would drop the fields
        /// it does not know.
        public var newerSchema: [String]

        public init(rounds: [FeedbackRound], unreadable: [String], newerSchema: [String] = []) {
            self.rounds = rounds
            self.unreadable = unreadable
            self.newerSchema = newerSchema
        }
    }

    /// What a `feedback.json` holds, as far as this copy can tell.
    enum RoundRead: Equatable, Sendable {
        case round(FeedbackRound)
        /// Missing, not JSON, or not a round.
        case unreadable
        /// A round written under a newer schema than `FeedbackRound.currentSchemaVersion`.
        case newerSchema(Int)

        var round: FeedbackRound? {
            if case .round(let round) = self { return round }
            return nil
        }
    }

    /// Only the schema number, read before the whole round. A newer schema
    /// can change other fields, so the probe must not depend on them.
    private struct SchemaProbe: Decodable {
        var schemaVersion: Int?
    }

    /// Reads one `feedback.json`. A round with a newer schema is refused, even
    /// if it would decode: a copy that saved it again would lose the fields it
    /// does not know (`docs/decisions/2026-10-25-versioning-and-releases.md`).
    static func read(_ data: Data) -> RoundRead {
        let decoder = FeedbackRoundStore.decoder()
        if let version = (try? decoder.decode(SchemaProbe.self, from: data))?.schemaVersion,
           version > FeedbackRound.currentSchemaVersion {
            return .newerSchema(version)
        }
        guard let round = try? decoder.decode(FeedbackRound.self, from: data) else { return .unreadable }
        return .round(round)
    }

    static func read(file: URL) -> RoundRead {
        guard let data = try? Data(contentsOf: file) else { return .unreadable }
        return read(data)
    }

    /// Ended rounds that hold at least one capture, newest end first, at
    /// most `limit`. The active round has no end time, so it is left out.
    /// A folder with no `feedback.json` is not a round and is ignored. A
    /// folder whose `feedback.json` fails to decode is named in `unreadable`.
    /// A caller that lists often should keep a `FeedbackRoundCache` instead.
    public static func recent(in rootURL: URL, limit: Int = 5) -> Listing {
        var cache = FeedbackRoundCache()
        return cache.recent(in: rootURL, limit: limit)
    }

    /// One round by its folder name, or nil when the folder or its
    /// `feedback.json` is missing or unreadable. A name with a path separator
    /// is refused, so a name cannot point outside the root.
    public static func round(named folderName: String, in rootURL: URL) -> FeedbackRound? {
        guard !folderName.isEmpty, folderName != ".", folderName != "..", !folderName.contains("/") else { return nil }
        return load(rootURL
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(FeedbackRoundStore.roundFileName))
    }

    /// True when the round's `manifest.md` or `prompt.md` is missing or does
    /// not name the folder's current path, for example after the bundles moved
    /// from the old `CapsoFeedback` folder. False when the round itself
    /// does not load, because there is then nothing to rewrite them from.
    public static func bundleFilesNeedRepair(folderName: String, in rootURL: URL) -> Bool {
        guard round(named: folderName, in: rootURL) != nil else { return false }
        let folder = rootURL.appendingPathComponent(folderName, isDirectory: true)
        return [FeedbackRoundStore.manifestFileName, FeedbackRoundStore.promptFileName].contains { name in
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { return true }
            return !text.contains(folder.path)
        }
    }

    /// The round in a `feedback.json`, or nil when it is unreadable or has a
    /// newer schema.
    static func load(_ file: URL) -> FeedbackRound? {
        read(file: file).round
    }

    // MARK: - Row labels

    /// "Today, 6:27 AM", "Yesterday, 3:41 PM", or "Oct 20, 9:59 PM". The day is
    /// judged in `timeZone`.
    public static func title(startedAt: Date, now: Date, timeZone: TimeZone, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day: String
        if calendar.isDate(startedAt, inSameDayAs: now) {
            day = "Today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(startedAt, inSameDayAs: yesterday) {
            day = "Yesterday"
        } else {
            day = formatted(startedAt, template: "MMMd", timeZone: timeZone, locale: locale)
        }
        return "\(day), \(timeText(startedAt, timeZone: timeZone, locale: locale))"
    }

    /// Apps in capture order without repeats, then the capture count and, when
    /// some are picked, the selection count: "Preview, TextEdit, 5 captures, 2 selected".
    public static func subtitle(for round: FeedbackRound, selectedCount: Int) -> String {
        var apps: [String] = []
        for app in round.captures.compactMap(\.sourceApp) where !apps.contains(app) {
            apps.append(app)
        }
        let count = round.captures.count
        var parts = apps
        parts.append(count == 1 ? "1 capture" : "\(count) captures")
        if selectedCount > 0 {
            parts.append("\(selectedCount) selected")
        }
        return parts.joined(separator: ", ")
    }

    /// The round's captures for a menu list: the newest first. A tie in capture
    /// time keeps the higher index first. The round itself stays in capture order.
    public static func capturesNewestFirst(_ round: FeedbackRound) -> [FeedbackCapture] {
        round.captures.sorted {
            $0.capturedAt == $1.capturedAt ? $0.index > $1.index : $0.capturedAt > $1.capturedAt
        }
    }

    /// "3:43 PM <window title>". The app name stands in for a missing window
    /// title, and "Capture <index>" for a missing app.
    public static func captureRowTitle(_ capture: FeedbackCapture, timeZone: TimeZone, locale: Locale = .current) -> String {
        let label = [capture.windowTitle, capture.sourceApp]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ?? "Capture \(capture.index)"
        return "\(timeText(capture.capturedAt, timeZone: timeZone, locale: locale)) \(label)"
    }

    /// "No items", "1 item", or "4 items".
    public static func itemCountText(_ capture: FeedbackCapture) -> String {
        switch capture.badgeNumbers.count {
        case 0: return "No items"
        case 1: return "1 item"
        case let count: return "\(count) items"
        }
    }

    private static func timeText(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        formatted(date, template: "jmm", timeZone: timeZone, locale: locale)
    }

    /// macOS puts a narrow no-break space (U+202F) before AM and PM. A plain
    /// space keeps labels equal to plain text.
    private static func formatted(_ date: Date, template: String, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
