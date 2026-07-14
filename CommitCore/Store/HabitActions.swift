import Foundation
import SwiftData

/// Shared mutations used by the app, the menu bar, and Shortcuts — so every path mutates
/// the same way: stamp `updatedAt` and use tombstones (`isDeleted`) for deletes.
///
/// Marked `@MainActor` because every caller (UI, AppIntents) runs on the main actor and
/// these touch the main `ModelContext`.
@MainActor
public enum HabitActions {

    /// Toggle whether `habit` is completed on `date` (defaults to today). Checking inserts a
    /// completion; un-checking **deletes** it so SwiftData refreshes the views — flipping a
    /// flag left the `completions` relationship unchanged, so the UI never updated.
    /// - Returns: `true` if the habit is now completed, `false` if it was un-completed.
    @discardableResult
    public static func toggleCompletion(
        for habit: Habit,
        on date: Date = AppClock.now,
        in context: ModelContext
    ) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)

        let nowCompleted: Bool
        if let existing = (habit.completions ?? []).first(where: {
            calendar.isDate($0.day, inSameDayAs: day)
        }) {
            if existing.isDeleted {
                // Legacy tombstone → re-complete it.
                existing.isDeleted = false
                existing.updatedAt = Date()
                nowCompleted = true
            } else {
                context.delete(existing)
                nowCompleted = false
            }
        } else {
            context.insert(HabitCompletion(day: day, habit: habit))
            nowCompleted = true
        }

        try? context.save()
        return nowCompleted
    }

    /// Insert a new habit at the end of the current ordering.
    @discardableResult
    public static func addHabit(
        name: String,
        iconName: String,
        colorHex: String,
        schedule: Schedule,
        in context: ModelContext
    ) -> Habit {
        let nextOrder = (try? context.fetch(FetchDescriptor<Habit>()))?
            .map(\.sortOrder).max().map { $0 + 1 } ?? 0
        let habit = Habit(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            schedule: schedule,
            sortOrder: nextOrder
        )
        context.insert(habit)
        try? context.save()
        return habit
    }

    /// Call after editing a habit's fields to stamp `updatedAt` and persist.
    public static func saveEdits(to habit: Habit, in context: ModelContext) {
        habit.updatedAt = Date()
        try? context.save()
    }

    /// Set/clear the archived flag.
    public static func setArchived(_ habit: Habit, archived: Bool, in context: ModelContext) {
        habit.isArchived = archived
        habit.updatedAt = Date()
        try? context.save()
    }

    /// Soft-delete (tombstone) a habit and its completions so they disappear from the
    /// app and menu bar consistently.
    public static func softDelete(_ habit: Habit, in context: ModelContext) {
        habit.isDeleted = true
        habit.updatedAt = Date()
        for completion in habit.completions ?? [] where !completion.isDeleted {
            completion.isDeleted = true
            completion.updatedAt = Date()
        }
        try? context.save()
    }

    /// Persist a new ordering: rewrite each habit's `sortOrder` to its index in `ordered`.
    public static func reorder(_ ordered: [Habit], in context: ModelContext) {
        for (index, habit) in ordered.enumerated() where habit.sortOrder != index {
            habit.sortOrder = index
            habit.updatedAt = Date()
        }
        try? context.save()
    }

    // MARK: Tester Mode session

    private static let testerSnapshotKey = "testerCompletionSnapshot"

    /// A stable "habitID|startOfDay" key so completions can be compared across a tester session.
    private static func completionKey(habitID: UUID, day: Date, calendar: Calendar) -> String {
        "\(habitID.uuidString)|\(Int(calendar.startOfDay(for: day).timeIntervalSinceReferenceDate))"
    }

    /// Snapshot the current (real) completion set when Tester Mode is turned on, so any
    /// check-offs made while testing can be fully reverted afterwards.
    public static func beginTesterSession(in context: ModelContext) {
        let calendar = Calendar.current
        let completions = (try? context.fetch(FetchDescriptor<HabitCompletion>())) ?? []
        let keys = completions.compactMap { c -> String? in
            guard !c.isDeleted, let habitID = c.habit?.id else { return nil }
            return completionKey(habitID: habitID, day: c.day, calendar: calendar)
        }
        CommitConstants.sharedDefaults.set(Array(Set(keys)), forKey: testerSnapshotKey)
    }

    /// Revert every completion change made since `beginTesterSession`: delete completions added
    /// while testing and restore ones that were un-checked, returning the store to the snapshot.
    /// No-op if there's no snapshot (Tester Mode was never started).
    public static func endTesterSession(in context: ModelContext) {
        guard let stored = CommitConstants.sharedDefaults.array(forKey: testerSnapshotKey) as? [String] else { return }
        let snapshot = Set(stored)
        let calendar = Calendar.current

        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        let habitsByID = Dictionary(habits.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })

        let completions = (try? context.fetch(FetchDescriptor<HabitCompletion>())) ?? []
        var currentKeys = Set<String>()
        for c in completions where !c.isDeleted {
            guard let habitID = c.habit?.id else { continue }
            let key = completionKey(habitID: habitID, day: c.day, calendar: calendar)
            currentKeys.insert(key)
            if !snapshot.contains(key) {
                context.delete(c)            // added during testing → remove
            }
        }
        for key in snapshot where !currentKeys.contains(key) {
            let parts = key.split(separator: "|")
            guard parts.count == 2,
                  let habit = habitsByID[String(parts[0])],
                  let seconds = Int(parts[1]) else { continue }
            let day = Date(timeIntervalSinceReferenceDate: TimeInterval(seconds))
            context.insert(HabitCompletion(day: day, habit: habit))   // un-checked during testing → restore
        }

        CommitConstants.sharedDefaults.removeObject(forKey: testerSnapshotKey)
        try? context.save()
    }
}
