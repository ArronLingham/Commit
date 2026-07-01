import Foundation

/// The app's single source of "now". Everything that means "today" reads `AppClock.now`
/// instead of `Date()` so **Tester Mode** can override the current date to exercise
/// scheduling, streaks, and weekly/monthly targets. Off by default → the real date.
public enum AppClock {
    public static let enabledKey = "testerModeEnabled"
    /// Stored as a `timeIntervalSinceReferenceDate` so it round-trips through UserDefaults.
    public static let overrideKey = "testerOverrideDate"

    public static var isEnabled: Bool {
        get { CommitConstants.sharedDefaults.bool(forKey: enabledKey) }
        set { CommitConstants.sharedDefaults.set(newValue, forKey: enabledKey) }
    }

    /// The simulated date. Defaults to the real now until the tester sets one.
    public static var overrideDate: Date {
        get {
            guard let t = CommitConstants.sharedDefaults.object(forKey: overrideKey) as? Double else {
                return Date()
            }
            return Date(timeIntervalSinceReferenceDate: t)
        }
        set { CommitConstants.sharedDefaults.set(newValue.timeIntervalSinceReferenceDate, forKey: overrideKey) }
    }

    /// The app's current date: the tester override when Tester Mode is on, else the real date.
    public static var now: Date {
        isEnabled ? overrideDate : Date()
    }
}
