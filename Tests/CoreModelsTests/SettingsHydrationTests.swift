import Foundation
import XCTest
@testable import CoreModels

@MainActor
final class SettingsHydrationTests: XCTestCase {
    func testLoadingMigratedAppearanceDoesNotWritePreferencesAgain() throws {
        let suite = "SettingsHydrationTests.\(UUID())"
        let defaults = try XCTUnwrap(WriteCountingDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for namespace: String? in [nil, "viewer"] {
            let artwork = ArtworkSettingsStore(defaults: defaults, namespace: namespace)
            let captions = CardCaptionSettingsStore(defaults: defaults, namespace: namespace)
            let expectedArtwork = artwork.load()
            let expectedCaptions = captions.load()
            // Exercise the saved-data paths as well as a migrated default with no blob.
            for saved in [false, true] {
                if saved {
                    artwork.save(expectedArtwork)
                    captions.save(expectedCaptions)
                }
                defaults.resetWrites()
                for _ in 0..<3 {
                    XCTAssertEqual(artwork.load(), expectedArtwork)
                    XCTAssertEqual(captions.load(), expectedCaptions)
                }
                XCTAssertEqual(defaults.writes, 0, "Profile activation must not repeat migration writes.")
            }
        }
    }

    func testSubtitleHydrationDoesNotSaveOrBroadcastAndEditsStillPersist() throws {
        let suite = "SubtitleHydrationTests.\(UUID())"
        let defaults = try XCTUnwrap(WriteCountingDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SubtitleStyleStore(defaults: defaults, namespace: "viewer")
        for liveStyle: SubtitleStyle? in [nil, .default] {
            let expected = SubtitleStylePreferences(base: .profileDefault, liveTV: liveStyle)
            store.save(expected)
            defaults.resetWrites()
            let model = SubtitleStyleModel(store: store)
            XCTAssertEqual(defaults.writes, 0)
            XCTAssertEqual(store.load(), expected)
            XCTAssertEqual(model.liveTVStyle, liveStyle)
            model.style.fontScale = 1.25
            XCTAssertGreaterThan(defaults.writes, 0)
            XCTAssertEqual(store.load().base.fontScale, 1.25)
            XCTAssertEqual(store.load().liveTV, liveStyle)
        }
    }
}

private final class WriteCountingDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var writeCount = 0
    var writes: Int { lock.withLock { writeCount } }
    func resetWrites() { lock.withLock { writeCount = 0 } }

    override func set(_ value: Any?, forKey key: String) {
        lock.withLock { writeCount += 1 }
        super.set(value, forKey: key)
    }

    override func set(_ value: Bool, forKey key: String) {
        lock.withLock { writeCount += 1 }
        super.set(value, forKey: key)
    }
}
