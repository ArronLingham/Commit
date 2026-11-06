import XCTest
import SwiftData
@testable import CommitCore

final class PhoneSyncCommandTests: XCTestCase {
    func testBatchCompleteIsIdempotentAndDeduplicatesIDs() throws {
        let first = UUID()
        let second = UUID()
        let json = """
        {"ids":["\(first)","\(second)","\(first)","invalid"],"action":"complete"}
        """
        let command = try JSONDecoder().decode(PhoneSyncCommand.self, from: Data(json.utf8))
        XCTAssertEqual(command.habitIDs, [first, second])
        XCTAssertTrue(command.shouldToggle(isCompleted: false))
        XCTAssertFalse(command.shouldToggle(isCompleted: true))
    }

    func testExistingSingleHabitToggleStillWorks() throws {
        let id = UUID()
        let json = "{\"id\":\"\(id)\",\"action\":\"toggle\"}"
        let command = try JSONDecoder().decode(PhoneSyncCommand.self, from: Data(json.utf8))
        XCTAssertEqual(command.habitIDs, [id])
        XCTAssertTrue(command.shouldToggle(isCompleted: false))
        XCTAssertTrue(command.shouldToggle(isCompleted: true))
    }

    func testUnknownActionDoesNotChangeACompletion() throws {
        let command = try JSONDecoder().decode(PhoneSyncCommand.self, from: Data("{\"action\":\"other\"}".utf8))
        XCTAssertTrue(command.habitIDs.isEmpty)
        XCTAssertFalse(command.shouldToggle(isCompleted: false))
    }

    @MainActor
    func testBatchCompletesSeveralHabitsAndCanBeReplayed() throws {
        let context = ModelContext(SharedModelContainer.make(inMemory: true))
        let first = Habit(name: "Read", schedule: .daily)
        let second = Habit(name: "Run", schedule: .daily)
        let other = Habit(name: "Walk", schedule: .daily)
        [first, second, other].forEach { context.insert($0) }
        try context.save()
        let now = Date()
        let json = "{\"ids\":[\"\(first.id)\",\"\(second.id)\",\"\(first.id)\"],\"action\":\"complete\"}"
        let command = try JSONDecoder().decode(PhoneSyncCommand.self, from: Data(json.utf8))

        command.apply(in: context, on: now)
        command.apply(in: context, on: now)

        XCTAssertTrue(first.isCompleted(on: now))
        XCTAssertTrue(second.isCompleted(on: now))
        XCTAssertFalse(other.isCompleted(on: now))
    }
}
