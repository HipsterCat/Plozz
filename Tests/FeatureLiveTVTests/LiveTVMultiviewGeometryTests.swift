#if DEBUG
import FeatureLiveTVCore
import XCTest
@testable import FeatureLiveTV

final class LiveTVMultiviewGeometryTests: XCTestCase {
    func testSideBySideAndPortraitFramesAreDisjointAndContained() {
        let first = UUID()
        let second = UUID()
        for size in [CGSize(width: 1760, height: 960), CGSize(width: 1920, height: 1080),
                     CGSize(width: 390, height: 844),
                     CGSize(width: 768, height: 1024)] {
            let bounds = CGRect(origin: .zero, size: size)
            let a = LiveTVMultiviewGeometry.frame(
                for: first, panes: [first, second], primary: first, layout: .sideBySide,
                corner: .bottomTrailing, insetSize: .medium, expanded: nil, size: size
            )
            let b = LiveTVMultiviewGeometry.frame(
                for: second, panes: [first, second], primary: first, layout: .sideBySide,
                corner: .bottomTrailing, insetSize: .medium, expanded: nil, size: size
            )
            XCTAssertTrue(bounds.contains(a))
            XCTAssertTrue(bounds.contains(b))
            XCTAssertFalse(a.intersects(b))
            XCTAssertEqual(a.width / a.height, 16 / 9, accuracy: 0.001)
            for (id, picture) in [(first, a), (second, b)] {
                XCTAssertTrue(LiveTVMultiviewGeometry.viewport(in: size).contains(picture))
                XCTAssertEqual(LiveTVMultiviewGeometry.focusFrame(
                    for: id, panes: [first, second], primary: first, layout: .sideBySide,
                    corner: .bottomTrailing, insetSize: .medium, expanded: nil, size: size
                ), picture)
            }
        }
    }

    func testEveryCornerAndInsetSizeStaysInsideMainPicture() {
        let first = UUID()
        let second = UUID()
        let size = CGSize(width: 1920, height: 1080)
        for corner in LiveTVMultiviewCorner.allCases {
            for inset in LiveTVMultiviewInsetSize.allCases {
                let main = LiveTVMultiviewGeometry.frame(
                    for: first, panes: [first, second], primary: first, layout: .corner,
                    corner: corner, insetSize: inset, expanded: nil, size: size
                )
                let overlay = LiveTVMultiviewGeometry.frame(
                    for: second, panes: [first, second], primary: first, layout: .corner,
                    corner: corner, insetSize: inset, expanded: nil, size: size
                )
                XCTAssertTrue(main.contains(overlay))
                XCTAssertLessThan(overlay.width, main.width)
            }
        }
    }

    func testPaneViewportBridgesFullWidthWithoutCoveringHeaderOrToolbar() {
        for size in [CGSize(width: 1760, height: 960), CGSize(width: 1920, height: 1080)] {
            let viewport = LiveTVMultiviewGeometry.viewport(in: size)
            XCTAssertEqual(viewport.minX, 0)
            XCTAssertEqual(viewport.maxX, size.width)
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(viewport))
            #if os(tvOS)
            let header = CGRect(x: 48, y: 48, width: size.width - 96, height: 103)
            let toolbar = CGRect(x: 48, y: size.height - 138, width: size.width - 96, height: 90)
            XCTAssertEqual(viewport.minY, 168)
            XCTAssertEqual(viewport.maxY, size.height - 150)
            XCTAssertGreaterThanOrEqual(viewport.minY - header.maxY, 16)
            XCTAssertFalse(viewport.intersects(header))
            XCTAssertFalse(viewport.intersects(toolbar))
            #else
            XCTAssertEqual(viewport.minY, 90)
            XCTAssertEqual(viewport.maxY, size.height - 110)
            #endif
        }
    }

    func testCornerFocusRegionsAreDisjointAndDirectionallyAdjacentForEverySizeAndPrimary() {
        let panes = [UUID(), UUID()]
        for size in [CGSize(width: 1760, height: 960), CGSize(width: 1920, height: 1080),
                     CGSize(width: 390, height: 844), CGSize(width: 768, height: 1024)] {
            for primary in panes {
                let secondary = panes.first { $0 != primary }!
                for corner in LiveTVMultiviewCorner.allCases {
                    for insetSize in LiveTVMultiviewInsetSize.allCases {
                        let main = LiveTVMultiviewGeometry.frame(
                            for: primary, panes: panes, primary: primary, layout: .corner,
                            corner: corner, insetSize: insetSize, expanded: nil, size: size
                        )
                        let inset = LiveTVMultiviewGeometry.frame(
                            for: secondary, panes: panes, primary: primary, layout: .corner,
                            corner: corner, insetSize: insetSize, expanded: nil, size: size
                        )
                        let mainFocus = LiveTVMultiviewGeometry.focusFrame(
                            for: primary, panes: panes, primary: primary, layout: .corner,
                            corner: corner, insetSize: insetSize, expanded: nil, size: size
                        )
                        let insetFocus = LiveTVMultiviewGeometry.focusFrame(
                            for: secondary, panes: panes, primary: primary, layout: .corner,
                            corner: corner, insetSize: insetSize, expanded: nil, size: size
                        )
                        let context = "\(size), \(corner), \(insetSize), primary \(primary)"
                        XCTAssertGreaterThan(mainFocus.width, 0, context)
                        XCTAssertGreaterThan(mainFocus.height, 0, context)
                        XCTAssertGreaterThan(insetFocus.width, 0, context)
                        XCTAssertGreaterThan(insetFocus.height, 0, context)
                        XCTAssertTrue(LiveTVMultiviewGeometry.viewport(in: size).contains(main), context)
                        XCTAssertTrue(main.insetBy(dx: -0.001, dy: -0.001).contains(mainFocus), context)
                        XCTAssertTrue(main.contains(insetFocus), context)
                        XCTAssertEqual(insetFocus, inset, context)
                        XCTAssertFalse(mainFocus.intersects(insetFocus), context)
                        XCTAssertEqual(mainFocus.minY, main.minY, accuracy: 0.001, context)
                        XCTAssertEqual(mainFocus.maxY, main.maxY, accuracy: 0.001, context)
                        XCTAssertLessThan(mainFocus.minY, insetFocus.maxY, context)
                        XCTAssertGreaterThan(mainFocus.maxY, insetFocus.minY, context)
                        if corner == .topLeading || corner == .bottomLeading {
                            XCTAssertEqual(mainFocus.minX - insetFocus.maxX, 16, accuracy: 0.001, context)
                        } else {
                            XCTAssertEqual(insetFocus.minX - mainFocus.maxX, 16, accuracy: 0.001, context)
                        }
                    }
                }
            }
        }
    }

    func testSingleAndExpandedPicturesKeepTheirFullFocusRegionInEveryLayout() {
        let panes = [UUID(), UUID()]
        let size = CGSize(width: 1760, height: 960)
        for layout in LiveTVMultiviewLayout.allCases {
            for primary in panes {
                for expanded in [nil, Optional(panes[0]), Optional(panes[1])] {
                    let visiblePanes = expanded == nil ? [primary] : panes
                    let visibleID = expanded ?? primary
                    let picture = LiveTVMultiviewGeometry.frame(
                        for: visibleID, panes: visiblePanes, primary: primary, layout: layout,
                        corner: .bottomTrailing, insetSize: .large, expanded: expanded, size: size
                    )
                    XCTAssertEqual(LiveTVMultiviewGeometry.focusFrame(
                        for: visibleID, panes: visiblePanes, primary: primary, layout: layout,
                        corner: .bottomTrailing, insetSize: .large, expanded: expanded, size: size
                    ), picture)
                    XCTAssertTrue(LiveTVMultiviewGeometry.viewport(in: size).contains(picture))
                }
            }
        }
    }
}
#endif
