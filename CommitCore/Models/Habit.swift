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

    /// Temporary pause window. When set, the habit is hidden from the Today list and not counted
    /// as missed for days in `[pausedFrom, pausedUntil)`; it auto-resumes once `pausedUntil` passes.
    public var pausedFrom: Date? = nil
    public var pausedUntil: Date? = nil

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
