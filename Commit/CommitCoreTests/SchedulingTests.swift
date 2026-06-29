import XCTest
@testable import CommitCore

final class SchedulingTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testDailyIsAlwaysScheduled() {
        let schedule = Schedule.daily
        XCTAssertTrue(schedule.isScheduled(on: date(2024, 1, 1)))   // Monday
        XCTAssertTrue(schedule.isScheduled(on: date(2024, 1, 6)))   // Saturday
    }

    func testWeekdayScheduleMatchesOnlySelectedDays() {
        // 2024-01-01 is a Monday (weekday 2); 2024-01-02 is a Tuesday (weekday 3).
        let monday = date(2024, 1, 1)
        let tuesday = date(2024, 1, 2)
        XCTAssertEqual(calendar.component(.weekday, from: monday), 2)

        let schedule = Schedule.weekdays([2]) // Mondays only
        XCTAssertTrue(schedule.isScheduled(on: monday))
        XCTAssertFalse(schedule.isScheduled(on: tuesday))
    }

    func testTimesPerWeekIsScheduledEveryDay() {
        let schedule = Schedule.timesPerWeek(3)
        XCTAssertTrue(schedule.isScheduled(on: date(2024, 1, 1)))
        XCTAssertTrue(schedule.isScheduled(on: date(2024, 1, 3)))
    }

    func testScheduleEncodingRoundTripsThroughHabit() {
        let habit = Habit(schedule: .weekdays([2, 4, 6]))
        XCTAssertEqual(habit.schedule, .weekdays([2, 4, 6]))
        XCTAssertEqual(habit.scheduleRaw, ScheduleKind.weekdays.rawValue)

        habit.schedule = .timesPerWeek(5)
        XCTAssertEqual(habit.schedule, .timesPerWeek(5))
        XCTAssertEqual(habit.targetPerWeek, 5)
    }

    func testIntensityLevelMapping() {
        XCTAssertEqual(ContributionLevel.level(count: 0, max: 4), 0)
        XCTAssertEqual(ContributionLevel.level(count: 4, max: 4), 4)
        XCTAssertEqual(ContributionLevel.level(count: 1, max: 8), 1)
        XCTAssertEqual(ContributionLevel.level(count: 0, max: 1), 0)
        // With a single habit, any completion is full intensity.
        XCTAssertEqual(ContributionLevel.level(count: 1, max: 1), 4)
    }
}
