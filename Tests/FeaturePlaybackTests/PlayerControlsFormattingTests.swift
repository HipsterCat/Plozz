import XCTest
import CoreModels
@testable import FeaturePlayback

/// Tests the pure subtitle-style label formatters extracted from
/// `PlayerControls`. These pin the human-readable readouts (precise positions,
/// signed offsets, preset color names, edge summary) that the style rows show.
final class PlayerControlsFormattingTests: XCTestCase {
    func testAvenirSelectionPersistsPerProfileWithoutChangingDefaults() throws {
        let suite = "SubtitleAvenirTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SubtitleStyleStore(defaults: defaults, namespace: "avenir-profile")
        let primary = SubtitleStyleStore(defaults: defaults)
        var preferences = SubtitleStylePreferences.default
        preferences.base.fontFamily = .avenir
        preferences.base.fontWeight = .semibold
        preferences.base.verticalPosition = 0.005
        store.save(preferences)
        XCTAssertEqual(store.load(), preferences)
        XCTAssertEqual(primary.load(), .default)
        XCTAssertEqual(SubtitleStyle.default.fontFamily, .atkinson)
        XCTAssertEqual(SubtitleFontFamily.avenir.displayName, "Avenir")
        XCTAssertTrue(SubtitleFontFamily.allCases.contains(.avenir))
    }

    func testExistingFontCandidateFallbacksAreUnchanged() {
        XCTAssertEqual(SubtitleFontFamily.atkinson.postScriptNameCandidates(
            weight: .semibold, isItalic: true
        ), ["AtkinsonHyperlegible-BoldItalic", "AtkinsonHyperlegible-Italic",
            "AtkinsonHyperlegible-Bold", "AtkinsonHyperlegible-Regular"])
        XCTAssertEqual(SubtitleFontFamily.roboto.postScriptNameCandidates(
            weight: .medium, isItalic: true
        ), ["Roboto-Italic", "Roboto-Medium", "Roboto-Regular"])
        XCTAssertTrue(SubtitleFontFamily.system.postScriptNameCandidates().isEmpty)
        XCTAssertTrue(SubtitleFontFamily.sfRounded.postScriptNameCandidates().isEmpty)
    }

    func testPositionGridIncludesEveryHalfPercentAndDefault() {
        let options = SubtitleStyle.verticalPositionOptions
        XCTAssertEqual(options.count, 211)
        XCTAssertEqual(options.first, SubtitleStyle.verticalPositionRange.lowerBound)
        XCTAssertEqual(options.last, SubtitleStyle.verticalPositionRange.upperBound)
        XCTAssertTrue(options.contains(SubtitleStyle.default.verticalPosition))
        for (previous, next) in zip(options, options.dropFirst()) {
            XCTAssertEqual(next - previous, 0.005, accuracy: 0.000_001)
        }
        let format = FloatingPointFormatStyle<Double>.Percent
            .percent.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US"))
        XCTAssertEqual(options[0].formatted(format), "-5%")
        XCTAssertEqual(options[9].formatted(format), "-0.5%")
        XCTAssertEqual(options[10].formatted(format), "0%")
        XCTAssertEqual(options[11].formatted(format), "0.5%")
        XCTAssertEqual(options[23].formatted(format), "6.5%")
        XCTAssertEqual(options[190].formatted(format), "90%")
        XCTAssertEqual(options[209].formatted(format), "99.5%")
        XCTAssertEqual(options[210].formatted(format), "100%")
    }

    func testHalfPercentPositionPersistsWithoutAffectingOtherProfiles() throws {
        let suite = "SubtitlePositionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let primary = SubtitleStyleStore(defaults: defaults)
        let secondary = SubtitleStyleStore(defaults: defaults, namespace: "second-profile")
        var preferences = SubtitleStylePreferences.default
        preferences.base.verticalPosition = 0.005
        preferences.base.fontFamily = .openDyslexic
        secondary.save(preferences)
        XCTAssertEqual(secondary.load(), preferences)
        XCTAssertEqual(primary.load(), .default)
        for position in [0.0, -0.005, -0.05, 0.995, 1.0] {
            preferences.base.verticalPosition = position
            secondary.save(preferences)
            XCTAssertEqual(secondary.load().base.verticalPosition, position)
            XCTAssertEqual(primary.load(), .default)
        }
    }

    func testHorizontalOffsetLabelWordsDirection() {
        XCTAssertEqual(String(localized: PlayerControlsFormatting.hOffsetLabel(0)), "Centre")
        // Interpolated resources carry placeholders, so the resource itself never
        // equals the finished sentence — render it before comparing.
        XCTAssertEqual(String(localized: PlayerControlsFormatting.hOffsetLabel(20)), "Right 20%")
        XCTAssertEqual(String(localized: PlayerControlsFormatting.hOffsetLabel(-15)), "Left 15%")
    }

    func testBottomAnchorIsDefaultForNewAndPreviouslySavedProfiles() throws {
        XCTAssertEqual(SubtitleStyle().verticalAnchor, .bottom)
        XCTAssertEqual(SubtitleStyle.default.verticalAnchor, .bottom)
        let suite = "SubtitleAnchorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = Data(#"{"base":{"fontFamily":"fredoka","fontScale":1.2,"verticalPosition":0.065},"overrides":[]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SubtitleStylePreferences.self, from: legacy).base.verticalAnchor, .bottom)
        for namespace: String? in [nil, "second-profile"] {
            let store = SubtitleStyleStore(defaults: defaults, namespace: namespace)
            XCTAssertEqual(store.load().base.verticalAnchor, .bottom)
            defaults.set(legacy, forKey: SettingsKey.scoped(SubtitleStyleStore.storageKey, namespace: namespace))
            let restored = store.load().base
            XCTAssertEqual(restored.verticalAnchor, .bottom)
            XCTAssertEqual(restored.fontFamily, .fredoka)
            XCTAssertEqual(restored.fontScale, 1.2)
            XCTAssertEqual(restored.verticalPosition, 0.065)
        }
    }

    func testExtraLinePositionLabelsMatchGrowthDirection() {
        XCTAssertEqual(SubtitleStyle.VerticalAnchor.allCases, [.bottom, .center, .top])
        XCTAssertEqual(String(localized: SubtitleStyle.VerticalAnchor.bottom.displayName), "Above")
        XCTAssertEqual(String(localized: SubtitleStyle.VerticalAnchor.center.displayName), "Center")
        XCTAssertEqual(String(localized: SubtitleStyle.VerticalAnchor.top.displayName), "Below")
    }

    func testRetiredAutoChoiceBecomesAboveWithoutResettingOtherSettings() throws {
        let legacy = Data(#"{"verticalAnchor":"automatic","fontFamily":"fredoka","verticalPosition":0.065}"#.utf8)
        let style = try JSONDecoder().decode(SubtitleStyle.self, from: legacy)
        XCTAssertEqual(style.verticalAnchor, .bottom)
        XCTAssertEqual(style.fontFamily, .fredoka)
        XCTAssertEqual(style.verticalPosition, 0.065)
        XCTAssertThrowsError(try JSONDecoder().decode(
            SubtitleStyle.VerticalAnchor.self, from: Data(#""unknown""#.utf8)
        ))
    }

    func testEveryVerticalAnchorPersistsPerProfile() throws {
        let suite = "SubtitleAnchorRoundTripTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SubtitleStyleStore(defaults: defaults, namespace: "custom")
        let primary = SubtitleStyleStore(defaults: defaults)
        for anchor in SubtitleStyle.VerticalAnchor.allCases {
            var preferences = SubtitleStylePreferences.default
            preferences.base.verticalAnchor = anchor
            store.save(preferences)
            XCTAssertEqual(store.load(), preferences)
            XCTAssertEqual(primary.load().base.verticalAnchor, .bottom)
        }
    }

    func testCornerLabelSentinelReadsFull() {
        XCTAssertEqual(PlayerControlsFormatting.cornerLabel(12), "12")
        XCTAssertEqual(PlayerControlsFormatting.cornerLabel(PlayerControlsFormatting.cornerFull), "Full")
    }

    func testNearestIndexSnapsToClosestOption() {
        let options = [0, 10, 20, 30]
        XCTAssertEqual(PlayerControlsFormatting.nearestIndex(options, 13), 1)
        XCTAssertEqual(PlayerControlsFormatting.nearestIndex(options, 16), 2)
        XCTAssertEqual(PlayerControlsFormatting.nearestIndex([], 5), 0)
    }

    func testEdgeSummaryCollapsesCombinations() {
        var s = SubtitleStyle.default
        s.edge.style = .none
        s.border.isEnabled = false
        XCTAssertEqual(PlayerControlsFormatting.edgeSummary(s), "Off")

        s.border.isEnabled = true
        XCTAssertEqual(PlayerControlsFormatting.edgeSummary(s), "Outline")

        s.edge.style = .dropShadow
        s.border.isEnabled = false
        XCTAssertEqual(PlayerControlsFormatting.edgeSummary(s), "Shadow")

        s.border.isEnabled = true
        XCTAssertEqual(PlayerControlsFormatting.edgeSummary(s), "On")
    }

    func testBoxColorLabelNamesPresets() {
        XCTAssertEqual(PlayerControlsFormatting.boxColorLabel(SubtitleColor(red: 0, green: 0, blue: 0, alpha: 1)), "Black")
        XCTAssertEqual(PlayerControlsFormatting.boxColorLabel(SubtitleColor(red: 1, green: 1, blue: 1, alpha: 1)), "White")
        XCTAssertEqual(PlayerControlsFormatting.boxColorLabel(SubtitleColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)), "Charcoal")
        XCTAssertEqual(PlayerControlsFormatting.boxColorLabel(SubtitleColor(red: 0.5, green: 0.2, blue: 0.1, alpha: 1)), "Custom")
    }
}
