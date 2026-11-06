import SwiftUI
import SwiftData
import CommitCore

@main
struct CommitApp: App {
    private let container = SharedModelContainer.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(showMenuBarIconKey, store: CommitConstants.sharedDefaults)
    private var showMenuBarIcon = true

    init() {
        // Map the removed Upcoming option to the complete Other habits list.
        if CommitConstants.sharedDefaults.string(forKey: OtherHabitsStyle.storageKey) == "upcoming" {
            CommitConstants.sharedDefaults.set(OtherHabitsStyle.collapsible.rawValue, forKey: OtherHabitsStyle.storageKey)
        }
        // Re-arm the daily reminder for returning users (no-op / no prompt if disabled).
        ReminderScheduler.refresh()
        // Resume iPhone sync (watches the shared iCloud Drive folder) if the user enabled it.
        MainActor.assumeIsolated { PhoneSyncService.shared.startIfEnabled() }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .focusEffectForInput()
        }
        .modelContainer(container)
        .defaultSize(width: 700, height: 720)

        #if os(macOS)
        // Quick check-off from the menu bar.
        MenuBarExtra("Commit", systemImage: "checkmark.seal", isInserted: $showMenuBarIcon) {
            MenuBarView()
                .focusEffectForInput()
                .modelContainer(container)
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .focusEffectForInput()
                .modelContainer(container)
                .frame(width: 420, height: 460)
        }
        #endif
    }
}
