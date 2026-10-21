import CoreModels
import ProviderIPTV

public enum DefaultAccountStoreFactory {
    public static func make() throws -> AccountStore {
        #if canImport(Security)
        let secureStore = KeychainStore()
        let localStateStore = try DurableLocalStateStoreFactory.userIndependent()
        let store = AccountStore(
            secureStore: secureStore,
            mediaCredentialVault: MediaCredentialVault(secureStore: secureStore),
            credentialJournal: try CredentialMutationJournal(store: localStateStore)
        )
        enableCatalogMaintenance(store)
        return store
        #else
        return AccountStore(secureStore: InMemorySecureStore())
        #endif
    }

    public static func makeCredentialOnlyFallback() -> AccountStore {
        #if canImport(Security)
        let store = AccountStore(secureStore: KeychainStore())
        enableCatalogMaintenance(store)
        return store
        #else
        AccountStore(secureStore: InMemorySecureStore())
        #endif
    }

    #if canImport(Security)
    private static func enableCatalogMaintenance(_ store: AccountStore) {
        store.enableIPTVCatalogMaintenance(
            directory: IPTVCatalogStorage.cacheDirectory,
            // A per-system-user fallback cannot authorize deleting household-wide caches.
            inventoryStore: KeychainStore(fallbackToPerUser: false)
        )
    }
    #endif
}
