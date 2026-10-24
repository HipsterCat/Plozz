import XCTest
@testable import CoreModels

final class LivePlaybackBufferTests: XCTestCase {
    func testPresetsPreserveAutomaticAndBoundExplicitCushions() {
        XCTAssertEqual(LivePlaybackBuffer.allCases, [
            .automatic, .tenSeconds, .twentySeconds, .thirtySeconds, .fortyFiveSeconds
        ])
        XCTAssertEqual(LivePlaybackBuffer.default, .automatic)
        XCTAssertEqual(LivePlaybackBuffer.allCases.map(\.seconds), [nil, 10, 20, 30, 45])
    }

    func testPersistenceAndVideoBufferIndependence() throws {
        try withDefaults { defaults in
            let store = LivePlaybackBufferStore(defaults: defaults)
            let video = PlaybackReadAheadStore(defaults: defaults)
            video.save(.fiveMinutes)
            XCTAssertEqual(store.load(), .automatic)
            for choice in LivePlaybackBuffer.allCases {
                store.save(choice)
                XCTAssertEqual(defaults.string(forKey: LivePlaybackBufferStore.storageKey), choice.rawValue)
                XCTAssertEqual(LivePlaybackBufferStore(defaults: defaults).load(), choice)
                XCTAssertEqual(video.load(), .fiveMinutes)
            }
        }
    }

    func testInvalidValuesFallBackWithoutRewritingStoredData() throws {
        try withDefaults { defaults in
            let store = LivePlaybackBufferStore(defaults: defaults)
            for value: Any in ["futurePreset", "", 45, Data([1, 2])] {
                defaults.set(value, forKey: LivePlaybackBufferStore.storageKey)
                let saved = defaults.object(forKey: LivePlaybackBufferStore.storageKey) as? NSObject
                XCTAssertEqual(store.load(), .automatic)
                XCTAssertEqual(defaults.object(forKey: LivePlaybackBufferStore.storageKey) as? NSObject, saved)
            }
            store.save(.fortyFiveSeconds)
            XCTAssertEqual(store.load(), .fortyFiveSeconds)
        }
    }

    func testDeviceChoiceDoesNotTransferWithProfiles() throws {
        try withDefaults { source in
            try withDefaults { target in
                LivePlaybackBufferStore(defaults: source).save(.fortyFiveSeconds)
                let targetStore = LivePlaybackBufferStore(defaults: target)
                targetStore.save(.tenSeconds)
                for namespace: String? in [nil, "adult", "kids"] {
                    let snapshot = ProfileSettingsTransfer.capture(namespace: namespace, defaults: source)
                    XCTAssertNil(snapshot[LivePlaybackBufferStore.storageKey])
                    ProfileSettingsTransfer.apply(snapshot, namespace: namespace, defaults: target)
                    XCTAssertEqual(targetStore.load(), .tenSeconds)
                }
            }
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "LivePlaybackBufferTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
