import XCTest
import SwiftData
@testable import CommitCore

final class ContributionDataTests: XCTestCase {
    private let calendar = Calendar.current

    private func makeContext() -> ModelContext {
        ModelContext(SharedModelContainer.make(inMemory: true))
    }

    private func startOfDay(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
    }

    private func complete(_ habit: Habit, daysAgo: Int, in context: ModelContext) {
        let completion = HabitCompletion(day: startOfDay(daysAgo: daysAgo))
        context.insert(completion)
        if habit.completions == nil { habit.completions = [] }
        habit.completions?.append(completion)
    }

    func testDailyStreakCountsConsecutiveDays() throws {
        let context = makeContext()
        let habit = Habit(name: "Read", schedule: .daily)
        context.insert(habit)
        complete(habit, daysAgo: 0, in: context)
        complete(habit, daysAgo: 1, in: context)
        complete(habit, daysAgo: 2, in: context)
        try context.save()

        XCTAssertEqual(habit.currentStreak(), 3)
    }

    func testStreakNotBrokenWhenTodayNotYetDone() throws {
        let context = makeContext()
        let habit = Habit(name: "Read", schedule: .daily)
        context.insert(habit)
        // Yesterday and the day before, but not today.
        complete(habit, daysAgo: 1, in: context)
        complete(habit, daysAgo: 2, in: context)
        try context.save()

        XCTAssertEqual(habit.currentStreak(), 2)
    }

    func testStreakBreaksOnMissedPastDay() throws {
        let context = makeContext()
        let habit = Habit(name: "Read", schedule: .daily)
        context.insert(habit)
        complete(habit, daysAgo: 0, in: context)
        // gap at daysAgo 1
        complete(habit, daysAgo: 2, in: context)
        try context.save()

        XCTAssertEqual(habit.currentStreak(), 1)
    }

    func testAggregateContributionCountsAllHabitsPerDay() throws {
        let context = makeContext()
        let a = Habit(name: "Read", schedule: .daily)
        let b = Habit(name: "Run", schedule: .daily)
        context.insert(a)
        context.insert(b)
        complete(a, daysAgo: 0, in: context)
        complete(b, daysAgo: 0, in: context)
        try context.save()

        let contributions = makeContributions(habits: [a, b], range: .trailingWeeks(2))
        let today = calendar.startOfDay(for: Date())
        let todayCell = contributions.days.first { calendar.isDate($0.date, inSameDayAs: today) }

        XCTAssertEqual(todayCell?.count, 2)
        XCTAssertEqual(todayCell?.level, 4) // both of two habits done == full intensity
        XCTAssertTrue(contributions.days.count % 7 == 0) // week-aligned grid
    }

    func testTimesPerWeekWeeklyCount() throws {
        let context = makeContext()
        let habit = Habit(name: "Gym", schedule: .timesPerWeek(3))
        context.insert(habit)
        // Two completions inside the current week.
        complete(habit, daysAgo: 0, in: context)
        complete(habit, daysAgo: 1, in: context)
        try context.save()

        XCTAssertGreaterThanOrEqual(habit.weeklyCompletionCount(), 1)
    }
}
