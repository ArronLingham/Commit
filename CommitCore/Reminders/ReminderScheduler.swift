import Foundation
import UserNotifications

/// Schedules an optional **daily local notification** reminding the user to check off habits.
/// Local notifications need no paid Apple account and fire even when the app is closed.
public enum ReminderScheduler {
    public static let enabledKey = "reminderEnabled"
    public static let hourKey = "reminderHour"
    public static let minuteKey = "reminderMinute"
    private static let identifier = "commit.daily-reminder"

    public static var isEnabled: Bool {
        get { CommitConstants.sharedDefaults.bool(forKey: enabledKey) }
        set { CommitConstants.sharedDefaults.set(newValue, forKey: enabledKey) }
    }

    /// Reminder hour (24h). Defaults to 22 (10pm) when unset.
    public static var hour: Int {
        get { (CommitConstants.sharedDefaults.object(forKey: hourKey) as? Int) ?? 22 }
        set { CommitConstants.sharedDefaults.set(newValue, forKey: hourKey) }
    }

    /// Reminder minute. Defaults to 0.
    public static var minute: Int {
        get { CommitConstants.sharedDefaults.integer(forKey: minuteKey) }
        set { CommitConstants.sharedDefaults.set(newValue, forKey: minuteKey) }
    }

    /// Schedule or cancel the reminder based on the stored preferences. Permission is only
    /// requested when the reminder is enabled, so disabled users never see a prompt.
    public static func refresh() {
        guard isEnabled else { cancel(); return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted { schedule() } else { cancel() }
            }
        }
    }

    private static func schedule() {
        let content = UNMutableNotificationContent()
        content.title = "Commit"
        content.body = "Time to check off today's habits."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(request)
    }

    private static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
