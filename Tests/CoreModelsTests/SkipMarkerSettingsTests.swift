import XCTest
@testable import CoreModels

final class SkipMarkerSettingsTests: XCTestCase {
    func testDefaultsKeepManualSkippingForAllContentWithFiveSecondAutomaticDelay() {
        let settings = PlaybackSettings.default
        XCTAssertTrue(settings.skipMarkersEnabled)
        XCTAssertEqual(settings.skipAutomaticDelaySeconds, 5)
        XCTAssertEqual(settings.skipContentCategories, Set(ContentCategory.allCases))
        for category in ContentCategory.allCases {
            XCTAssertEqual(settings.skipMarkerModes(for: category).mode(for: .intro), .on)
        }
    }

    func testLegacyModesPreserveBehaviorAndTiming() throws {
        for mode in SkipIntrosMode.allCases {
            let settings = try JSONDecoder().decode(
                PlaybackSettings.self,
                from: JSONSerialization.data(withJSONObject: ["skipIntros": mode.rawValue])
            )
            XCTAssertEqual(settings.skipIntros, mode)
            XCTAssertEqual(settings.skipMarkersEnabled, mode != .off)
            XCTAssertEqual(settings.skipMarkerModes.mode(for: .intro), mode)
            XCTAssertEqual(settings.configuredSkipDelay(), mode == .autoInstant ? 0 : 5)
        }
    }

    func testLegacyMixedInstantAndDelayedOverridesKeepIndependentTiming() throws {
        let settings = try JSONDecoder().decode(PlaybackSettings.self, from: Data(
            #"{"skipIntros":"autoInstant","skipModeOverrides":{"intro":"autoDelay","credits":"on","recap":"off"}}"#.utf8
        ))
        XCTAssertEqual(settings.skipMarkerModes.mode(for: .intro), .autoDelay)
        XCTAssertEqual(settings.skipMarkerModes.delay(for: .intro), 5)
        XCTAssertEqual(settings.skipMarkerModes.mode(for: .preview), .autoInstant)
        XCTAssertEqual(settings.skipMarkerModes.mode(for: .credits), .on)
        XCTAssertEqual(settings.skipMarkerModes.mode(for: .recap), .off)
    }

    func testMasterSwitchRestoresConfigurationIncludingAnOffBaseWithActiveOverrides() throws {
        for base in [SkipIntrosMode.autoDelay, .off] {
            var settings = PlaybackSettings(
                skipIntros: base, skipModeOverrides: [.intro: .autoInstant, .credits: .autoDelay],
                skipContentCategories: [.tvShow, .anime], skipAutomaticDelaySeconds: 12,
                skipAutomaticDelayOverrides: [.intro: 0, .credits: 23], useCommunityMarkers: false
            )
            let original = settings
            settings.setSkipMarkersEnabled(false)
            XCTAssertEqual(settings.skipMarkerModes, .allOff)
            settings = try JSONDecoder().decode(PlaybackSettings.self, from: JSONEncoder().encode(settings))
            settings.setSkipMarkersEnabled(true)
            XCTAssertEqual(settings, original)
        }
    }

    func testEnablingALegacyOffProfileStartsWithTheManualButton() throws {
        var settings = try JSONDecoder().decode(PlaybackSettings.self, from: Data(#"{"skipIntros":false}"#.utf8))
        settings.setSkipMarkersEnabled(true)
        XCTAssertEqual(settings.skipMarkerModes.mode(for: .intro), .on)
        XCTAssertEqual(settings.skipAutomaticDelaySeconds, 5)
    }

    func testContentSwitchesAreIndependentAndDoNotChangeStoredModes() {
        var settings = PlaybackSettings(skipIntros: .autoDelay)
        for category in [ContentCategory.movie, .tvShow, .anime] {
            settings.skipContentCategories.remove(category)
            XCTAssertEqual(settings.skipMarkerModes(for: category), .allOff)
            for other in ContentCategory.allCases where other != category {
                XCTAssertEqual(settings.skipMarkerModes(for: other).mode(for: .intro), .autoDelay)
            }
            settings.skipContentCategories.insert(category)
        }
        XCTAssertEqual(settings.skipIntros, .autoDelay)
    }

    func testImmediateAndEverySecondThroughThirtyResolveToTheChosenTiming() {
        XCTAssertEqual(PlaybackSettings.skipAutomaticDelayOptions, Array(0...30))
        var settings = PlaybackSettings(skipIntros: .autoDelay)
        for seconds in 0...30 {
            settings.setSkipAutomaticDelay(seconds)
            XCTAssertEqual(settings.configuredSkipDelay(), seconds)
            XCTAssertEqual(settings.skipMarkerModes.mode(for: .intro), seconds == 0 ? .autoInstant : .autoDelay)
            XCTAssertEqual(settings.skipMarkerModes.delay(for: .intro), TimeInterval(seconds))
        }
    }

    func testSeparateMarkersInheritCurrentTimingThenRemainIndependent() {
        var settings = PlaybackSettings(skipIntros: .autoDelay, skipAutomaticDelaySeconds: 12)
        settings.setSkipMarkersSeparately(true)
        for kind in MediaSegment.Kind.skippable {
            XCTAssertEqual(settings.configuredSkipDelay(for: kind), 12)
        }
        settings.setSkipAutomaticDelay(0, for: .intro)
        settings.setSkipAutomaticDelay(30, for: .credits)
        settings.setConfiguredSkipMode(.off, for: .commercial)
        XCTAssertEqual(settings.skipMarkerModes.mode(for: .intro), .autoInstant)
        XCTAssertEqual(settings.skipMarkerModes.delay(for: .credits), 30)
        XCTAssertEqual(settings.skipMarkerModes.delay(for: .recap), 12)
        XCTAssertEqual(settings.skipMarkerModes.mode(for: .commercial), .off)
        settings.setSkipMarkersSeparately(false)
        XCTAssertEqual(settings.skipMarkerModes.delay(for: .intro), 12)
    }

    func testMarkerEditsDoNotRequireSeparateModeOrResetInheritedChoices() throws {
        var settings = PlaybackSettings(skipIntros: .autoDelay, skipAutomaticDelaySeconds: 12)
        settings.setSkipAutomaticDelay(0, for: .intro)
        settings.setConfiguredSkipMode(.off, for: .credits)
        settings.setSkipAutomaticDelay(30, for: .recap)
        XCTAssertEqual(settings.skipMarkerModes.mode(for: .intro), .autoInstant)
        XCTAssertEqual(settings.skipMarkerModes.mode(for: .credits), .off)
        XCTAssertEqual(settings.skipMarkerModes.delay(for: .recap), 30)
        for kind in [MediaSegment.Kind.preview, .commercial] {
            XCTAssertEqual(settings.configuredSkipMode(for: kind), .autoDelay)
            XCTAssertEqual(settings.configuredSkipDelay(for: kind), 12)
        }
        let configured = settings
        settings.setSkipMarkersEnabled(false)
        settings = try JSONDecoder().decode(PlaybackSettings.self, from: JSONEncoder().encode(settings))
        settings.setSkipMarkersEnabled(true)
        XCTAssertEqual(settings, configured)
    }

    func testDelayBoundsAndZeroAreConsistentForImportedPreferences() throws {
        var settings = try JSONDecoder().decode(PlaybackSettings.self, from: Data(
            #"{"skipIntros":"autoDelay","skipAutomaticDelaySeconds":-10,"skipModeOverrides":{"credits":"autoDelay"},"skipAutomaticDelayOverrides":{"credits":99}}"#.utf8
        ))
        XCTAssertEqual(settings.skipAutomaticDelaySeconds, 0)
        XCTAssertEqual(settings.skipMarkerModes.mode(for: .intro), .autoInstant)
        XCTAssertEqual(settings.skipMarkerModes.delay(for: .credits), 30)
        settings.skipAutomaticDelaySeconds = 500
        settings.skipAutomaticDelayOverrides = [.credits: -20]
        XCTAssertEqual(settings.skipAutomaticDelaySeconds, 30)
        XCTAssertEqual(settings.skipMarkerModes.mode(for: .credits), .autoInstant)
    }

    func testProfileStoresRetainAllPreferencesWithoutLeakingToAnotherProfile() throws {
        let suite = "SkipMarkerSettingsTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = PlaybackSettingsStore(defaults: defaults, namespace: "first")
        let second = PlaybackSettingsStore(defaults: defaults, namespace: "second")
        let settings = PlaybackSettings(
            skipIntros: .autoDelay, skipModeOverrides: [.credits: .autoDelay],
            skipMarkersEnabled: false, skipContentCategories: [.anime],
            skipAutomaticDelaySeconds: 8, skipAutomaticDelayOverrides: [.credits: 21]
        )
        first.save(settings)
        XCTAssertEqual(first.load(), settings)
        XCTAssertEqual(second.load(), .default)
    }
}
