import SwiftUI
import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

/// Handles notification presentation. Without a delegate, macOS suppresses local notifications
/// while the app is frontmost — so the daily reminder would never show while you're using Commit.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Show reminders even when Commit is the active app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Tapping a reminder brings the app forward.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        #if canImport(AppKit)
        NSApp.activate(ignoringOtherApps: true)
        #endif
        completionHandler()
    }
}
