import Foundation
import SwiftData

/// Identifiers shared across the app and the widget. Change these together with the
/// values in the `.entitlements` files and `project.yml` if you re-namespace the app.
public enum CommitConstants {
    public static let appGroupID = "group.com.arronlingham.commit"
    public static let cloudKitContainerID = "iCloud.com.arronlingham.commit"
    public static let storeFileName = "Commit.store"

    /// App Group `UserDefaults` shared between the app and the widget (e.g. accent colour).
    public static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

/// Builds the SwiftData container backing the app and the widget.
///
/// The store lives in the App Group container so the widget can read it. The app
/// process owns CloudKit sync; the widget opens the same store read-side without
/// CloudKit. If the App Group / CloudKit aren't available (e.g. no paid Apple
/// Developer account yet), it falls back to a plain local store so the app still runs.
public enum SharedModelContainer {
    public static let schema = Schema([Habit.self, HabitCompletion.self])

    static func storeURL() -> URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: CommitConstants.appGroupID)
        else { return nil }
        return base.appendingPathComponent(CommitConstants.storeFileName)
    }

    public static func make(cloudKit: Bool = true, inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [config])
        }

        // Preferred: shared App Group store (so the widget can read it).
        if let url = storeURL() {
            let config = ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: cloudKit ? .automatic : .none
            )
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                return container
            }
        }

        // Fallback: local default store (no App Group / CloudKit). Keeps the app usable
        // without a paid Apple Developer account.
        let fallback = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [fallback])
    }

    /// Shared container for the app and AppIntents (CloudKit when entitled).
    public static let shared: ModelContainer = make(cloudKit: true)

    /// Read-side container for the widget process (no CloudKit initialisation).
    public static let widget: ModelContainer = make(cloudKit: false)
}
