import SwiftUI
import SwiftData
import CommitCore

@main
struct CommitApp: App {
    private let container = SharedModelContainer.shared
    @AppStorage(showMenuBarIconKey, store: CommitConstants.sharedDefaults)
    private var showMenuBarIcon = true

    init() {
        // Re-arm the daily reminder for returning users (no-op / no prompt if disabled).
        ReminderScheduler.refresh()
        // Resume iPhone sync (watches the shared iCloud Drive folder) if the user enabled it.
        MainActor.assumeIsolated { PhoneSyncService.shared.startIfEnabled() }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
        }
        .modelContainer(container)
        .defaultSize(width: 700, height: 720)

        #if os(macOS)
        // Quick check-off from the menu bar.
        MenuBarExtra("Commit", systemImage: "checkmark.seal", isInserted: $showMenuBarIcon) {
            MenuBarView()
                .modelContainer(container)
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .modelContainer(container)
                .frame(width: 420, height: 460)
        }
        #endif
    }
}
