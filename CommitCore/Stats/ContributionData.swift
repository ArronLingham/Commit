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
    /// Number of habit obligations *assessed* on this day (the "out of" denominator). For
    /// times-per-week / month habits this is only non-zero on the last day of their period.
    public let scheduled: Int
    /// How many of those assessed obligations were missed on this day (drives the informative
    /// colour scheme). Always 0 on future days.
    public let missed: Int

    public init(date: Date, count: Int, level: Int, isInRange: Bool, scheduled: Int = 0, missed: Int = 0) {
        self.date = date
        self.count = count
        self.level = level
        self.isInRange = isInRange
        self.scheduled = scheduled
        self.missed = missed
    }

    public var id: Date { date }

    /// Human-readable summary for hover tooltips, e.g. "Jun 3, 2026 — 2 of 3 done".
    public var summary: String {
        let dateText = date.formatted(date: .abbreviated, time: .omitted)
        return scheduled > 0
            ? "\(dateText) — \(scheduled - missed) of \(scheduled) done"
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
    referenceDate: Date = AppClock.now
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
    let today = calendar.startOfDay(for: referenceDate)

    var days: [DayContribution] = []
    var cursor = gridStart
    while cursor <= gridEnd {
        let count = counts[cursor] ?? 0
        let inRange = cursor >= rangeStart && cursor <= rangeEnd
        let (scheduled, missed) = assess(active, on: cursor, today: today, calendar: calendar)
        days.append(
            DayContribution(
                date: cursor,
                count: count,
                level: ContributionLevel.level(count: count, max: denom),
                isInRange: inRange,
                scheduled: scheduled,
                missed: missed
            )
        )
        cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gridEnd.addingTimeInterval(86_400)
    }

    return Contributions(days: days, gridStart: gridStart, gridEnd: gridEnd, maxPerDay: denom)
}

/// How many habit obligations fall on `day`, and how many of those were missed. Times-per-week /
/// month habits are only assessed on the last day of their period (and never in the future), so
/// they don't paint the whole period as missed before they're actually due.
private func assess(
    _ habits: [Habit],
    on day: Date,
    today: Date,
    calendar: Calendar
) -> (scheduled: Int, missed: Int) {
    guard day <= today else { return (0, 0) }   // future days: nothing assessed yet

    var scheduled = 0
    var missed = 0
    for habit in habits {
        // A habit only applies from the day it was created onward (inclusive) — earlier days
        // are neutral, not misses.
        guard day >= calendar.startOfDay(for: habit.createdAt) else { continue }
        // Paused days are neutral too — a snooze isn't a miss.
        guard !habit.isPausedDay(day, calendar: calendar) else { continue }

        switch habit.schedule {
        case .timesPerWeek(let n):
            guard calendar.isDate(day, inSameDayAs: calendar.endOfWeek(for: day)) else { continue }
            scheduled += 1
            if habit.weeklyCompletionCount(asOf: day, calendar: calendar) < n { missed += 1 }
        case .timesPerMonth(let n):
            guard isLastDayOfMonth(day, calendar: calendar) else { continue }
            scheduled += 1
            if habit.monthlyCompletionCount(asOf: day, calendar: calendar) < n { missed += 1 }
        default:
            guard habit.schedule.isScheduled(on: day, calendar: calendar) else { continue }
            scheduled += 1
            if !habit.isCompleted(on: day, calendar: calendar) { missed += 1 }
        }
    }
    return (scheduled, missed)
}

private func isLastDayOfMonth(_ day: Date, calendar: Calendar) -> Bool {
    guard let range = calendar.range(of: .day, in: .month, for: day) else { return false }
    return calendar.component(.day, from: day) == range.count
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
    func weeklyCompletionCount(asOf date: Date = AppClock.now, calendar: Calendar = .current) -> Int {
        let weekStart = calendar.startOfWeek(for: date)
        let weekEnd = calendar.endOfWeek(for: date)
        return completedDaySet(calendar: calendar).filter { $0 >= weekStart && $0 <= weekEnd }.count
    }

    /// Completions within the calendar month containing `date`.
    func monthlyCompletionCount(asOf date: Date = AppClock.now, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let monthStart = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: monthStart),
              let monthEnd = calendar.date(byAdding: .day, value: range.count - 1, to: monthStart)
        else { return 0 }
        return completedDaySet(calendar: calendar).filter { $0 >= monthStart && $0 <= monthEnd }.count
    }

    /// For `.timesPerWeek` / `.timesPerMonth` habits, whether this period's target has already
    /// been met — so the habit can drop off the list until the week/month rolls over. Always
    /// `false` for other schedules.
    func isPeriodTargetMet(asOf date: Date = AppClock.now, calendar: Calendar = .current) -> Bool {
        switch schedule {
        case .timesPerWeek(let target):
            return weeklyCompletionCount(asOf: date, calendar: calendar) >= target
        case .timesPerMonth(let target):
            return monthlyCompletionCount(asOf: date, calendar: calendar) >= target
        default:
            return false
        }
    }

    /// Whether the habit belongs on the Today list (and in a day's graph denominator) for
    /// `date`: it's scheduled that day and, for times-per-week / month habits, its period
    /// target isn't already met — unless it was completed on `date` itself, so checking off
    /// the last one doesn't make it vanish until the following day.
    func isDueForList(on date: Date = AppClock.now, calendar: Calendar = .current) -> Bool {
        guard schedule.isScheduled(on: date, calendar: calendar) else { return false }
        if isPeriodTargetMet(asOf: date, calendar: calendar),
           !isCompleted(on: date, calendar: calendar) {
            return false
        }
        return true
    }

    // MARK: Pause / snooze

    /// Whether the habit is currently paused (hidden from the Today list) as of `date`.
    func isPaused(asOf date: Date = AppClock.now) -> Bool {
        guard let from = pausedFrom, let until = pausedUntil else { return false }
        return date >= from && date < until
    }

    /// Whether `day` falls inside the pause window — such days are neutral on the graph and don't
    /// break streaks / lower the completion rate.
    func isPausedDay(_ day: Date, calendar: Calendar = .current) -> Bool {
        guard let from = pausedFrom, let until = pausedUntil else { return false }
        let d = calendar.startOfDay(for: day)
        return d >= calendar.startOfDay(for: from) && d < calendar.startOfDay(for: until)
    }

    /// A short "Paused until Jul 3" label, or nil when not paused.
    func pauseStatusText(asOf date: Date = AppClock.now) -> String? {
        guard isPaused(asOf: date), let until = pausedUntil else { return nil }
        return "Paused until \(until.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Current streak.
    ///
    /// For daily / weekday habits this counts consecutive *scheduled* days completed,
    /// skipping non-scheduled days (so a Mon/Wed/Fri habit doesn't break on Tuesday) and
    /// not breaking on today if today simply hasn't been done yet.
    /// For `timesPerWeek` habits it counts consecutive weeks that met the target.
    func currentStreak(asOf date: Date = AppClock.now, calendar: Calendar = .current) -> Int {
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
            if schedule.isScheduled(on: day, calendar: calendar) && !isPausedDay(day, calendar: calendar) {
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

    /// Total number of days this habit was ever completed.
    var totalCompletions: Int { completedDaySet().count }

    /// The longest run this habit ever sustained, using the same rules as `currentStreak`
    /// (consecutive scheduled days for date-based habits, consecutive on-target weeks/months
    /// for times-per-week / month habits) but scanning the whole history for the maximum.
    func longestStreak(asOf date: Date = AppClock.now, calendar: Calendar = .current) -> Int {
        let completed = completedDaySet(calendar: calendar)
        let today = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: createdAt)
        guard start <= today else { return 0 }

        if case .timesPerWeek(let target) = schedule {
            return longestPeriodStreak(target: target, weekly: true, completed: completed, start: start, today: today, calendar: calendar)
        }
        if case .timesPerMonth(let target) = schedule {
            return longestPeriodStreak(target: target, weekly: false, completed: completed, start: start, today: today, calendar: calendar)
        }

        var maxRun = 0, run = 0, safety = 0
        var day = start
        while day <= today && safety < 4000 {
            safety += 1
            if schedule.isScheduled(on: day, calendar: calendar) && !isPausedDay(day, calendar: calendar) {
                if completed.contains(day) {
                    run += 1
                    maxRun = max(maxRun, run)
                } else if calendar.isDateInToday(day) {
                    // Today not done yet — don't reset the run.
                } else {
                    run = 0
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? today.addingTimeInterval(86_400)
        }
        return maxRun
    }

    /// How well the habit has been kept, 0…1: scheduled days completed ÷ scheduled days for
    /// date-based habits, or on-target periods ÷ elapsed periods for times-per-week / month.
    /// The current in-progress day/period is excluded so it isn't unfairly counted as a miss.
    func completionRate(asOf date: Date = AppClock.now, calendar: Calendar = .current) -> Double {
        let completed = completedDaySet(calendar: calendar)
        let today = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: createdAt)
        guard start <= today else { return 0 }

        if case .timesPerWeek(let target) = schedule {
            return periodRate(target: target, weekly: true, completed: completed, start: start, today: today, calendar: calendar)
        }
        if case .timesPerMonth(let target) = schedule {
            return periodRate(target: target, weekly: false, completed: completed, start: start, today: today, calendar: calendar)
        }

        var scheduledDays = 0, doneDays = 0, safety = 0
        var day = start
        while day <= today && safety < 4000 {
            safety += 1
            if schedule.isScheduled(on: day, calendar: calendar) && !isPausedDay(day, calendar: calendar) {
                let doneToday = completed.contains(day)
                // Skip an in-progress today that isn't done yet.
                if !(calendar.isDateInToday(day) && !doneToday) {
                    scheduledDays += 1
                    if doneToday { doneDays += 1 }
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? today.addingTimeInterval(86_400)
        }
        return scheduledDays > 0 ? Double(doneDays) / Double(scheduledDays) : 0
    }

    // MARK: Period-habit helpers (weeks / months)

    private func periodBounds(start: Date, weekly: Bool, calendar: Calendar) -> (start: Date, end: Date) {
        if weekly {
            let s = calendar.startOfWeek(for: start)
            return (s, calendar.endOfWeek(for: s))
        }
        let s = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        let count = calendar.range(of: .day, in: .month, for: s)?.count ?? 30
        return (s, calendar.date(byAdding: .day, value: count - 1, to: s) ?? s)
    }

    private func longestPeriodStreak(target: Int, weekly: Bool, completed: Set<Date>, start: Date, today: Date, calendar: Calendar) -> Int {
        var maxRun = 0, run = 0, safety = 0
        var periodStart = periodBounds(start: start, weekly: weekly, calendar: calendar).start
        while periodStart <= today && safety < 2400 {
            safety += 1
            let bounds = periodBounds(start: periodStart, weekly: weekly, calendar: calendar)
            let count = completed.filter { $0 >= bounds.start && $0 <= bounds.end }.count
            let isCurrent = today >= bounds.start && today <= bounds.end
            if count >= target {
                run += 1
                maxRun = max(maxRun, run)
            } else if isCurrent {
                // In-progress period — don't reset.
            } else {
                run = 0
            }
            periodStart = calendar.date(byAdding: weekly ? .weekOfYear : .month, value: 1, to: periodStart) ?? today.addingTimeInterval(86_400)
        }
        return maxRun
    }

    private func periodRate(target: Int, weekly: Bool, completed: Set<Date>, start: Date, today: Date, calendar: Calendar) -> Double {
        var total = 0, met = 0, safety = 0
        var periodStart = periodBounds(start: start, weekly: weekly, calendar: calendar).start
        while periodStart <= today && safety < 2400 {
            safety += 1
            let bounds = periodBounds(start: periodStart, weekly: weekly, calendar: calendar)
            let isCurrent = today >= bounds.start && today <= bounds.end
            if !isCurrent {   // only score fully-elapsed periods
                total += 1
                let count = completed.filter { $0 >= bounds.start && $0 <= bounds.end }.count
                if count >= target { met += 1 }
            }
            periodStart = calendar.date(byAdding: weekly ? .weekOfYear : .month, value: 1, to: periodStart) ?? today.addingTimeInterval(86_400)
        }
        return total > 0 ? Double(met) / Double(total) : 0
    }
}
