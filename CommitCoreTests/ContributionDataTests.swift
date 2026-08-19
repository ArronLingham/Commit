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

    // MARK: Pause windows

    /// The reported bug: pausing a second time used to overwrite `pausedFrom` / `pausedUntil`,
    /// so every day of the earlier pause flipped from neutral back to a miss.
    @MainActor
    func testEarlierPauseStaysNeutralAfterPausingAgain() throws {
        let context = makeContext()
        let habit = Habit(name: "Stretch", schedule: .daily)
        habit.createdAt = startOfDay(daysAgo: 20)
        context.insert(habit)

        // A pause that ran 8 -> 5 days ago and has since auto-resumed.
        habit.pausedFrom = startOfDay(daysAgo: 8)
        habit.pausedUntil = startOfDay(daysAgo: 5)
        try context.save()
        XCTAssertTrue(habit.isPausedDay(startOfDay(daysAgo: 8)))

        // Pause again today, until tomorrow.
        HabitActions.pause(habit, until: startOfDay(daysAgo: -1), in: context)

        for daysAgo in [8, 7, 6] {
            XCTAssertTrue(
                habit.isPausedDay(startOfDay(daysAgo: daysAgo)),
                "\(daysAgo) days ago was paused and must stay neutral"
            )
        }
        XCTAssertFalse(habit.isPausedDay(startOfDay(daysAgo: 5)), "window is half-open")
        XCTAssertTrue(habit.isPausedDay(startOfDay(daysAgo: 0)), "today is covered by the new pause")
        XCTAssertEqual(habit.pauseHistory.count, 1)
    }

    /// The user-visible consequence: a streak spans an archived pause instead of being cut by it.
    @MainActor
    func testStreakSpansAnArchivedPauseAfterPausingAgain() throws {
        let context = makeContext()
        let habit = Habit(name: "Stretch", schedule: .daily)
        habit.createdAt = startOfDay(daysAgo: 10)
        context.insert(habit)
        for daysAgo in [10, 9, 8, 7, 6] { complete(habit, daysAgo: daysAgo, in: context) }

        // Paused 5 -> 3 days ago, then kept it up again.
        habit.pausedFrom = startOfDay(daysAgo: 5)
        habit.pausedUntil = startOfDay(daysAgo: 2)
        for daysAgo in [2, 1, 0] { complete(habit, daysAgo: daysAgo, in: context) }
        try context.save()

        // Snoozing again today must not cut the run at the old pause (which gave 5).
        HabitActions.pause(habit, until: startOfDay(daysAgo: -1), in: context)

        // 5 days before the pause + 2 after it (today is covered by the new pause, so it's
        // skipped rather than counted). Losing the archived pause would cut this to 5.
        XCTAssertEqual(habit.longestStreak(), 7)
    }

    /// Resuming mid-pause keeps the days already spent paused neutral.
    @MainActor
    func testResumeKeepsElapsedPauseNeutral() throws {
        let context = makeContext()
        let habit = Habit(name: "Run", schedule: .daily)
        habit.createdAt = startOfDay(daysAgo: 10)
        context.insert(habit)
        habit.pausedFrom = startOfDay(daysAgo: 3)
        habit.pausedUntil = startOfDay(daysAgo: -4)   // originally a week off
        try context.save()

        HabitActions.resume(habit, in: context)

        XCTAssertTrue(habit.isPausedDay(startOfDay(daysAgo: 3)))
        XCTAssertTrue(habit.isPausedDay(startOfDay(daysAgo: 1)))
        XCTAssertFalse(habit.isPausedDay(startOfDay(daysAgo: 0)), "today counts again")
        XCTAssertFalse(habit.isPaused())
    }

    /// Pausing and resuming the same day is a no-op on the calendar: today goes back to counting,
    /// and the collapsed window isn't archived as a paused day.
    @MainActor
    func testResumingTheSameDayMakesTodayCountAgain() throws {
        let context = makeContext()
        let habit = Habit(name: "Journal", schedule: .daily)
        habit.createdAt = startOfDay(daysAgo: 5)
        context.insert(habit)

        HabitActions.pause(habit, until: startOfDay(daysAgo: -3), in: context)
        XCTAssertTrue(habit.isPausedDay(startOfDay(daysAgo: 0)))

        HabitActions.resume(habit, in: context)
        XCTAssertFalse(habit.isPausedDay(startOfDay(daysAgo: 0)))
        XCTAssertTrue(habit.pauseHistory.isEmpty)

        // A later pause must not archive that empty window as if it covered a day.
        HabitActions.pause(habit, until: startOfDay(daysAgo: -1), in: context)
        XCTAssertTrue(habit.pauseHistory.isEmpty)
    }

    func testPauseHistoryRoundTripsThroughFlatDates() {
        let habit = Habit(name: "Read")
        let span = PauseSpan(from: startOfDay(daysAgo: 5), until: startOfDay(daysAgo: 3))
        habit.pauseHistory = [span]

        XCTAssertEqual(habit.pauseHistoryDates.count, 2)
        XCTAssertEqual(habit.pauseHistory, [span])
    }

    func testPauseSpanMergeCoalescesOverlappingWindows() {
        let spans = [
            PauseSpan(from: startOfDay(daysAgo: 10), until: startOfDay(daysAgo: 8)),
            PauseSpan(from: startOfDay(daysAgo: 9), until: startOfDay(daysAgo: 6)),
            PauseSpan(from: startOfDay(daysAgo: 3), until: startOfDay(daysAgo: 3)),
            PauseSpan(from: startOfDay(daysAgo: 2), until: startOfDay(daysAgo: 1)),
        ]

        let merged = PauseSpan.merged(spans)

        XCTAssertEqual(merged, [
            PauseSpan(from: startOfDay(daysAgo: 10), until: startOfDay(daysAgo: 6)),
            PauseSpan(from: startOfDay(daysAgo: 2), until: startOfDay(daysAgo: 1)),
        ])
    }
}
