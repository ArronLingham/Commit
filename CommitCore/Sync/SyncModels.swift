import Foundation

/// High-level sync state, surfaced in Settings.
public enum SyncStatus: Equatable, Sendable {
    case off            // no sync code set
    case unavailable    // Firebase not configured / not compiled in
    case syncing
    case synced
    case error(String)
}

// MARK: - Transfer objects (Codable, backend-agnostic)

public struct HabitDTO: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var iconName: String
    public var colorHex: String
    public var scheduleRaw: String
    public var weekdays: [Int]
    public var targetPerWeek: Int
    public var createdAt: Date
    public var sortOrder: Int
    public var isArchived: Bool
    public var isDeleted: Bool
    public var updatedAt: Date

    public init(_ h: Habit) {
        self.id = h.id.uuidString
        self.name = h.name
        self.iconName = h.iconName
        self.colorHex = h.colorHex
        self.scheduleRaw = h.scheduleRaw
        self.weekdays = h.weekdays
        self.targetPerWeek = h.targetPerWeek
        self.createdAt = h.createdAt
        self.sortOrder = h.sortOrder
        self.isArchived = h.isArchived
        self.isDeleted = h.isDeleted
        self.updatedAt = h.updatedAt
    }
}

public struct CompletionDTO: Codable, Sendable, Identifiable {
    public var id: String
    public var habitID: String
    public var day: Date
    public var count: Int
    public var createdAt: Date
    public var isDeleted: Bool
    public var updatedAt: Date

    public init(_ c: HabitCompletion) {
        self.id = c.id.uuidString
        self.habitID = c.habit?.id.uuidString ?? ""
        self.day = c.day
        self.count = c.count
        self.createdAt = c.createdAt
        self.isDeleted = c.isDeleted
        self.updatedAt = c.updatedAt
    }
}
