import Foundation
import SwiftData

/// A habit the user wants to build. Stored in SwiftData and synced via CloudKit.
///
/// CloudKit (`NSPersistentCloudKitContainer`) requires every stored property to be
/// optional or have a default, relationships to be optional, and forbids
/// `@Attribute(.unique)` — so uniqueness (one completion per habit per day) is
/// enforced in code, not by the store.
@Model
public final class Habit {
    public var id: UUID = UUID()
    public var name: String = ""
    /// SF Symbol name shown next to the habit.
    public var iconName: String = "checkmark.circle"
    /// Per-habit accent, stored as a hex string (e.g. "#39D353").
    public var colorHex: String = Theme.defaultAccentHex

    /// Schedule is encoded across three primitive fields so it stays CloudKit-friendly.
    /// Read/written via the `schedule` computed property below.
    public var scheduleRaw: String = ScheduleKind.daily.rawValue
    /// Weekdays for `.weekdays` schedules. 1 = Sunday … 7 = Saturday (matches `Calendar`).
    public var weekdays: [Int] = []
    /// Target completions per week for `.timesPerWeek` schedules.
    public var targetPerWeek: Int = 3

    public var createdAt: Date = Date()
    public var sortOrder: Int = 0
    public var isArchived: Bool = false
    /// Tombstone for sync: soft-deleted records are kept so deletions propagate
    /// between devices instead of resurrecting. Filtered out of all queries.
    public var isDeleted: Bool = false
    /// Last local modification time; drives last-write-wins merge during sync.
    public var updatedAt: Date = Date()

    /// The *latest* pause window. When set, the habit is hidden from the Today list and not counted
    /// as missed for days in `[pausedFrom, pausedUntil)`; it auto-resumes once `pausedUntil` passes.
    public var pausedFrom: Date? = nil
    public var pausedUntil: Date? = nil

    /// Every *earlier* pause window, flattened to `[from, until, from, until, …]` — the same
    /// primitive-fields trick `scheduleRaw` / `weekdays` use to stay CloudKit-friendly.
    ///
    /// Pausing overwrites `pausedFrom` / `pausedUntil`, so without this a second snooze would
    /// erase the first and retroactively turn those neutral days into misses. Read/written as
    /// `PauseSpan`s via `pauseHistory`.
    public var pauseHistoryDates: [Date] = []

    @Relationship(deleteRule: .cascade, inverse: \HabitCompletion.habit)
    public var completions: [HabitCompletion]? = []

    public init(
        name: String = "",
        iconName: String = "checkmark.circle",
        colorHex: String = Theme.defaultAccentHex,
        schedule: Schedule = .daily,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.createdAt = Date()
        self.sortOrder = sortOrder
        self.isArchived = false
        self.isDeleted = false
        self.updatedAt = Date()
        self.pausedFrom = nil
        self.pausedUntil = nil
        self.pauseHistoryDates = []
        self.completions = []

        // Encode the schedule into the stored fields explicitly (avoids calling a
        // computed-property setter during a SwiftData @Model init).
        switch schedule {
        case .daily:
            self.scheduleRaw = ScheduleKind.daily.rawValue
            self.weekdays = []
            self.targetPerWeek = 3
        case .weekdays(let days):
            self.scheduleRaw = ScheduleKind.weekdays.rawValue
            self.weekdays = days.sorted()
            self.targetPerWeek = 3
        case .timesPerWeek(let n):
            self.scheduleRaw = ScheduleKind.timesPerWeek.rawValue
            self.weekdays = []
            self.targetPerWeek = max(1, n)
        case .timesPerMonth(let n):
            self.scheduleRaw = ScheduleKind.timesPerMonth.rawValue
            self.weekdays = []
            self.targetPerWeek = max(1, n)          // reused field: monthly target
        case .monthly(let days):
            self.scheduleRaw = ScheduleKind.monthly.rawValue
            self.weekdays = days.sorted()          // reused field: days of month
            self.targetPerWeek = 3
        case .yearly(let month, let day):
            self.scheduleRaw = ScheduleKind.yearly.rawValue
            self.weekdays = [month, day]           // reused field: [month, day]
            self.targetPerWeek = 3
        case .everyNDays(let n):
            self.scheduleRaw = ScheduleKind.everyNDays.rawValue
            self.weekdays = []
            self.targetPerWeek = max(1, n)         // reused field: interval in days
        }
    }
}

public extension Habit {
    /// Strongly-typed view over the encoded schedule fields.
    var schedule: Schedule {
        get {
            switch ScheduleKind(rawValue: scheduleRaw) ?? .daily {
            case .daily: return .daily
            case .weekdays: return .weekdays(Set(weekdays))
            case .timesPerWeek: return .timesPerWeek(max(1, targetPerWeek))
            case .timesPerMonth: return .timesPerMonth(max(1, targetPerWeek))
            case .monthly: return .monthly(Set(weekdays))
            case .yearly:
                let month = weekdays.indices.contains(0) ? weekdays[0] : 1
                let day = weekdays.indices.contains(1) ? weekdays[1] : 1
                return .yearly(month: month, day: day)
            case .everyNDays: return .everyNDays(max(1, targetPerWeek))
            }
        }
        set {
            switch newValue {
            case .daily:
                scheduleRaw = ScheduleKind.daily.rawValue
            case .weekdays(let days):
                scheduleRaw = ScheduleKind.weekdays.rawValue
                weekdays = days.sorted()
            case .timesPerWeek(let n):
                scheduleRaw = ScheduleKind.timesPerWeek.rawValue
                targetPerWeek = max(1, n)
            case .timesPerMonth(let n):
                scheduleRaw = ScheduleKind.timesPerMonth.rawValue
                targetPerWeek = max(1, n)
            case .monthly(let days):
                scheduleRaw = ScheduleKind.monthly.rawValue
                weekdays = days.sorted()
            case .yearly(let month, let day):
                scheduleRaw = ScheduleKind.yearly.rawValue
                weekdays = [month, day]
            case .everyNDays(let n):
                scheduleRaw = ScheduleKind.everyNDays.rawValue
                targetPerWeek = max(1, n)
            }
        }
    }
}

// MARK: - Pause windows

/// One pause window, half-open in start-of-day terms: `[from, until)`.
public struct PauseSpan: Codable, Hashable, Sendable {
    public var from: Date
    public var until: Date

    public init(from: Date, until: Date) {
        self.from = from
        self.until = until
    }

    /// A window that never covered a whole day — e.g. paused and resumed the same day.
    public var isEmpty: Bool { until <= from }

    public func contains(_ day: Date, calendar: Calendar = .current) -> Bool {
        let d = calendar.startOfDay(for: day)
        return d >= calendar.startOfDay(for: from) && d < calendar.startOfDay(for: until)
    }

    /// Sort and coalesce, dropping empty windows, so repeated snoozes can't pile up overlapping
    /// spans. The result is the same set of paused days in the fewest windows.
    public static func merged(_ spans: [PauseSpan]) -> [PauseSpan] {
        let sorted = spans.filter { !$0.isEmpty }.sorted { $0.from < $1.from }
        var result: [PauseSpan] = []
        for span in sorted {
            if var last = result.last, span.from <= last.until {
                last.until = max(last.until, span.until)
                result[result.count - 1] = last
            } else {
                result.append(span)
            }
        }
        return result
    }
}

public extension Habit {
    /// The earlier pause windows held in `pauseHistoryDates`. An odd trailing date (which
    /// shouldn't happen) is ignored rather than crashing.
    var pauseHistory: [PauseSpan] {
        get {
            stride(from: 0, to: pauseHistoryDates.count - 1, by: 2).map {
                PauseSpan(from: pauseHistoryDates[$0], until: pauseHistoryDates[$0 + 1])
            }
        }
        set {
            pauseHistoryDates = newValue.flatMap { [$0.from, $0.until] }
        }
    }

    /// The window in `pausedFrom` / `pausedUntil`, or nil when it covers no days.
    var currentPauseSpan: PauseSpan? {
        guard let from = pausedFrom, let until = pausedUntil else { return nil }
        let span = PauseSpan(from: from, until: until)
        return span.isEmpty ? nil : span
    }
}
