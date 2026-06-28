import SwiftUI
import CommitCore

/// Top-level UI: a single page (macOS). Settings is a separate `Settings` scene (⌘,) and the
/// menu bar is a `MenuBarExtra` — both defined in `CommitApp`.
struct RootView: View {
    var body: some View {
        HomeView()
    }
}
