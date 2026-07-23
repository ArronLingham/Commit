import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Swaps the running app's Dock icon between a light and dark variant to match the current
/// appearance. (macOS only changes the *running* Dock icon this way — the static Finder /
/// Launchpad icon stays the compiled `AppIcon`.)
enum AppIconManager {
    static func update(for colorScheme: ColorScheme) {
        #if canImport(AppKit)
        let name = colorScheme == .dark ? "AppIconDark" : "AppIconLight"
        if let image = NSImage(named: name) {
            NSApplication.shared.applicationIconImage = image
        }
        #endif
    }
}
