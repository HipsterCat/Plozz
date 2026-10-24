import Foundation
import Observation

public protocol ContentRatingSettingsStoring: Sendable {
    func load() -> Bool
    func save(_ showsRatings: Bool)
}

public final class ContentRatingSettingsStore: ContentRatingSettingsStoring, @unchecked Sendable {
    public static let storageKey = "com.plozz.showsContentRatings"
    public static let defaultShowsRatings = true
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, namespace: String? = nil) {
        self.defaults = defaults
        key = SettingsKey.scoped(Self.storageKey, namespace: namespace)
    }

    public func load() -> Bool {
        defaults.object(forKey: key) as? Bool ?? Self.defaultShowsRatings
    }

    public func save(_ showsRatings: Bool) {
        defaults.set(showsRatings, forKey: key)
    }
}

@MainActor
@Observable
public final class ContentRatingSettingsModel {
    public var showsRatings: Bool {
        didSet { store.save(showsRatings) }
    }
    private let store: any ContentRatingSettingsStoring

    public init(store: any ContentRatingSettingsStoring = ContentRatingSettingsStore()) {
        self.store = store
        showsRatings = store.load()
    }
}
