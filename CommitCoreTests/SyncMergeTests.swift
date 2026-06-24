import XCTest
import SwiftData
@testable import CommitCore

/// Tests the last-write-wins merge + tombstone behaviour that sync relies on.
/// Uses an in-memory store and DTOs built from detached model instances — no Firebase.
final class SyncMergeTests: XCTestCase {

    private func makeContext() -> ModelContext {
        ModelContext(SharedModelContainer.make(inMemory: true))
    }

    /// Build a HabitDTO with explicit id / updatedAt / isDeleted.
    private func habitDTO(id: UUID, name: String, updatedAt: Date, isDeleted: Bool = false) -> HabitDTO {
        let h = Habit(name: name)
        h.id = id
        h.updatedAt = updatedAt
        h.isDeleted = isDeleted
        return HabitDTO(h)
    }

    func testApplyInsertsNewHabit() {
        let context = makeContext()
        let id = UUID()
        SyncMerge.apply(habits: [habitDTO(id: id, name: "Read", updatedAt: Date())], into: context)

        let all = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Read")
    }

    func testOlderRemoteUpdateIsIgnored() {
        let context = makeContext()
        let id = UUID()
        let now = Date()

        let local = Habit(name: "Local")
        local.id = id
        local.updatedAt = now
        context.insert(local)
        try? context.save()

        SyncMerge.apply(habits: [habitDTO(id: id, name: "Remote", updatedAt: now.addingTimeInterval(-100))], into: context)

        let fetched = (try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })))?.first
        XCTAssertEqual(fetched?.name, "Local")
    }

    func testNewerRemoteUpdateWins() {
        let context = makeContext()
        let id = UUID()
        let now = Date()

        let local = Habit(name: "Local")
        local.id = id
        local.updatedAt = now
        context.insert(local)
        try? context.save()

        SyncMerge.apply(habits: [habitDTO(id: id, name: "Remote", updatedAt: now.addingTimeInterval(100))], into: context)

        let fetched = (try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })))?.first
        XCTAssertEqual(fetched?.name, "Remote")
    }

    func testTombstoneHidesHabit() {
        let context = makeContext()
        let id = UUID()
        let now = Date()

        let local = Habit(name: "Local")
        local.id = id
        local.updatedAt = now
        context.insert(local)
        try? context.save()

        SyncMerge.apply(habits: [habitDTO(id: id, name: "Local", updatedAt: now.addingTimeInterval(50), isDeleted: true)], into: context)

        let active = (try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { !$0.isDeleted }))) ?? []
        XCTAssertTrue(active.isEmpty)
    }

    func testApplyCompletionLinksToHabit() {
        let context = makeContext()
        let habitID = UUID()
        let habit = Habit(name: "Read")
        habit.id = habitID
        context.insert(habit)
        try? context.save()

        let completion = HabitCompletion(day: Date(), habit: habit)
        let completionID = UUID()
        completion.id = completionID

        SyncMerge.apply(completions: [CompletionDTO(completion)], into: context)

        let fetched = (try? context.fetch(FetchDescriptor<HabitCompletion>()))?.first
        XCTAssertEqual(fetched?.id, completionID)
        XCTAssertEqual(fetched?.habit?.id, habitID)
    }
}
