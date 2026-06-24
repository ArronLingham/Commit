import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// Configures Firebase at launch — but only if the SDK is linked *and* a
/// `GoogleService-Info.plist` is bundled. Safe to call before Firebase is set up:
/// it simply does nothing, so the app keeps working local-only.
public enum SyncBootstrap {
    public static func configureIfAvailable() {
        #if canImport(FirebaseCore)
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        #endif
    }
}
