import CoreModels
import CoreSecureStore
import Foundation
import ProviderKinoPubDemo

/// Keeps the offline demo from inheriting a real household "watch nothing"
/// profile selection — that left Home empty while Watchlist (universal) still
/// showed items.
public enum KinoPubDemoProfileSelection {
    /// Same Keychain-backed profiles model as a normal launch, seeded so a
    /// brand-new default profile inherits the demo account.
    @MainActor
    public static func makeProfilesModel() -> ProfilesModel {
        #if canImport(Security)
        ProfilesModel(
            store: ProfileStore(secureStore: KeychainStore(service: "com.plozz.app.household")),
            defaultActiveAccountIDs: [KinoPubDemo.accountID]
        )
        #else
        ProfilesModel(defaultActiveAccountIDs: [KinoPubDemo.accountID])
        #endif
    }

    /// Pins every profile onto the demo account before `reloadAccounts()`.
    ///
    /// A real household often leaves an explicit empty selection ("watch
    /// nothing") in Keychain; with only the in-memory demo store that hides
    /// Home while the universal Watchlist tab still has items.
    @MainActor
    public static func ensureDemoAccountSelected(_ profiles: ProfilesModel) {
        guard KinoPubDemo.isEnabled else { return }
        let demo = [KinoPubDemo.accountID]
        for profile in profiles.profiles {
            let stored = profiles.storedActiveAccountIDs(for: profile.id) ?? []
            if Set(stored) != Set(demo) {
                profiles.setActiveAccountIDs(demo, for: profile.id)
            }
        }
    }
}
