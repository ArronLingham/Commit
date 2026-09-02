import Foundation

/// A "pause all" episode — what the vacation itself changed, so ending it early can *restore*
/// each habit's previous pause rather than flattening it.
///
/// Deliberately stored in `sharedDefaults` as JSON rather than SwiftData: this is a short-lived
/// undo buffer, not habit data. The durable truth stays in each habit's own `pausedFrom` /
/// `pausedUntil`, which is what keeps the graph, streaks, menu bar, and phone sync working with
/// no changes at all. If the record goes missing (reinstall, another device) `resumeAll` falls
/// back to "resume everything that's paused" instead of corrupting anything.
public struct VacationRecord: Codable, Sendable, Equatable {
    /// Start of the day the vacation began. Informational.
    public var startedOn: Date
    /// Exclusive end, start-of-day — the same half-open `[from, until)` convention as `PauseSpan`.
    public var endsOn: Date
    /// Habits that were *not* paused when the vacation began, keyed by `id.uuidString`.
    /// Resuming truncates these to today, exactly like `HabitActions.resume`.
    public var createdForHabitIDs: [String]
    /// Habits that were *already* paused and merely had their window extended → their
    /// `pausedUntil` from before the vacation. Resuming restores `max(prior, today)`.
    public var extendedPriorUntil: [String: Date]

    public init(
        startedOn: Date,
        endsOn: Date,
        createdForHabitIDs: [String] = [],
        extendedPriorUntil: [String: Date] = [:]
    ) {
        self.startedOn = startedOn
        self.endsOn = endsOn
        self.createdForHabitIDs = createdForHabitIDs
        self.extendedPriorUntil = extendedPriorUntil
    }
}

/// Storage for the current "pause all" episode. Follows the same feature-owns-its-keys idiom as
/// `ReminderScheduler` and `AppClock`.
public enum Vacation {
    public static let recordKey = "vacationRecord"

    /// The stored record, whether or not it has already elapsed.
    public static var record: VacationRecord? {
        get {
            guard let data = CommitConstants.sharedDefaults.data(forKey: recordKey) else { return nil }
            return try? JSONDecoder().decode(VacationRecord.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                CommitConstants.sharedDefaults.removeObject(forKey: recordKey)
                return
            }
            CommitConstants.sharedDefaults.set(data, forKey: recordKey)
        }
    }

    /// The record only while it's still running. Clears the key once `endsOn` has passed, so a
    /// vacation that simply lapses leaves nothing behind.
    ///
    /// This is the single place the "vacation ended on its own" transition is observed, so it's
    /// also where the nightly reminder is re-armed. `refresh()` is otherwise only called at
    /// launch and from Settings — without this, a trip that lapsed while the app kept running
    /// (it's designed to live in the menu bar) would leave the reminder cancelled indefinitely.
    public static func activeRecord(asOf date: Date = AppClock.now, calendar: Calendar = .current) -> VacationRecord? {
        guard let record else { return nil }
        guard calendar.startOfDay(for: date) < calendar.startOfDay(for: record.endsOn) else {
            self.record = nil
            ReminderScheduler.refresh()
            return nil
        }
        return record
    }

    /// Whether a "pause all" is currently in effect.
    public static func isActive(asOf date: Date = AppClock.now, calendar: Calendar = .current) -> Bool {
        activeRecord(asOf: date, calendar: calendar) != nil
    }

    /// "Paused until Sep 14" for the running vacation, or nil when there isn't one.
    public static func statusText(asOf date: Date = AppClock.now, calendar: Calendar = .current) -> String? {
        guard let record = activeRecord(asOf: date, calendar: calendar) else { return nil }
        return "All habits paused until \(record.endsOn.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
