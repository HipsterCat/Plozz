import CoreModels
import Foundation

/// Entry point for the kino.pub look-and-feel demo.
///
/// On this branch the demo is the **default** for Debug builds, because a build
/// launched from the Home screen of a real Apple TV or iPhone has no launch
/// environment to read — tapping an icon is how it will actually be looked at.
/// Set `PLOZZ_KINOPUB_DEMO=0` to run the same build as ordinary Plozz.
///
/// Release builds never enable it.
public enum KinoPubDemo {
    public static var isEnabled: Bool {
        #if DEBUG
            ProcessInfo.processInfo.environment["PLOZZ_KINOPUB_DEMO"] != "0"
        #else
            false
        #endif
    }

    /// The account store the demo runs on: one fake account, in memory, never
    /// written to the Keychain or anywhere else.
    public static func makeAccountStore() -> KinoPubDemoAccountStore {
        KinoPubDemoAccountStore()
    }

    /// Points the managed provider kinds at the offline catalogue.
    ///
    /// Registered under the existing kinds on purpose: adding a `ProviderKind`
    /// case would force every exhaustive switch in the app to grow a branch for
    /// a provider that only exists in a demo build.
    public static func install(into registry: ProviderRegistry) {
        for kind in [ProviderKind.jellyfin, .emby, .plex] {
            registry.register(kind) { context in
                KinoPubDemoProvider(session: context.session, accountID: context.accountID)
            }
        }
    }

    public static func makeRegistry() -> ProviderRegistry {
        let registry = ProviderRegistry()
        install(into: registry)
        return registry
    }
}
