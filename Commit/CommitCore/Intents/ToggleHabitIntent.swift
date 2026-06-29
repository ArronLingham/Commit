import Foundation
import AppIntents
import SwiftData

/// Toggle a habit's completion for today. Used by the interactive widget, the menu bar,
/// and Shortcuts/Siri — all share the same write path via `HabitActions`.
public struct ToggleHabitIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Habit"
    public static var description = IntentDescription("Mark a habit complete or incomplete for today.")
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Habit ID")
    public var habitID: String

    public init() {}

    public init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: habitID) else { return .result() }

        let context = SharedModelContainer.shared.mainContext
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == uuid })
        if let habit = try context.fetch(descriptor).first {
            HabitActions.toggleCompletion(for: habit, in: context)
        }
        return .result()
    }
}
