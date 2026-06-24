#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore
#if canImport(FirebaseFirestoreSwift)
import FirebaseFirestoreSwift
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

/// Firestore implementation of `SyncBackend`.
///
/// Layout: `spaces/{syncCode}/habits/{id}` and `spaces/{syncCode}/completions/{id}`.
/// Offline persistence and retries are handled by the Firestore SDK. We skip snapshots
/// with pending local writes to avoid echoing our own changes back into the store.
public final class FirestoreSyncBackend: SyncBackend {
    private let db = Firestore.firestore()
    private var habitsListener: ListenerRegistration?
    private var completionsListener: ListenerRegistration?
    private var spaceCode = ""

    public init() {}

    private func habitsRef() -> CollectionReference {
        db.collection("spaces").document(spaceCode).collection("habits")
    }

    private func completionsRef() -> CollectionReference {
        db.collection("spaces").document(spaceCode).collection("completions")
    }

    public func start(
        spaceCode: String,
        onHabits: @escaping ([HabitDTO]) -> Void,
        onCompletions: @escaping ([CompletionDTO]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.spaceCode = spaceCode

        let attach = { [weak self] in
            guard let self else { return }
            self.habitsListener = self.habitsRef().addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                guard let snapshot, !snapshot.metadata.hasPendingWrites else { return }
                onHabits(snapshot.documents.compactMap { try? $0.data(as: HabitDTO.self) })
            }
            self.completionsListener = self.completionsRef().addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                guard let snapshot, !snapshot.metadata.hasPendingWrites else { return }
                onCompletions(snapshot.documents.compactMap { try? $0.data(as: CompletionDTO.self) })
            }
        }

        #if canImport(FirebaseAuth)
        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { _, error in
                if let error { onError(error) }
                attach()
            }
        } else {
            attach()
        }
        #else
        attach()
        #endif
    }

    public func stop() {
        habitsListener?.remove(); habitsListener = nil
        completionsListener?.remove(); completionsListener = nil
    }

    public func upsertHabit(_ dto: HabitDTO) {
        try? habitsRef().document(dto.id).setData(from: dto, merge: true)
    }

    public func upsertCompletion(_ dto: CompletionDTO) {
        try? completionsRef().document(dto.id).setData(from: dto, merge: true)
    }
}
#endif
