import Foundation
import SwiftData

/// A command written by an iPhone Shortcut. The single-ID toggle format remains supported.
public struct PhoneSyncCommand: Decodable {
    private let id: String?
    private let ids: [String]?
    private let action: String

    public var habitIDs: [UUID] {
        var seen = Set<UUID>()
        return (ids ?? [id].compactMap { $0 }).compactMap { raw in
            guard let uuid = UUID(uuidString: raw), seen.insert(uuid).inserted else { return nil }
            return uuid
        }
    }

    /// Completing an already completed habit is a no-op, including when a file is replayed.
    public func shouldToggle(isCompleted: Bool) -> Bool {
        switch action {
        case "toggle": return true
        case "complete": return !isCompleted
        default: return false
        }
    }

    @MainActor
    public func apply(in context: ModelContext, on date: Date = AppClock.now) {
        for uuid in habitIDs {
            let match = try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == uuid }))
            guard let habit = match?.first, !habit.isArchived,
                  shouldToggle(isCompleted: habit.isCompleted(on: date)) else { continue }
            HabitActions.toggleCompletion(for: habit, on: date, in: context)
        }
    }
}
