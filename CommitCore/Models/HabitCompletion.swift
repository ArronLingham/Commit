import Foundation
import SwiftData

/// A single day on which a habit was completed. One per habit per day (enforced in code).
@Model
public final class HabitCompletion {
    public var id: UUID = UUID()
    /// Normalised to the start of the day so look-ups compare cleanly.
    public var day: Date = Date()
    /// Reserved for future "count" habits (e.g. glasses of water). Always >= 1 today.
    public var count: Int = 1
    public var createdAt: Date = Date()
    public var habit: Habit?

    public init(day: Date, count: Int = 1, habit: Habit? = nil) {
        self.id = UUID()
        self.day = Calendar.current.startOfDay(for: day)
        self.count = count
        self.createdAt = Date()
        self.habit = habit
    }
}
