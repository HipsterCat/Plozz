import XCTest
@testable import CoreModels

final class TrueHDAtmosSettingsTests: XCTestCase {
    func testDefaultAndOlderPayloadsKeepAutomaticAtmosEnabled() throws {
        XCTAssertTrue(PlaybackSettings.default.trueHDAtmosEnabled)
        for payload in [
            #"{}"#,
            #"{"trueHDAtmosEnabled":null}"#,
            #"{"trueHDAtmosEnabled":"unknown"}"#
        ] {
            let settings = try JSONDecoder().decode(PlaybackSettings.self, from: Data(payload.utf8))
            XCTAssertTrue(settings.trueHDAtmosEnabled)
        }
    }

    func testBothChoicesRoundTripWithoutChangingOtherAudioPreferences() throws {
        for enabled in [false, true] {
            let settings = PlaybackSettings(
                audioLanguagePreference: .language("ja"),
                trueHDAtmosEnabled: enabled,
                rememberAudioTrackPerSeries: false
            )
            XCTAssertEqual(
                try JSONDecoder().decode(PlaybackSettings.self, from: JSONEncoder().encode(settings)),
                settings
            )
        }
    }

    @MainActor
    func testBindingRestoresAndTransfersOnlyTheSelectedProfilesChoice() throws {
        let suite = "TrueHDAtmosSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let primaryStore = PlaybackSettingsStore(defaults: defaults)
        let guestStore = PlaybackSettingsStore(defaults: defaults, namespace: "guest")
        let guest = PlaybackSettingsModel(store: guestStore)
        guest.settings.trueHDAtmosEnabled = false

        XCTAssertTrue(PlaybackSettingsModel(store: primaryStore).settings.trueHDAtmosEnabled)
        XCTAssertFalse(PlaybackSettingsModel(store: guestStore).settings.trueHDAtmosEnabled)
        XCTAssertTrue(guestStore.load().rememberAudioTrackPerSeries)

        let snapshot = ProfileSettingsTransfer.capture(namespace: "guest", defaults: defaults)
        ProfileSettingsTransfer.apply(snapshot, namespace: "restored", defaults: defaults)
        XCTAssertFalse(
            PlaybackSettingsStore(defaults: defaults, namespace: "restored").load().trueHDAtmosEnabled
        )
        guest.settings.trueHDAtmosEnabled = true
        XCTAssertTrue(guestStore.load().trueHDAtmosEnabled)
        XCTAssertFalse(
            PlaybackSettingsStore(defaults: defaults, namespace: "restored").load().trueHDAtmosEnabled
        )
    }
}
