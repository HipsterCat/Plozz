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

    func testPreviewExtendsToTheScreenEdgeInsteadOfStackingSafeAreaMargins() {
        let layout = PrototypePreviewLayout(
            size: CGSize(width: 1_740, height: 960),
            safeAreaInsets: EdgeInsets(top: 60, leading: 90, bottom: 60, trailing: 90)
        )
        XCTAssertEqual(layout.bounds, CGRect(x: -90, y: -60, width: 1_920, height: 1_080))
        XCTAssertEqual(layout.videoFrame.maxX, layout.bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(layout.videoFrame.minX, layout.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(layout.videoFrame.minY, layout.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(layout.videoFrame.width / layout.videoFrame.height, 16.0 / 9.0, accuracy: 0.001)
        #if os(tvOS)
        XCTAssertEqual(layout.contentFrame.minX - layout.bounds.minX, 32, accuracy: 0.5)
        XCTAssertEqual(layout.bounds.maxX - layout.contentFrame.maxX, 32, accuracy: 0.5)
        XCTAssertEqual(layout.bounds.maxY - layout.contentFrame.maxY, 20, accuracy: 0.5)
        #endif
    }

    func testPreviewFadeFinishesBeforeThePictureAndScreenEdges() {
        for size in [
            CGSize(width: 1_920, height: 1_080),
            CGSize(width: 1_024, height: 768),
            CGSize(width: 390, height: 844),
            CGSize(width: 844, height: 390)
        ] {
            let layout = PrototypePreviewLayout(size: size)
            let end = layout.bounds.minY + layout.fadeEnd
            XCTAssertGreaterThan(layout.fadeEnd, 0)
            XCTAssertLessThan(end, layout.videoFrame.maxY - 16)
            XCTAssertLessThan(end, layout.bounds.maxY - 16)
        }
    }

    func testTVPreviewRemainsVisibleBehindTheUpperGuide() {
        let layout = PrototypePreviewLayout(size: CGSize(width: 1_920, height: 1_080))
        let guideTop = layout.contentFrame.minY + layout.heroHeight + PrototypeLayout.sectionGap * 2
            + PrototypeLayout.controlHeight + PrototypeLayout.controlInset * 2
        XCTAssertGreaterThan(
            layout.bounds.minY + layout.fadeEnd,
            guideTop + PrototypeLayout.rowHeight * 2
        )
    }

    func testScrollFadesRampOnlyWhereContentExtendsPastTheViewport() {
        let atStart = PrototypeScrollFade(before: 0, after: 2_000)
        XCTAssertEqual(atStart.leading, 0)
        XCTAssertEqual(atStart.trailing, 1)
        let halfway = PrototypeScrollFade(before: 12, after: 12, distance: 24)
        XCTAssertEqual(halfway.leading, 0.5)
        XCTAssertEqual(halfway.trailing, 0.5)
        let atEnd = PrototypeScrollFade(before: 2_000, after: 0)
        XCTAssertEqual(atEnd.leading, 1)
        XCTAssertEqual(atEnd.trailing, 0)
        let fitting = PrototypeScrollFade(before: -10, after: -40)
        XCTAssertEqual(fitting.leading, 0)
        XCTAssertEqual(fitting.trailing, 0)
    }

    func testProgrammeSurfacesHaveVerticalClearanceInsideEveryRowSize() {
        for rowHeight in [PrototypeLayout.rowHeight, PrototypeLayout.rowHeight * 2] {
            let cellHeight = PrototypeLayout.programHeight(in: rowHeight)
            XCTAssertGreaterThanOrEqual(rowHeight - cellHeight, 16)
            XCTAssertEqual(cellHeight + PrototypeLayout.programInset * 2, rowHeight)
        }
        XCTAssertEqual(PrototypeLayout.programRadius + PrototypeLayout.programInset, PrototypeLayout.rowRadius)
    }

    func testNavigationRailInsetsContentWithoutShrinkingVideo() {
        let size = CGSize(width: 1_740, height: 960)
        let insets = EdgeInsets(top: 60, leading: 90, bottom: 60, trailing: 90)
        let plain = PrototypePreviewLayout(size: size, safeAreaInsets: insets)
        let rail = PrototypePreviewLayout(size: size, safeAreaInsets: insets, navigationInset: 112)
        XCTAssertEqual(rail.bounds, plain.bounds)
        XCTAssertEqual(rail.videoFrame, plain.videoFrame)
        XCTAssertEqual(rail.contentFrame.minX - plain.contentFrame.minX, 112, accuracy: 0.5)
        XCTAssertEqual(rail.contentFrame.maxX, plain.contentFrame.maxX, accuracy: 0.5)
    }

    func testTVLayoutLeavesRoomForFourRoomyRows() {
        #if os(tvOS)
        let layout = PrototypePreviewLayout(
            size: CGSize(width: 1_740, height: 960),
            safeAreaInsets: EdgeInsets(top: 60, leading: 90, bottom: 60, trailing: 90)
        )
        let toolbarAndRuler: CGFloat = 44
        let spacing = PrototypeLayout.sectionGap + PrototypeLayout.guideInset * 2
            + PrototypeLayout.gap + PrototypeLayout.smallGap * 2
        let listHeight = layout.contentFrame.height - layout.heroHeight - toolbarAndRuler - spacing
        let visibleRows = listHeight / (PrototypeLayout.rowHeight + PrototypeLayout.rowGap)
        XCTAssertGreaterThanOrEqual(visibleRows, 4)
        XCTAssertLessThan(visibleRows, 5)
        XCTAssertGreaterThanOrEqual(PrototypeLayout.rowHeight, 100)
        #endif
    }

    func testWideGuideReservesSpaceForPinnedControlsWithoutShrinkingVideo() {
        for size in [CGSize(width: 1_920, height: 1_080), CGSize(width: 1_024, height: 768)] {
            let layout = PrototypePreviewLayout(size: size)
            XCTAssertGreaterThan(layout.sidebarWidth, 0)
            XCTAssertEqual(
                layout.sidebarWidth + PrototypeLayout.sectionGap + layout.guideWidth,
                layout.contentFrame.width, accuracy: 0.01
            )
            XCTAssertGreaterThanOrEqual(layout.guideWidth - PrototypeLayout.guideInset * 2, 650)
            XCTAssertEqual(layout.videoFrame.width, layout.bounds.width)
        }
    }

    func testCompactOrShortWindowsKeepPinnedHorizontalControls() {
        for size in [
            CGSize(width: 390, height: 844),
            CGSize(width: 700, height: 750),
            CGSize(width: 1_024, height: 500)
        ] {
            let layout = PrototypePreviewLayout(size: size)
            XCTAssertEqual(layout.sidebarWidth, 0)
            XCTAssertEqual(layout.guideWidth, layout.contentFrame.width)
        }
    }

    func testSidebarFitsWithLongAndScrollableCategoryLists() {
        let widths: [CGFloat] = [224, 272]
        for width in widths {
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                let fixture = SidebarFixture()
                    .environment(\.layoutDirection, direction)
                    .dynamicTypeSize(.large)
                let size = UIHostingController(rootView: fixture)
                    .sizeThatFits(in: CGSize(width: width, height: 600))
                XCTAssertLessThanOrEqual(size.width, width + 0.5)
                XCTAssertLessThanOrEqual(size.height, 600.5)
                XCTAssertGreaterThan(size.height, 400)
            }
        }
    }

    func testGuideAndLogoCornersStayConcentric() {
        XCTAssertEqual(PrototypeLayout.guideRadius, PrototypeLayout.rowRadius + PrototypeLayout.guideInset)
        XCTAssertEqual(PrototypeLayout.rowRadius, PrototypeLayout.logoRadius + PrototypeLayout.rowInset)
        XCTAssertEqual(PrototypeLayout.rowHeight, PrototypeLayout.stationSize + PrototypeLayout.rowInset * 2)
        XCTAssertEqual(
            PrototypeLayout.controlGroupRadius,
            PrototypeLayout.controlRadius + PrototypeLayout.controlInset
        )
    }

    func testStationAndTimelineAlwaysShareTheSameAvailableWidth() {
        let widths: [CGFloat] = [650, 700, 1_100, 1_400, 1_832]
        for width in widths {
            XCTAssertEqual(
                PrototypeLayout.stationWidth(for: width)
                    + PrototypeLayout.columnGap + PrototypeLayout.timelineWidth(for: width),
                width, accuracy: 0.01
            )
        }
    }

    func testControlGroupFitsCompactAndWideLayoutsWithLongFilters() {
        let widths: [CGFloat] = [320, 390, 700, 1_440]
        for width in widths {
            let fixture = ToolbarFixture(compact: width < 650)
                .dynamicTypeSize(.large)
            let size = UIHostingController(rootView: fixture)
                .sizeThatFits(in: CGSize(width: width, height: 300))
            #if os(tvOS)
            if width < 650 || width >= 1_400 {
                XCTAssertLessThanOrEqual(size.width, width + 0.5)
            }
            #else
            XCTAssertLessThanOrEqual(size.width, width + 0.5)
            #endif
            XCTAssertGreaterThanOrEqual(size.height, PrototypeLayout.controlHeight)
        }
    }

    func testCompactAndAccessibilityLayoutsKeepTheGuideInBounds() {
        for size in [CGSize(width: 390, height: 750), CGSize(width: 700, height: 500)] {
            let layout = PrototypePreviewLayout(size: size, largeText: true)
            XCTAssertGreaterThan(layout.contentFrame.width, 0)
            XCTAssertGreaterThan(layout.contentFrame.height - layout.heroHeight, 200)
            XCTAssertLessThanOrEqual(layout.metadataWidth, layout.contentFrame.width)
            XCTAssertLessThanOrEqual(layout.contentFrame.maxY, layout.bounds.maxY)
        }
    }

    func testLogoPlateSupportsDarkInkAndPreservesBrightWordmarks() {
        XCTAssertTrue(PrototypeLogoPlate.usesLightBackground(luminance: 0.12, brightInk: 0))
        XCTAssertTrue(PrototypeLogoPlate.usesLightBackground(luminance: 0.3, brightInk: 0.1))
        XCTAssertFalse(PrototypeLogoPlate.usesLightBackground(luminance: 0.95, brightInk: 0.9))
        XCTAssertFalse(PrototypeLogoPlate.usesLightBackground(luminance: 0.3, brightInk: 0.4))
    }

    func testEnlargedLogoKeepsItsFixedSlotWithMissingArtwork() {
        let channel = LiveTVPrototypeChannel(
            id: "missing-logo", number: 1, name: "Test station",
            category: "News", symbol: "tv", accent: 0, source: .iptv, tagline: ""
        )
        let size = UIHostingController(rootView: PrototypeStationMark(channel: channel, size: 64))
            .sizeThatFits(in: CGSize(width: 400, height: 400))
        XCTAssertEqual(size.width, 112, accuracy: 0.5)
        XCTAssertEqual(size.height, 64, accuracy: 0.5)
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

private struct ToolbarFixture: View {
    let compact: Bool
    @State private var active = false
    private let model: LiveTVPrototypeModel = {
        let model = LiveTVPrototypeModel(now: Date(), scenario: .noGuide, channels: [])
        model.category = "Documentaries and international entertainment"
        return model
    }()

    var body: some View {
        PrototypeBrowseToolbar(
            model: model, active: $active, focusRequest: 0, compact: compact,
            search: {}, filters: {}, more: {}
        )
    }
}

private struct SidebarFixture: View {
    @State private var active = false
    private let model = LiveTVPrototypeModel(
        now: Date(), scenario: .noGuide,
        channels: (1 ... 30).map { number in
            LiveTVPrototypeChannel(
                id: "sidebar-\(number)", number: number, name: "Channel \(number)",
                category: "Documentaries and entertainment \(number)",
                symbol: "tv", accent: 0, source: .iptv, tagline: ""
            )
        }
    )

    var body: some View {
        PrototypeBrowseSidebar(model: model, active: $active, focusRequest: 0, search: {}, more: {})
    }
}
#endif
