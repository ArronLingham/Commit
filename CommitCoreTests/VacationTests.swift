import XCTest
import SwiftData
@testable import CommitCore

/// Covers "pause all" (vacation mode), the list predicate the date-scoped Home page uses, and
/// the period-habit pause handling that a multi-week vacation would otherwise wreck.
final class VacationTests: XCTestCase {
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

    override func setUp() {
        super.setUp()
        Vacation.record = nil
    }

    override func tearDown() {
        Vacation.record = nil
        super.tearDown()
    }

    // MARK: Pause all

    @MainActor
    func testPauseAllPausesEveryActiveHabit() throws {
        let context = makeContext()
        for name in ["Read", "Run", "Stretch"] {
            context.insert(Habit(name: name, schedule: .daily))
        }
        try context.save()

        let changed = HabitActions.pauseAll(until: startOfDay(daysAgo: -7), in: context)

        XCTAssertEqual(changed, 3)
        let habits = try context.fetch(FetchDescriptor<Habit>())
        for habit in habits {
            XCTAssertTrue(habit.isPaused(), "\(habit.name) should be paused")
            XCTAssertFalse(habit.isDueForList() && !habit.isPaused())
        }
        XCTAssertTrue(Vacation.isActive())
    }

    /// The whole reason pause-all isn't a plain fan-out: a habit already snoozed past your
    /// return date must come through the trip completely untouched.
    @MainActor
    func testPauseAllLeavesAHabitSnoozedBeyondTheTripAlone() throws {
        let context = makeContext()
        let longSnooze = Habit(name: "Gym", schedule: .daily)
        context.insert(longSnooze)
        HabitActions.pause(longSnooze, until: startOfDay(daysAgo: -30), in: context)
        let untilBefore = longSnooze.pausedUntil
        let historyBefore = longSnooze.pauseHistory.count

        HabitActions.pauseAll(until: startOfDay(daysAgo: -7), in: context)

        XCTAssertEqual(longSnooze.pausedUntil, untilBefore, "a longer snooze must not be shortened")
        XCTAssertEqual(longSnooze.pauseHistory.count, historyBefore, "nothing should be archived")
        XCTAssertNil(Vacation.record?.extendedPriorUntil["\(longSnooze.id.uuidString)"])
        XCTAssertFalse(Vacation.record?.createdForHabitIDs.contains(longSnooze.id.uuidString) ?? true)
    }

    /// Coming home early must restore a pre-existing individual snooze, not flatten it.
    @MainActor
    func testResumeAllRestoresAShorterPreExistingPause() throws {
        let context = makeContext()
        let snoozed = Habit(name: "Gym", schedule: .daily)
        let plain = Habit(name: "Read", schedule: .daily)
        context.insert(snoozed)
        context.insert(plain)
        // Individually snoozed until 3 days from now — inside the vacation, so it gets extended.
        HabitActions.pause(snoozed, until: startOfDay(daysAgo: -3), in: context)

        HabitActions.pauseAll(until: startOfDay(daysAgo: -14), in: context)
        XCTAssertEqual(snoozed.pausedUntil, startOfDay(daysAgo: -14), "extended for the trip")

        HabitActions.resumeAll(in: context)

        XCTAssertEqual(
            snoozed.pausedUntil, startOfDay(daysAgo: -3),
            "the habit's own snooze must survive the vacation"
        )
        XCTAssertTrue(snoozed.isPaused(), "still individually snoozed")
        XCTAssertFalse(plain.isPaused(), "the vacation-only habit is back")
        XCTAssertNil(Vacation.record)
    }

    /// Pause-all then immediately undo should leave no trace — in particular no stranded
    /// `pauseHistory` stripe, which is what a naive fan-out would produce.
    @MainActor
    func testPauseAllThenResumeAllSameDayIsANoOp() throws {
        let context = makeContext()
        let habit = Habit(name: "Read", schedule: .daily)
        context.insert(habit)
        try context.save()

        HabitActions.pauseAll(until: startOfDay(daysAgo: -7), in: context)
        HabitActions.resumeAll(in: context)

        XCTAssertFalse(habit.isPaused())
        XCTAssertTrue(habit.pauseHistory.isEmpty, "no stranded pause window")
        XCTAssertFalse(habit.isPausedDay(startOfDay(daysAgo: 0)), "today counts again")
        XCTAssertNil(Vacation.record)
    }

    @MainActor
    func testHabitAddedDuringAVacationStartsPausedAndIsReleased() throws {
        let context = makeContext()
        context.insert(Habit(name: "Read", schedule: .daily))
        try context.save()
        HabitActions.pauseAll(until: startOfDay(daysAgo: -7), in: context)

        let added = HabitActions.addHabit(
            name: "Journal", iconName: "book", colorHex: "#39D353", schedule: .daily, in: context
        )
        XCTAssertTrue(added.isPaused(), "a habit added mid-trip shouldn't start accruing misses")

        HabitActions.resumeAll(in: context)
        XCTAssertFalse(added.isPaused(), "and it must be released with everything else")
    }

    @MainActor
    func testPauseAllUntilTodayIsRejected() throws {
        let context = makeContext()
        context.insert(Habit(name: "Read", schedule: .daily))
        try context.save()

        XCTAssertEqual(HabitActions.pauseAll(until: startOfDay(daysAgo: 0), in: context), 0)
        XCTAssertNil(Vacation.record)
    }

    @MainActor
    func testResumeAllWithoutARecordResumesEverythingPaused() throws {
        let context = makeContext()
        let habit = Habit(name: "Read", schedule: .daily)
        context.insert(habit)
        HabitActions.pause(habit, until: startOfDay(daysAgo: -5), in: context)
        Vacation.record = nil   // e.g. a reinstall, or the pause came from another device

        XCTAssertEqual(HabitActions.resumeAll(in: context), 1)
        XCTAssertFalse(habit.isPaused())
    }

    // MARK: Period habits across a pause

    /// The bug a vacation would otherwise expose: the `.timesPerWeek` branch of `currentStreak`
    /// never consulted the pause windows, so a fortnight away broke every period streak.
    @MainActor
    func testTimesPerWeekStreakSurvivesAFullyPausedWeek() throws {
        let context = makeContext()
        let habit = Habit(name: "Run", schedule: .timesPerWeek(2))
        habit.createdAt = startOfDay(daysAgo: 40)
        context.insert(habit)

        // Hit the target this week and in the weeks either side of a paused one.
        for daysAgo in [0, 1, 7, 8, 21, 22, 28, 29] { complete(habit, daysAgo: daysAgo, in: context) }
        // Paused across the whole week ~14-20 days ago, so it was never missed.
        habit.pausedFrom = calendar.startOfWeek(for: startOfDay(daysAgo: 17))
        habit.pausedUntil = calendar.date(
            byAdding: .day, value: 7, to: calendar.startOfWeek(for: startOfDay(daysAgo: 17))
        )!
        try context.save()

        XCTAssertTrue(
            habit.isFullyPausedPeriod(
                start: calendar.startOfWeek(for: startOfDay(daysAgo: 17)),
                end: calendar.endOfWeek(for: startOfDay(daysAgo: 17))
            ),
            "that week should read as fully paused"
        )
        XCTAssertGreaterThan(
            habit.currentStreak(), 2,
            "the streak must span the paused week rather than break on it"
        )
    }

    @MainActor
    func testFullyPausedPeriodIsExcludedFromCompletionRate() throws {
        let context = makeContext()
        let habit = Habit(name: "Run", schedule: .timesPerWeek(2))
        habit.createdAt = startOfDay(daysAgo: 21)
        context.insert(habit)

        let pausedWeekStart = calendar.startOfWeek(for: startOfDay(daysAgo: 10))
        let pausedWeekEnd = calendar.date(byAdding: .day, value: 7, to: pausedWeekStart)!

        // Hit the target in every week except the paused one, which is left empty. Without the
        // pause that empty week reads as a miss; with it, the week shouldn't be scored at all.
        for daysAgo in 1...21 {
            let day = startOfDay(daysAgo: daysAgo)
            guard day < pausedWeekStart || day >= pausedWeekEnd else { continue }
            complete(habit, daysAgo: daysAgo, in: context)
        }
        habit.pausedFrom = pausedWeekStart
        habit.pausedUntil = pausedWeekEnd
        try context.save()

        let withPause = habit.completionRate()

        habit.pausedFrom = nil
        habit.pausedUntil = nil
        try context.save()
        let withoutPause = habit.completionRate()

        XCTAssertEqual(withPause, 1.0, accuracy: 0.0001, "every scored week met its target")
        XCTAssertLessThan(
            withoutPause, withPause,
            "a week spent entirely paused must not be scored as a missed week"
        )
    }

    // MARK: belongsOnList — the date-scoped list predicate

    @MainActor
    func testBelongsOnListExcludesDaysBeforeTheHabitExisted() throws {
        let context = makeContext()
        let habit = Habit(name: "Read", schedule: .daily)
        habit.createdAt = startOfDay(daysAgo: 3)
        context.insert(habit)
        try context.save()

        XCTAssertFalse(habit.belongsOnList(for: startOfDay(daysAgo: 4)))
        XCTAssertTrue(habit.belongsOnList(for: startOfDay(daysAgo: 3)))
        XCTAssertTrue(habit.belongsOnList(for: startOfDay(daysAgo: 0)))
    }

    /// The case that forces the past/today split. After a Resume, the archived window still
    /// covers today via `pauseHistory` — so a list filtered on `isPausedDay` alone would keep the
    /// habit hidden and Resume would look broken, while `isPaused` alone would wrongly show it as
    /// a plain missable row on the days it really was snoozed.
    @MainActor
    func testBelongsOnListSplitsPastHistoryFromTheLiveWindow() throws {
        let context = makeContext()
        let habit = Habit(name: "Stretch", schedule: .daily)
        habit.createdAt = startOfDay(daysAgo: 20)
        context.insert(habit)

        // Snoozed from 8 days ago until 10 days from now, then re-paused today (which archives
        // the whole original window, including today) and resumed.
        habit.pausedFrom = startOfDay(daysAgo: 8)
        habit.pausedUntil = startOfDay(daysAgo: -10)
        try context.save()
        HabitActions.pause(habit, until: startOfDay(daysAgo: -1), in: context)
        HabitActions.resume(habit, in: context)

        XCTAssertTrue(habit.isPausedDay(startOfDay(daysAgo: 0)), "today is inside the archived span")
        XCTAssertFalse(habit.isPaused(), "but the live window is closed")
        XCTAssertTrue(
            habit.belongsOnList(for: startOfDay(daysAgo: 0)),
            "today must come back on the list after Resume"
        )
        XCTAssertFalse(
            habit.belongsOnList(for: startOfDay(daysAgo: 6)),
            "a day genuinely spent snoozed stays off the list"
        )
    }

    /// A past day is a record, not a todo list: a times-per-week habit whose week later filled up
    /// must stay listed on that past day, or it becomes impossible to backfill.
    @MainActor
    func testBelongsOnListKeepsPastDaysBackfillableAfterTheWeeklyTargetIsMet() throws {
        let context = makeContext()
        let habit = Habit(name: "Run", schedule: .timesPerWeek(1))
        habit.createdAt = startOfDay(daysAgo: 10)
        context.insert(habit)
        complete(habit, daysAgo: 0, in: context)   // target already met this week
        try context.save()

        XCTAssertFalse(
            habit.isDueForList(on: startOfDay(daysAgo: 1)),
            "precondition: the todo-list rule hides it once the target is met"
        )
        XCTAssertTrue(
            habit.belongsOnList(for: startOfDay(daysAgo: 1)),
            "but the past day must still list it so it can be backfilled"
        )
    }

    @MainActor
    func testBelongsOnListHidesAHabitPausedOnAFutureDay() throws {
        let context = makeContext()
        let habit = Habit(name: "Read", schedule: .daily)
        habit.createdAt = startOfDay(daysAgo: 10)
        context.insert(habit)
        HabitActions.pause(habit, until: startOfDay(daysAgo: -5), in: context)
        try context.save()

        XCTAssertFalse(habit.belongsOnList(for: startOfDay(daysAgo: -2)), "still inside the pause")
        XCTAssertTrue(habit.belongsOnList(for: startOfDay(daysAgo: -6)), "after it resumes")
    }
}
