import Foundation

/// Abstracts the remote store so the engine is testable and the backend swappable
/// (Firestore today; a mock in tests; something else later).
public protocol SyncBackend: AnyObject {
    /// Begin syncing a space. The callbacks deliver remote records (initial + live).
    func start(
        spaceCode: String,
        onHabits: @escaping ([HabitDTO]) -> Void,
        onCompletions: @escaping ([CompletionDTO]) -> Void,
        onError: @escaping (Error) -> Void
    )
    func stop()
    func upsertHabit(_ dto: HabitDTO)
    func upsertCompletion(_ dto: CompletionDTO)
}
