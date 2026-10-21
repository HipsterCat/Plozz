import XCTest
@testable import CoreModels

final class PlaybackReadAheadTests: XCTestCase {
    func testPresetOrderAndDefault() {
        XCTAssertEqual(PlaybackReadAhead.allCases, [
            .automatic, .oneMinute, .fiveMinutes, .tenMinutes, .maximumAvailable
        ])
        XCTAssertEqual(PlaybackReadAhead.default, .automatic)
    }

    func testEveryChoicePersistsAcrossStoreRecreation() throws {
        try withDefaults { defaults in
            let store = PlaybackReadAheadStore(defaults: defaults)
            XCTAssertEqual(store.load(), .automatic)
            for choice in PlaybackReadAhead.allCases {
                store.save(choice)
                XCTAssertEqual(defaults.string(forKey: PlaybackReadAheadStore.storageKey), choice.rawValue)
                XCTAssertEqual(PlaybackReadAheadStore(defaults: defaults).load(), choice)
            }
        }
    }

    func testUnknownAndWrongTypeValuesFallBackWithoutRewritingStoredData() throws {
        try withDefaults { defaults in
            let store = PlaybackReadAheadStore(defaults: defaults)
            for value: Any in ["futurePreset", "", 150, Data([1, 2])] {
                defaults.set(value, forKey: PlaybackReadAheadStore.storageKey)
                XCTAssertEqual(store.load(), .automatic)
                XCTAssertNotNil(defaults.object(forKey: PlaybackReadAheadStore.storageKey))
            }
            store.save(.fiveMinutes)
            XCTAssertEqual(store.load(), .fiveMinutes)
        }
    }

    func testDeviceChoiceNeverTransfersWithAnyProfile() throws {
        try withDefaults { source in
            try withDefaults { target in
                PlaybackReadAheadStore(defaults: source).save(.maximumAvailable)
                let targetStore = PlaybackReadAheadStore(defaults: target)
                targetStore.save(.oneMinute)
                for namespace: String? in [nil, "adult", "kids"] {
                    let snapshot = ProfileSettingsTransfer.capture(namespace: namespace, defaults: source)
                    XCTAssertNil(snapshot[PlaybackReadAheadStore.storageKey])
                    ProfileSettingsTransfer.apply(snapshot, namespace: namespace, defaults: target)
                    XCTAssertEqual(targetStore.load(), .oneMinute)
                    XCTAssertEqual(PlaybackReadAheadStore(defaults: source).load(), .maximumAvailable)
                }
            }
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "PlaybackReadAheadTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
