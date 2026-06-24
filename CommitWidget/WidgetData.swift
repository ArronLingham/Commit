import Foundation
import SwiftUI
import SwiftData
import WidgetKit
import CommitCore

/// Shared data access for the widgets: reads the App Group SwiftData store and builds entries.
enum WidgetData {
    static func fetchHabits() -> [Habit] {
        let context = ModelContext(SharedModelContainer.widget)
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func nextRefresh() -> Date {
        let calendar = Calendar.current
        return calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
    }

    // MARK: Contribution graph

    static func contributionEntry(family: WidgetFamily) -> ContributionEntry {
        let habits = fetchHabits()
        let range: ContributionGraphRange
        switch family {
        case .systemSmall: range = .trailingWeeks(7)
        case .systemMedium: range = .trailingWeeks(18)
        default: range = .year(Date())
        }
        let contributions = makeContributions(habits: habits, range: range)
        let today = habits.filter { $0.schedule.isScheduled(on: Date()) }
        return ContributionEntry(
            date: Date(),
            days: contributions.days,
            accent: Theme.currentAccent(),
            completedToday: today.filter { $0.isCompleted(on: Date()) }.count,
            totalToday: today.count
        )
    }

    static func sampleContribution(family: WidgetFamily) -> ContributionEntry {
        let calendar = Calendar.current
        let weeks = family == .systemSmall ? 7 : (family == .systemMedium ? 18 : 52)
        let end = calendar.startOfWeek(for: Date())
        let start = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: end) ?? end
        var days: [DayContribution] = []
        var cursor = calendar.startOfWeek(for: start)
        while cursor <= calendar.endOfWeek(for: end) {
            let level = Int.random(in: 0...4)
            days.append(DayContribution(date: cursor, count: level, level: level, isInRange: true))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }
        return ContributionEntry(date: Date(), days: days, accent: Theme.defaultAccent, completedToday: 2, totalToday: 4)
    }

    // MARK: Today list

    static func todayEntry() -> TodayEntry {
        let habits = fetchHabits().filter { $0.schedule.isScheduled(on: Date()) }
        let items = habits.map { habit in
            TodayHabitItem(
                id: habit.id,
                name: habit.name.isEmpty ? "Untitled" : habit.name,
                iconName: habit.iconName,
                colorHex: habit.colorHex,
                done: habit.isCompleted(on: Date())
            )
        }
        return TodayEntry(date: Date(), habits: items, accent: Theme.currentAccent())
    }

    static func sampleToday() -> TodayEntry {
        TodayEntry(
            date: Date(),
            habits: [
                TodayHabitItem(id: UUID(), name: "Read", iconName: "book", colorHex: "#2F81F7", done: true),
                TodayHabitItem(id: UUID(), name: "Workout", iconName: "dumbbell", colorHex: "#E5534B", done: false),
                TodayHabitItem(id: UUID(), name: "Meditate", iconName: "leaf", colorHex: "#39D353", done: false),
            ],
            accent: Theme.defaultAccent
        )
    }
}
