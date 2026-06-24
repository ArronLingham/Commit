import Foundation
import SwiftData

/// Applies remote records into the local SwiftData store using **last-write-wins** on
/// `updatedAt`. Pure (no Firebase, not main-actor bound) so it can be unit-tested with
/// an in-memory container and a mock backend.
public enum SyncMerge {

    /// - Returns: number of records inserted/updated.
    @discardableResult
    public static func apply(habits dtos: [HabitDTO], into context: ModelContext) -> Int {
        var changes = 0
        for dto in dtos {
            guard let uuid = UUID(uuidString: dto.id) else { continue }
            let existing = try? context.fetch(
                FetchDescriptor<Habit>(predicate: #Predicate { $0.id == uuid })
            ).first

            if let habit = existing {
                guard dto.updatedAt > habit.updatedAt else { continue }
                assign(dto, to: habit)
                changes += 1
            } else {
                let habit = Habit()
                habit.id = uuid
                assign(dto, to: habit)
                context.insert(habit)
                changes += 1
            }
        }
        if changes > 0 { try? context.save() }
        return changes
    }

    @discardableResult
    public static func apply(completions dtos: [CompletionDTO], into context: ModelContext) -> Int {
        var changes = 0
        for dto in dtos {
            guard let uuid = UUID(uuidString: dto.id) else { continue }
            let existing = try? context.fetch(
                FetchDescriptor<HabitCompletion>(predicate: #Predicate { $0.id == uuid })
            ).first
            let habit = linkedHabit(for: dto, in: context)

            if let completion = existing {
                guard dto.updatedAt > completion.updatedAt else { continue }
                completion.day = dto.day
                completion.count = dto.count
                completion.isDeleted = dto.isDeleted
                completion.createdAt = dto.createdAt
                completion.updatedAt = dto.updatedAt
                if completion.habit == nil { completion.habit = habit }
                changes += 1
            } else {
                let completion = HabitCompletion(day: dto.day, count: dto.count, habit: habit)
                completion.id = uuid
                completion.isDeleted = dto.isDeleted
                completion.createdAt = dto.createdAt
                completion.updatedAt = dto.updatedAt
                context.insert(completion)
                changes += 1
            }
        }
        if changes > 0 { try? context.save() }
        return changes
    }

    private static func assign(_ dto: HabitDTO, to habit: Habit) {
        habit.name = dto.name
        habit.iconName = dto.iconName
        habit.colorHex = dto.colorHex
        habit.scheduleRaw = dto.scheduleRaw
        habit.weekdays = dto.weekdays
        habit.targetPerWeek = dto.targetPerWeek
        habit.sortOrder = dto.sortOrder
        habit.isArchived = dto.isArchived
        habit.isDeleted = dto.isDeleted
        habit.createdAt = dto.createdAt
        habit.updatedAt = dto.updatedAt
    }

    private static func linkedHabit(for dto: CompletionDTO, in context: ModelContext) -> Habit? {
        guard let hid = UUID(uuidString: dto.habitID) else { return nil }
        return try? context.fetch(
            FetchDescriptor<Habit>(predicate: #Predicate { $0.id == hid })
        ).first
    }
}
