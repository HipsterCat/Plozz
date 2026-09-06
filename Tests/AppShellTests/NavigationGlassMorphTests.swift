#if os(tvOS)
import XCTest
import SwiftUI
@testable import AppShell

final class NavigationGlassMorphTests: XCTestCase {
    func testPersistentSurfaceInterpolatesMaterialGeometryInBothDirections() {
        let small = CGRect(x: 83, y: 72, width: 174, height: 58)
        let large = CGRect(x: 36, y: 36, width: 354, height: 1008)
        var surface = NavigationGlassSurfaceView(frame: small, cornerRadius: 29)
        let start = surface.animatableData
        let end = NavigationGlassSurfaceView(frame: large, cornerRadius: 46).animatableData
        var delta = end - start
        delta.scale(by: 0.5)
        surface.animatableData = start + delta
        XCTAssertEqual(surface.frame, CGRect(x: 59.5, y: 54, width: 264, height: 533))
        XCTAssertEqual(surface.cornerRadius, 37.5)
        surface.animatableData = end
        XCTAssertEqual(surface.frame, large)
        surface.animatableData = start
        XCTAssertEqual(surface.frame, small)
        XCTAssertEqual(surface.cornerRadius, 29)
    }

    func testOpenMenuSurvivesSwitchToSearchUntilCapsuleIsMeasured() {
        XCTAssertEqual(NavigationGlassSurface.resolve(
            isExpanded: true, showsPageButton: false, hasButtonFrame: false
        ), .menu)
        XCTAssertEqual(NavigationGlassSurface.resolve(
            isExpanded: false, showsPageButton: true, hasButtonFrame: false
        ), .menu)
        XCTAssertEqual(NavigationGlassSurface.resolve(
            isExpanded: false, showsPageButton: true, hasButtonFrame: true
        ), .button)
    }

    func testCapsuleOpensToSameMenuSurfaceAndClosesBack() {
        XCTAssertEqual(NavigationGlassSurface.resolve(
            isExpanded: true, showsPageButton: true, hasButtonFrame: true
        ), .menu)
        XCTAssertEqual(NavigationGlassSurface.resolve(
            isExpanded: false, showsPageButton: true, hasButtonFrame: true
        ), .button)
    }

    func testOtherPagesKeepNoPanelBehindCollapsedPinnedIcons() {
        XCTAssertEqual(NavigationGlassSurface.resolve(
            isExpanded: false, showsPageButton: false, hasButtonFrame: false
        ), .none)
    }

    func testMorphUsesMeasuredCapsuleAndMenuGeometry() {
        let button = CGRect(x: 83, y: 72, width: 174.5, height: 58)
        let menu = CGRect(x: 36, y: 36, width: 354, height: 1008)
        let geometry = NavigationGlassMorphGeometry(button: button, menu: menu)
        XCTAssertTrue(geometry.isUsable)
        XCTAssertEqual(geometry.buttonRadius, 29)
        XCTAssertEqual(geometry.menuRadius, NavigationRailMetrics.expandedPanelCornerRadius)
        XCTAssertEqual(geometry.button, button)
        XCTAssertEqual(geometry.menu, menu)
    }

    func testLocalizedButtonWidthsRemainCapsules() {
        for width: CGFloat in [140, 220, 380] {
            let geometry = NavigationGlassMorphGeometry(
                button: CGRect(x: 83, y: 72, width: width, height: 58),
                menu: CGRect(x: 36, y: 36, width: 354, height: 1008)
            )
            XCTAssertEqual(geometry.buttonRadius, 29)
            XCTAssertTrue(geometry.isUsable)
        }
    }

    func testUnresolvedLayoutDoesNotCreateAnInvalidGlassSurface() {
        let valid = CGRect(x: 36, y: 36, width: 354, height: 1008)
        for invalid: CGRect in [.zero, .null, .infinite] {
            XCTAssertFalse(NavigationGlassMorphGeometry(button: invalid, menu: valid).isUsable)
            XCTAssertFalse(NavigationGlassMorphGeometry(button: valid, menu: invalid).isUsable)
        }
    }
}
#endif
