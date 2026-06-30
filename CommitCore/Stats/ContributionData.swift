import Foundation

// MARK: - Calendar helpers

public extension Calendar {
    /// First day of the week containing `date`, respecting `firstWeekday`.
    func startOfWeek(for date: Date) -> Date {
        let day = startOfDay(for: date)
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)
        return self.date(from: comps) ?? day
    }

    /// Last day of the week containing `date`.
    func endOfWeek(for date: Date) -> Date {
        self.date(byAdding: .day, value: 6, to: startOfWeek(for: date)) ?? date
    }
}

// MARK: - Intensity mapping

/// Maps a per-day completion count to a 0…4 intensity level, GitHub style.
public enum ContributionLevel {
    public static func level(count: Int, max: Int) -> Int {
        guard count > 0 else { return 0 }
        guard max > 1 else { return 4 }
        let ratio = Double(count) / Double(max)
        switch ratio {
        case ..<0.25: return 1
        case ..<0.50: return 2
        case ..<0.75: return 3
        default: return 4
        }
    }
}

// MARK: - Contribution model

/// One cell in the contribution graph.
public struct DayContribution: Identifiable, Sendable, Hashable {
    public let date: Date
    /// Number of habits completed on this day.
    public let count: Int
    /// 0…4 intensity level.
    public let level: Int
    /// Whether the day falls inside the requested range (vs. week-alignment padding).
    public let isInRange: Bool
    /// Number of active habits scheduled on this day (the "out of" denominator for tooltips).
    public let scheduled: Int

    public init(date: Date, count: Int, level: Int, isInRange: Bool, scheduled: Int = 0) {
        self.date = date
        self.count = count
        self.level = level
        self.isInRange = isInRange
        self.scheduled = scheduled
    }

    public var id: Date { date }

    /// Human-readable summary for hover tooltips, e.g. "Jun 3, 2026 — 2 of 3 completed".
    public var summary: String {
        let dateText = date.formatted(date: .abbreviated, time: .omitted)
        return scheduled > 0
            ? "\(dateText) — \(count) of \(scheduled) completed"
            : "\(dateText) — \(count) completed"
    }
}

/// A computed grid of contributions, aligned to whole weeks for rendering.
public struct Contributions: Sendable {
    /// Ascending, exactly `gridStart … gridEnd`, length is a multiple of 7.
    public let days: [DayContribution]
    public let gridStart: Date
    public let gridEnd: Date
    /// Denominator used for intensity (active habit count, min 1).
    public let maxPerDay: Int

    public var weeksCount: Int { Int((Double(days.count) / 7.0).rounded(.up)) }
}

/// What span the graph should cover.
public enum ContributionGraphRange: Sendable {
    /// The calendar month containing the given date.
    case month(Date)
    /// The trailing ~52 weeks ending on the given date.
    case year(Date)
    /// The full calendar year (Jan 1 – Dec 31) containing the given date.
    case calendarYear(Date)
    /// The trailing `n` weeks ending today.
    case trailingWeeks(Int)
    /// The calendar week containing the given date.
    case week(Date)

    func bounds(calendar: Calendar, reference: Date) -> (start: Date, end: Date) {
        switch self {
        case .month(let date):
            let comps = calendar.dateComponents([.year, .month], from: date)
            let start = calendar.date(from: comps) ?? calendar.startOfDay(for: date)
            let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 28
            let end = calendar.date(byAdding: .day, value: dayCount - 1, to: start) ?? start
            return (start, end)
        case .year(let date):
            let end = calendar.startOfDay(for: date)
            let start = calendar.date(byAdding: .day, value: -363, to: end) ?? end
            return (start, end)
        case .calendarYear(let date):
            let year = calendar.component(.year, from: date)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
                ?? calendar.startOfDay(for: date)
            let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? start
            return (start, end)
        case .trailingWeeks(let n):
            let end = calendar.startOfDay(for: reference)
            let start = calendar.date(byAdding: .day, value: -(max(1, n) * 7 - 1), to: end) ?? end
            return (start, end)
        case .week(let date):
            return (calendar.startOfWeek(for: date), calendar.endOfWeek(for: date))
        }
    }
}

/// Build the aggregate contribution grid: each day's `count` is how many active
/// habits were completed that day, mapped to a 0…4 intensity.
public func makeContributions(
    habits: [Habit],
    range: ContributionGraphRange,
    calendar: Calendar = .current,
    referenceDate: Date = Date()
) -> Contributions {
    let (primaryStart, primaryEnd) = range.bounds(calendar: calendar, reference: referenceDate)
    let gridStart = calendar.startOfWeek(for: primaryStart)
    let gridEnd = calendar.endOfWeek(for: primaryEnd)

    let active = habits.filter { !$0.isArchived && !$0.isDeleted }
    let denom = max(active.count, 1)

    var counts: [Date: Int] = [:]
    for habit in active {
        for completion in habit.completions ?? [] where !completion.isDeleted {
            let day = calendar.startOfDay(for: completion.day)
            if day >= gridStart && day <= gridEnd {
                counts[day, default: 0] += 1
            }
        }
    }

    let rangeStart = calendar.startOfDay(for: primaryStart)
    let rangeEnd = calendar.startOfDay(for: primaryEnd)

    var days: [DayContribution] = []
    var cursor = gridStart
    while cursor <= gridEnd {
        let count = counts[cursor] ?? 0
        let inRange = cursor >= rangeStart && cursor <= rangeEnd
        let scheduled = active.filter { $0.schedule.isScheduled(on: cursor, calendar: calendar) }.count
        days.append(
            DayContribution(
                date: cursor,
                count: count,
                level: ContributionLevel.level(count: count, max: denom),
                isInRange: inRange,
                scheduled: scheduled
            )
        )
        cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gridEnd.addingTimeInterval(86_400)
    }

    return Contributions(days: days, gridStart: gridStart, gridEnd: gridEnd, maxPerDay: denom)
}

// MARK: - Per-habit stats

public extension Habit {
    /// Completed days as a set of start-of-day dates.
    func completedDaySet(calendar: Calendar = .current) -> Set<Date> {
        Set((completions ?? []).filter { !$0.isDeleted }.map { calendar.startOfDay(for: $0.day) })
    }

    func isCompleted(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return (completions ?? []).contains { !$0.isDeleted && calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// Completions within the calendar week containing `date`.
    func weeklyCompletionCount(asOf date: Date = Date(), calendar: Calendar = .current) -> Int {
        let weekStart = calendar.startOfWeek(for: date)
        let weekEnd = calendar.endOfWeek(for: date)
        return completedDaySet(calendar: calendar).filter { $0 >= weekStart && $0 <= weekEnd }.count
    }

    /// Completions within the calendar month containing `date`.
    func monthlyCompletionCount(asOf date: Date = Date(), calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let monthStart = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: monthStart),
              let monthEnd = calendar.date(byAdding: .day, value: range.count - 1, to: monthStart)
        else { return 0 }
        return completedDaySet(calendar: calendar).filter { $0 >= monthStart && $0 <= monthEnd }.count
    }

    /// Current streak.
    ///
    /// For daily / weekday habits this counts consecutive *scheduled* days completed,
    /// skipping non-scheduled days (so a Mon/Wed/Fri habit doesn't break on Tuesday) and
    /// not breaking on today if today simply hasn't been done yet.
    /// For `timesPerWeek` habits it counts consecutive weeks that met the target.
    func currentStreak(asOf date: Date = Date(), calendar: Calendar = .current) -> Int {
        let completed = completedDaySet(calendar: calendar)

        if case .timesPerWeek(let target) = schedule {
            var streak = 0
            var weekStart = calendar.startOfWeek(for: date)
            let currentWeekStart = weekStart
            var safety = 0
            while safety < 520 {
                safety += 1
                let weekEnd = calendar.endOfWeek(for: weekStart)
                let count = completed.filter { $0 >= weekStart && $0 <= weekEnd }.count
                if count >= target {
                    streak += 1
                } else if calendar.isDate(weekStart, inSameDayAs: currentWeekStart) {
                    // Current week still in progress — don't count, don't break.
                } else {
                    break
                }
                weekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
            }
            return streak
        }

        if case .timesPerMonth(let target) = schedule {
            var streak = 0
            let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
                ?? calendar.startOfDay(for: date)
            var monthStart = currentMonthStart
            var safety = 0
            while safety < 240 {
                safety += 1
                guard let range = calendar.range(of: .day, in: .month, for: monthStart),
                      let monthEnd = calendar.date(byAdding: .day, value: range.count - 1, to: monthStart)
                else { break }
                let count = completed.filter { $0 >= monthStart && $0 <= monthEnd }.count
                if count >= target {
                    streak += 1
                } else if calendar.isDate(monthStart, equalTo: currentMonthStart, toGranularity: .month) {
                    // Current month still in progress — don't count, don't break.
                } else {
                    break
                }
                monthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
            }
            return streak
        }

        var streak = 0
        var day = calendar.startOfDay(for: date)
        var safety = 0
        while safety < 3650 {
            safety += 1
            if schedule.isScheduled(on: day, calendar: calendar) {
                if completed.contains(day) {
                    streak += 1
                } else if calendar.isDateInToday(day) {
                    // Today not done yet — skip without breaking the streak.
                } else {
                    break
                }
            }
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }
}
