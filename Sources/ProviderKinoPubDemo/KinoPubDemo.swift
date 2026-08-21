import CoreModels
import Foundation

/// Entry point for the kino.pub look-and-feel demo.
///
/// Off unless the launch environment asks for it, so a normal build of Plozz is
/// bit-for-bit unaffected:
///
///     SIMCTL_CHILD_PLOZZ_KINOPUB_DEMO=1 xcrun simctl launch booted com.thatcube.plozz
///
/// or tick the scheme's environment variable `PLOZZ_KINOPUB_DEMO=1` in Xcode.
public enum KinoPubDemo {
    public static var isEnabled: Bool {
        #if DEBUG
            ProcessInfo.processInfo.environment["PLOZZ_KINOPUB_DEMO"] == "1"
        #else
            false
        #endif
    }

    /// The account store and provider registry the demo runs on. Handed to
    /// `AppState` in place of the Keychain-backed pair.
    public static func makeAccountStore() -> KinoPubDemoAccountStore {
        KinoPubDemoAccountStore()
    }

    public static func makeRegistry() -> ProviderRegistry {
        let registry = ProviderRegistry()
        // Registered under `.jellyfin` on purpose: adding a `ProviderKind` case
        // would force every exhaustive switch in the app to grow a branch for a
        // provider that only exists in a demo build.
        registry.register(.jellyfin) { context in
            KinoPubDemoProvider(session: context.session, accountID: context.accountID)
        }
        return registry
    }
}
