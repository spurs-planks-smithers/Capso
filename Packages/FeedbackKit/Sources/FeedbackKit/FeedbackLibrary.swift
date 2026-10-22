// Packages/FeedbackKit/Sources/FeedbackKit/FeedbackLibrary.swift
import Foundation

/// Reads past sessions from the store's root folder and words the menu rows
/// that list them. Read-only: it never writes to a session folder.
public enum FeedbackLibrary {
    /// The sessions found by `recent(in:)`.
    public struct Listing: Equatable, Sendable {
        /// Newest end first.
        public var sessions: [FeedbackSession]
        /// Folder names whose `feedback.json` could not be read or decoded.
        public var unreadable: [String]

        public init(sessions: [FeedbackSession], unreadable: [String]) {
            self.sessions = sessions
            self.unreadable = unreadable
        }
    }

    /// Ended sessions that hold at least one capture, newest end first, at
    /// most `limit`. The active session has no end time, so it is left out.
    /// A folder with no `feedback.json` is not a session and is ignored. A
    /// folder whose `feedback.json` fails to decode is named in `unreadable`.
    /// A caller that lists often should keep a `FeedbackSessionCache` instead.
    public static func recent(in rootURL: URL, limit: Int = 5) -> Listing {
        var cache = FeedbackSessionCache()
        return cache.recent(in: rootURL, limit: limit)
    }

    /// One session by its folder name, or nil when the folder or its
    /// `feedback.json` is missing or unreadable. A name with a path separator
    /// is refused, so a name cannot point outside the root.
    public static func session(named folderName: String, in rootURL: URL) -> FeedbackSession? {
        guard !folderName.isEmpty, folderName != ".", folderName != "..", !folderName.contains("/") else { return nil }
        return load(rootURL
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(FeedbackSessionStore.sessionFileName))
    }

    /// True when the session's `manifest.md` or `prompt.md` is missing or does
    /// not name the folder's current path, for example after the bundles moved
    /// from the old `CapsoFeedback` folder. False when the session itself
    /// does not load, because there is then nothing to rewrite them from.
    public static func bundleFilesNeedRepair(folderName: String, in rootURL: URL) -> Bool {
        guard session(named: folderName, in: rootURL) != nil else { return false }
        let folder = rootURL.appendingPathComponent(folderName, isDirectory: true)
        return [FeedbackSessionStore.manifestFileName, FeedbackSessionStore.promptFileName].contains { name in
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { return true }
            return !text.contains(folder.path)
        }
    }

    static func load(_ file: URL) -> FeedbackSession? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? FeedbackSessionStore.decoder().decode(FeedbackSession.self, from: data)
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
    public static func subtitle(for session: FeedbackSession, selectedCount: Int) -> String {
        var apps: [String] = []
        for app in session.captures.compactMap(\.sourceApp) where !apps.contains(app) {
            apps.append(app)
        }
        let count = session.captures.count
        var parts = apps
        parts.append(count == 1 ? "1 capture" : "\(count) captures")
        if selectedCount > 0 {
            parts.append("\(selectedCount) selected")
        }
        return parts.joined(separator: ", ")
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
