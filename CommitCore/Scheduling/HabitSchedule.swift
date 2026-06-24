import Foundation

/// The kind of schedule a habit follows. Used as the persisted discriminator.
public enum ScheduleKind: String, CaseIterable, Codable, Sendable {
    case daily
    case weekdays
    case timesPerWeek
}

/// Strongly-typed schedule for a habit.
public enum Schedule: Equatable, Hashable, Sendable {
    /// Every day.
    case daily
    /// Specific weekdays. 1 = Sunday … 7 = Saturday (matches `Calendar.component(.weekday:)`).
    case weekdays(Set<Int>)
    /// Any `n` days within a calendar week.
    case timesPerWeek(Int)

    public var kind: ScheduleKind {
        switch self {
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .timesPerWeek: return .timesPerWeek
        }
    }

    /// Whether the habit is "due"/eligible on `date`.
    ///
    /// `timesPerWeek` habits can be done on any day until the weekly target is met,
    /// so they are considered scheduled every day.
    public func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily:
            return true
        case .weekdays(let days):
            return days.contains(calendar.component(.weekday, from: date))
        case .timesPerWeek:
            return true
        }
    }

    /// Short, human-readable summary, e.g. "Daily", "Mon, Wed, Fri", "3× / week".
    public func shortDescription(calendar: Calendar = .current) -> String {
        switch self {
        case .daily:
            return "Daily"
        case .weekdays(let days):
            if days.count == 7 { return "Daily" }
            let symbols = calendar.shortWeekdaySymbols // index 0 == Sunday
            let ordered = days.sorted()
            return ordered.compactMap { idx -> String? in
                let i = idx - 1
                guard symbols.indices.contains(i) else { return nil }
                return symbols[i]
            }.joined(separator: ", ")
        case .timesPerWeek(let n):
            return "\(n)× / week"
        }
    }
}
