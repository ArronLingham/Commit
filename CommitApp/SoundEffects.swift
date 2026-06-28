import AppKit

/// Small sound cues for the app (macOS).
enum SoundEffects {
    /// Retained so the sound object isn't deallocated before it finishes playing
    /// (a freshly-created, unreferenced `NSSound` often won't sound).
    private static let click = NSSound(named: "Pop")

    /// A short, satisfying click when a habit is checked off.
    static func playCheck() {
        click?.stop()
        click?.play()
    }
}
