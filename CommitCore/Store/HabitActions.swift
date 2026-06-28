import Foundation
import SwiftData

/// Shared mutations used by the app, the menu bar, and Shortcuts — so every path mutates
/// the same way: stamp `updatedAt` and use tombstones (`isDeleted`) for deletes.
///
/// Marked `@MainActor` because every caller (UI, AppIntents) runs on the main actor and
/// these touch the main `ModelContext`.
@MainActor
public enum HabitActions {

    /// Toggle whether `habit` is completed on `date` (defaults to today).
    /// Un-checking sets a tombstone (isDeleted) rather than hard-deleting, so the
    /// contribution graph stays consistent.
    /// - Returns: `true` if the habit is now completed, `false` if it was un-completed.
    @discardableResult
    public static func toggleCompletion(
        for habit: Habit,
        on date: Date = Date(),
        in context: ModelContext
    ) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)

        let nowCompleted: Bool
        if let existing = (habit.completions ?? []).first(where: {
            calendar.isDate($0.day, inSameDayAs: day)
        }) {
            existing.isDeleted.toggle()
            existing.updatedAt = Date()
            nowCompleted = !existing.isDeleted
        } else {
            let completion = HabitCompletion(day: day, habit: habit)
            context.insert(completion)
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
}
