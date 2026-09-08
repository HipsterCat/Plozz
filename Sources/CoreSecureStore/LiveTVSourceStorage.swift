import CoreModels

public enum LiveTVSourceStorage {
    public static func store(namespace: String? = nil) -> LiveTVSourcesStore {
        LiveTVSourcesStore(
            secureStore: KeychainStore(service: "com.plozz.liveTV.sources"),
            namespace: namespace
        )
    }
}
