import Foundation

/// Retention compares completed screenshot versions. Round references cannot be removed here.
enum ScreenshotRetention {
    static let limit = 100

    static func expired(in items: [ScreenshotHistoryItem], keeping limit: Int) -> [UUID] {
        let local = items.filter {
            if case .local = $0.id { return true }
            return false
        }
        return local.sorted(by: newestFirst).dropFirst(max(0, limit)).compactMap {
            guard case .local(let id) = $0.id else { return nil }
            return id
        }
    }

    static func newestFirst(_ lhs: ScreenshotHistoryItem, _ rhs: ScreenshotHistoryItem) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.sortKey < rhs.id.sortKey
    }
}
