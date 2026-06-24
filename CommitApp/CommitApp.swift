import SwiftUI
import SwiftData
import CommitCore

@main
struct CommitApp: App {
    private let container = SharedModelContainer.shared

    init() {
        // Configure Firebase if it's set up; no-op otherwise (app stays local-only).
        SyncBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .task { SyncEngine.shared.configure(container: container) }
        }
        .modelContainer(container)

        #if os(macOS)
        // Quick check-off from the menu bar.
        MenuBarExtra("Commit", systemImage: "checkmark.seal") {
            MenuBarView()
                .modelContainer(container)
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .modelContainer(container)
                .frame(width: 420, height: 360)
        }
        #endif
    }
}
