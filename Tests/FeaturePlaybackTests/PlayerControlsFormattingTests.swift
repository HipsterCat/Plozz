import XCTest
import CoreModels
@testable import FeaturePlayback

/// Tests the pure subtitle-style label formatters extracted from
/// `PlayerControls`. These pin the human-readable readouts (precise positions,
/// signed offsets, preset color names, edge summary) that the style rows show.
final class PlayerControlsFormattingTests: XCTestCase {
    func testPositionGridIncludesEveryHalfPercentAndDefault() {
        let options = SubtitleStyle.verticalPositionOptions
        XCTAssertEqual(options.count, 181)
        XCTAssertEqual(options.first, SubtitleStyle.verticalPositionRange.lowerBound)
        XCTAssertEqual(options.last, SubtitleStyle.verticalPositionRange.upperBound)
        XCTAssertTrue(options.contains(SubtitleStyle.default.verticalPosition))
        for (previous, next) in zip(options, options.dropFirst()) {
            XCTAssertEqual(next - previous, 0.005, accuracy: 0.000_001)
        }
        let format = FloatingPointFormatStyle<Double>.Percent
            .percent.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US"))
        XCTAssertEqual(options[0].formatted(format), "0%")
        XCTAssertEqual(options[1].formatted(format), "0.5%")
        XCTAssertEqual(options[13].formatted(format), "6.5%")
        XCTAssertEqual(options[180].formatted(format), "90%")
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
        preferences.base.verticalPosition = 0
        secondary.save(preferences)
        XCTAssertEqual(secondary.load().base.verticalPosition, 0)
    }

    func testHorizontalOffsetLabelWordsDirection() {
        XCTAssertEqual(String(localized: PlayerControlsFormatting.hOffsetLabel(0)), "Centre")
        // Interpolated resources carry placeholders, so the resource itself never
        // equals the finished sentence — render it before comparing.
        XCTAssertEqual(String(localized: PlayerControlsFormatting.hOffsetLabel(20)), "Right 20%")
        XCTAssertEqual(String(localized: PlayerControlsFormatting.hOffsetLabel(-15)), "Left 15%")
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
