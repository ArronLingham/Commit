import SwiftUI
import SwiftData
import CommitCore

@main
struct CommitApp: App {
    private let container = SharedModelContainer.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
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
