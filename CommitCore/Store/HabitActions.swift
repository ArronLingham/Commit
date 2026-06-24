import Foundation
import SwiftData
import WidgetKit

/// Shared mutations used by the app, the menu bar, the interactive widget, and Shortcuts —
/// so every path toggles a habit the same way and refreshes widgets afterwards.
public enum HabitActions {

    /// Toggle whether `habit` is completed on `date` (defaults to today).
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
            context.delete(existing)
            nowCompleted = false
        } else {
            let completion = HabitCompletion(day: day, habit: habit)
            context.insert(completion)
            nowCompleted = true
        }

        try? context.save()
        reloadWidgets()
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
        reloadWidgets()
        return habit
    }

    public static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
