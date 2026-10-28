import CoreModels
import Observation

@MainActor
@Observable
public final class WatchlistBrowseModel {
    public var preferences: WatchlistBrowsePreferences {
        didSet { store.save(preferences) }
    }
    private let store: WatchlistBrowsePreferencesStore

    public init(store: WatchlistBrowsePreferencesStore) {
        self.store = store
        preferences = store.load()
    }
}
