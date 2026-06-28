import AppKit

/// Small sound cues for the app (macOS).
enum SoundEffects {
    /// A short, satisfying click when a habit is checked off.
    static func playCheck() {
        NSSound(named: "Pop")?.play()
    }
}
