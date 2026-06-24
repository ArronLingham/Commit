import Foundation
import SwiftData
import Combine
#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// Orchestrates cross-device sync: pushes local changes to the backend and merges
/// incoming remote changes into SwiftData. Singleton, observed by Settings for status.
///
/// Sync is **additive** — if no sync code is set (or Firebase isn't configured) the app
/// behaves exactly as a local-only app.
@MainActor
public final class SyncEngine: ObservableObject {
    public static let shared = SyncEngine()

    @Published public private(set) var status: SyncStatus = .off

    private var container: ModelContainer?
    private var backend: SyncBackend?

    private init() {}

    public var isActive: Bool { backend != nil }

    /// Call once at launch with the shared container. Starts syncing if a code is set.
    public func configure(container: ModelContainer) {
        self.container = container
        if SyncCode.current != nil { start() }
    }

    public func start() {
        guard backend == nil else { return }            // already running
        guard SyncCode.current != nil else { status = .off; return }
        guard let code = SyncCode.current else { status = .off; return }
        guard let backend = Self.makeBackend() else { status = .unavailable; return }

        self.backend = backend
        status = .syncing
        backend.start(
            spaceCode: code,
            onHabits: { dtos in Task { @MainActor in SyncEngine.shared.receiveHabits(dtos) } },
            onCompletions: { dtos in Task { @MainActor in SyncEngine.shared.receiveCompletions(dtos) } },
            onError: { error in Task { @MainActor in SyncEngine.shared.status = .error(error.localizedDescription) } }
        )
        pushAllLocal()
    }

    public func stop() {
        backend?.stop()
        backend = nil
        status = .off
    }

    public func restart() {
        stop()
        start()
    }

    // MARK: Outgoing

    public func push(habit: Habit) {
        guard let backend else { return }
        backend.upsertHabit(HabitDTO(habit))
        markSynced()
    }

    public func push(completion: HabitCompletion) {
        guard let backend else { return }
        backend.upsertCompletion(CompletionDTO(completion))
        markSynced()
    }

    /// Upload the entire local store once (e.g. when first pairing a device that already
    /// has habits). Last-write-wins reconciles anything the other device also has.
    private func pushAllLocal() {
        guard let backend, let container else { return }
        let context = container.mainContext
        if let habits = try? context.fetch(FetchDescriptor<Habit>()) {
            habits.forEach { backend.upsertHabit(HabitDTO($0)) }
        }
        if let completions = try? context.fetch(FetchDescriptor<HabitCompletion>()) {
            completions.forEach { backend.upsertCompletion(CompletionDTO($0)) }
        }
    }

    // MARK: Incoming

    private func receiveHabits(_ dtos: [HabitDTO]) {
        guard let container else { return }
        SyncMerge.apply(habits: dtos, into: container.mainContext)
        HabitActions.reloadWidgets()
        markSynced()
    }

    private func receiveCompletions(_ dtos: [CompletionDTO]) {
        guard let container else { return }
        SyncMerge.apply(completions: dtos, into: container.mainContext)
        HabitActions.reloadWidgets()
        markSynced()
    }

    private func markSynced() {
        if case .error = status { return }
        status = .synced
    }

    private static func makeBackend() -> SyncBackend? {
        #if canImport(FirebaseFirestore)
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else { return nil }   // Firebase not configured (no plist)
        #endif
        return FirestoreSyncBackend()
        #else
        return nil
        #endif
    }
}
