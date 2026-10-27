import Foundation

/// Groups older rounds by their start dates, matching the dates on their rows.
public enum FeedbackHistory {
    public struct Group: Equatable, Sendable {
        public let title: String
        public let rounds: [FeedbackRound]
    }

    private enum Kind: Int, Hashable {
        case day, week, month
    }

    private struct Key: Hashable {
        let kind: Kind
        let start: Date
    }

    /// Seven local days, then the remaining dates in eight calendar weeks,
    /// then months. The supplied calendar controls time zone and week start.
    public static func groups(
        _ rounds: [FeedbackRound],
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [Group] {
        let today = calendar.startOfDay(for: now)
        let dayCutoff = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let weekCutoff = calendar.date(byAdding: .weekOfYear, value: -7, to: thisWeek) ?? thisWeek
        var buckets: [Key: [FeedbackRound]] = [:]

        for round in rounds where round.endedAt != nil && !round.captures.isEmpty {
            let day = calendar.startOfDay(for: round.startedAt)
            let key: Key
            if day >= dayCutoff {
                key = Key(kind: .day, start: day)
            } else if day >= weekCutoff {
                key = Key(kind: .week, start: calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day)
            } else {
                key = Key(kind: .month, start: calendar.dateInterval(of: .month, for: day)?.start ?? day)
            }
            buckets[key, default: []].append(round)
        }

        return buckets.keys.sorted {
            $0.start != $1.start ? $0.start > $1.start : $0.kind.rawValue < $1.kind.rawValue
        }.map { key in
            let rounds = (buckets[key] ?? []).sorted {
                $0.startedAt != $1.startedAt ? $0.startedAt > $1.startedAt : $0.folderName > $1.folderName
            }
            return Group(title: title(for: key, today: today, calendar: calendar, locale: locale), rounds: rounds)
        }
    }

    private static func title(for key: Key, today: Date, calendar: Calendar, locale: Locale) -> String {
        if key.kind == .day {
            if calendar.isDate(key.start, inSameDayAs: today) { return "Today" }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
               calendar.isDate(key.start, inSameDayAs: yesterday) { return "Yesterday" }
        }

        let sameYear = calendar.component(.year, from: key.start) == calendar.component(.year, from: today)
        let template: String
        switch key.kind {
        case .day: template = sameYear ? "EEEMMMd" : "EEEMMMdy"
        case .week: template = sameYear ? "MMMd" : "MMMdy"
        case .month: template = "MMMMy"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        let date = formatter.string(from: key.start)
        return key.kind == .week ? "Week of \(date)" : date
    }
}
