#if DEBUG && canImport(SwiftUI) && canImport(UIKit)
import FeatureLiveTVCore
import SwiftUI
import UIKit
import XCTest
@testable import FeatureLiveTV

@MainActor
final class LiveTVGuideRowLayoutTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testNarrowClippedProgramsDoNotStretchTheChannelRow() {
        let programs = [
            program("leading", from: -1_080, to: 660),
            program("regular", from: 660, to: 2_400),
            program("long", from: 2_400, to: 21_590),
            program("trailing", from: 21_590, to: 22_200)
        ]
        XCTAssertEqual(height(programs: programs), PrototypeLayout.rowHeight, accuracy: 0.5)
    }

    func testGuideAndGenreOnlyRowsHaveTheSameHeight() {
        let regular = height(programs: [program("regular", from: 0, to: 21_600)])
        let narrow = height(programs: [program("brief", from: 0, to: 30)])
        let withoutGuide = height(programs: [])
        XCTAssertEqual(regular, PrototypeLayout.rowHeight, accuracy: 0.5)
        XCTAssertEqual(narrow, regular, accuracy: 0.5)
        XCTAssertEqual(withoutGuide, regular, accuracy: 0.5)
    }

    func testRowHeightDoesNotDependOnTimestampWrappingOrLongTitles() {
        let longTitle = String(repeating: "A long programme title ", count: 12)
        let programs = [program(longTitle, from: -3_600, to: 60)]
        for locale in ["en_US", "fr_FR", "ar"] {
            XCTAssertEqual(
                height(programs: programs, locale: locale),
                PrototypeLayout.rowHeight,
                accuracy: 0.5
            )
        }
    }

    func testAccessibilityTextScalesAllGuideRowsTogether() {
        let regular = height(
            programs: [program("regular", from: 0, to: 21_600)],
            typeSize: .accessibility3
        )
        let narrow = height(
            programs: [program("brief", from: 0, to: 30)],
            typeSize: .accessibility3
        )
        let withoutGuide = height(programs: [], typeSize: .accessibility3)
        XCTAssertGreaterThanOrEqual(regular, PrototypeLayout.rowHeight)
        XCTAssertEqual(narrow, regular, accuracy: 0.5)
        XCTAssertEqual(withoutGuide, regular, accuracy: 0.5)
    }

    private func program(
        _ title: String,
        from: TimeInterval,
        to: TimeInterval
    ) -> LiveTVPrototypeProgram {
        LiveTVPrototypeProgram(
            id: title, channelID: "station", title: title, subtitle: "",
            start: start.addingTimeInterval(from), end: start.addingTimeInterval(to)
        )
    }

    private func height(
        programs: [LiveTVPrototypeProgram],
        locale: String = "en_US",
        typeSize: DynamicTypeSize = .large
    ) -> CGFloat {
        let view = GuideRowFixture(programs: programs, start: start)
            .environment(\.locale, Locale(identifier: locale))
            .dynamicTypeSize(typeSize)
        return UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: 1_400, height: 1_000))
            .height
    }
}

private struct GuideRowFixture: View {
    let programs: [LiveTVPrototypeProgram]
    let start: Date
    @FocusState private var focus: PrototypeBrowseFocus?
    @State private var offset: CGFloat = 0

    private let channel = LiveTVPrototypeChannel(
        id: "station", number: 28, name: "Test station", category: "Kids",
        symbol: "tv", accent: 0, source: .iptv, tagline: ""
    )

    var body: some View {
        PrototypeGuideRow(
            channel: channel, programs: programs, start: start,
            now: start.addingTimeInterval(2_500), width: 1_400,
            timelineOffset: $offset, focus: $focus, railActive: false,
            returnTarget: nil, favorite: false, playing: false,
            toggleFavorite: {}, tune: {}, details: { _ in },
            controls: {}, top: {}, goToNow: {}
        )
    }
}
#endif
