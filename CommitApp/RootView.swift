import SwiftUI
import CommitCore

/// Top-level UI: a single page (macOS). Settings is a separate `Settings` scene (⌘,) and the
/// menu bar is a `MenuBarExtra` — both defined in `CommitApp`.
struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HomeView()
            // Keep the Dock icon in sync with the system appearance while the app runs.
            .onAppear { AppIconManager.update(for: colorScheme) }
            .onChange(of: colorScheme) { _, newValue in
                AppIconManager.update(for: newValue)
            }
    }
}
