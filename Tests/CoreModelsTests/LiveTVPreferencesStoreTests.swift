import XCTest
@testable import CoreModels

final class LiveTVPreferencesStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "LiveTVPreferencesStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testMissingPreferencesLoadAsEmpty() throws {
        let store = LiveTVPreferencesStore(defaults: makeDefaults(), namespace: nil)

        XCTAssertEqual(try store.load(), .empty)
    }

    func testPreferencesRoundTripAcrossStoreInstances() throws {
        let defaults = makeDefaults()
        let preferences = LiveTVPreferences(
            favoriteIDs: ["channel-1", "channel-3"],
            recentChannelIDs: ["channel-3", "channel-2", "channel-1"]
        )

        try LiveTVPreferencesStore(defaults: defaults, namespace: nil).save(preferences)
        let reopened = LiveTVPreferencesStore(defaults: defaults, namespace: nil)

        XCTAssertEqual(try reopened.load(), preferences)
    }

    func testEmptyPreferencesRoundTrip() throws {
        let defaults = makeDefaults()
        let store = LiveTVPreferencesStore(defaults: defaults, namespace: nil)

        try store.save(.empty)

        XCTAssertEqual(try store.load(), .empty)
        XCTAssertNotNil(defaults.data(forKey: LiveTVPreferencesStore.baseKey))
    }

    func testNamespacesIsolateProfiles() throws {
        let defaults = makeDefaults()
        let primary = LiveTVPreferencesStore(defaults: defaults, namespace: nil)
        let secondary = LiveTVPreferencesStore(
            defaults: defaults,
            namespace: "profile-secondary"
        )

        try primary.save(LiveTVPreferences(
            favoriteIDs: ["primary-favorite"],
            recentChannelIDs: ["primary-recent"]
        ))
        try secondary.save(LiveTVPreferences(
            favoriteIDs: ["secondary-favorite"],
            recentChannelIDs: ["secondary-recent"]
        ))

        XCTAssertEqual(try primary.load().favoriteIDs, ["primary-favorite"])
        XCTAssertEqual(try secondary.load().favoriteIDs, ["secondary-favorite"])
        XCTAssertEqual(try primary.load().recentChannelIDs, ["primary-recent"])
        XCTAssertEqual(try secondary.load().recentChannelIDs, ["secondary-recent"])
    }

    func testRecentChannelsAreUniqueAndBoundedToThree() throws {
        let preferences = LiveTVPreferences(
            favoriteIDs: [],
            recentChannelIDs: ["one", "two", "one", "three", "four"]
        )

        XCTAssertEqual(preferences.recentChannelIDs, ["one", "two", "three"])

        let data = try JSONEncoder().encode([
            "favoriteIDs": [String](),
            "recentChannelIDs": ["one", "two", "one", "three", "four"],
        ])
        let decoded = try JSONDecoder().decode(LiveTVPreferences.self, from: data)
        XCTAssertEqual(decoded.recentChannelIDs, ["one", "two", "three"])
    }

    func testCorruptPreferencesSurfaceTypedErrorAndAreNotOverwritten() throws {
        let defaults = makeDefaults()
        let key = SettingsKey.scoped(
            LiveTVPreferencesStore.baseKey,
            namespace: "profile-corrupt"
        )
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: key)
        let store = LiveTVPreferencesStore(
            defaults: defaults,
            namespace: "profile-corrupt"
        )

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? LiveTVPreferencesStoreError, .decodingFailed)
        }
        XCTAssertThrowsError(try store.save(.empty)) { error in
            XCTAssertEqual(error as? LiveTVPreferencesStoreError, .decodingFailed)
        }
        XCTAssertEqual(defaults.data(forKey: key), corrupt)
    }

    func testWrongStoredTypeSurfacesTypedErrorAndIsNotOverwritten() throws {
        let defaults = makeDefaults()
        let key = SettingsKey.scoped(
            LiveTVPreferencesStore.baseKey,
            namespace: "profile-wrong-type"
        )
        defaults.set("not-data", forKey: key)
        let store = LiveTVPreferencesStore(
            defaults: defaults,
            namespace: "profile-wrong-type"
        )

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? LiveTVPreferencesStoreError, .invalidStoredValue)
        }
        XCTAssertThrowsError(try store.save(.empty)) { error in
            XCTAssertEqual(error as? LiveTVPreferencesStoreError, .invalidStoredValue)
        }
        XCTAssertEqual(defaults.string(forKey: key), "not-data")
    }
}
