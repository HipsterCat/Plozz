#if os(tvOS)
import XCTest
@testable import AppShell

final class NavigationGlassMorphTests: XCTestCase {
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
