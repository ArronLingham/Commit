import Foundation

/// The kind of schedule a habit follows. Used as the persisted discriminator.
public enum ScheduleKind: String, CaseIterable, Codable, Sendable {
    case daily
    case weekdays
    case timesPerWeek
    case timesPerMonth
    case monthly
    case yearly
    case everyNDays
}

/// Strongly-typed schedule for a habit.
public enum Schedule: Equatable, Hashable, Sendable {
    /// Every day.
    case daily
    /// Specific weekdays. 1 = Sunday … 7 = Saturday (matches `Calendar.component(.weekday:)`).
    case weekdays(Set<Int>)
    /// Any `n` days within a calendar week.
    case timesPerWeek(Int)
    /// Any `n` days within a calendar month.
    case timesPerMonth(Int)
    /// Specific days of the month, 1…31.
    case monthly(Set<Int>)
    /// A specific calendar date each year (month 1…12, day 1…31).
    case yearly(month: Int, day: Int)
    /// Every `n` days on a fixed global cadence (n == 1 behaves like daily).
    case everyNDays(Int)

    public var kind: ScheduleKind {
        switch self {
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .timesPerWeek: return .timesPerWeek
        case .timesPerMonth: return .timesPerMonth
        case .monthly: return .monthly
        case .yearly: return .yearly
        case .everyNDays: return .everyNDays
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
        case .timesPerMonth:
            return true
        case .monthly(let days):
            return days.contains(calendar.component(.day, from: date))
        case .yearly(let month, let day):
            let comps = calendar.dateComponents([.month, .day], from: date)
            return comps.month == month && comps.day == day
        case .everyNDays(let n):
            guard n > 1 else { return true }
            // Fixed cadence anchored to the reference date (2001-01-01) so it's deterministic.
            let anchor = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
            let target = calendar.startOfDay(for: date)
            let days = calendar.dateComponents([.day], from: anchor, to: target).day ?? 0
            return ((days % n) + n) % n == 0
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
        case .timesPerMonth(let n):
            return "\(n)× / month"
        case .monthly(let days):
            if days.isEmpty { return "Monthly" }
            return "Monthly: " + days.sorted().map(String.init).joined(separator: ", ")
        case .yearly(let month, let day):
            let i = month - 1
            let monthName = calendar.shortMonthSymbols.indices.contains(i)
                ? calendar.shortMonthSymbols[i] : "\(month)"
            return "Yearly: \(monthName) \(day)"
        case .everyNDays(let n):
            return n <= 1 ? "Daily" : "Every \(n) days"
        }
    }

    /// The next date strictly after `date` on which the habit is scheduled (searches up to a
    /// year-plus ahead). Returns nil if nothing matches within the window.
    public func nextDate(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: date)
        for offset in 1...400 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if isScheduled(on: candidate, calendar: calendar) { return candidate }
        }
        return nil
    }
}
