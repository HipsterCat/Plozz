import CoreModels
import SwiftUI
import XCTest
@testable import CoreUI

@MainActor
final class PlayerGlassEnvironmentTests: XCTestCase {
    func testPlayerGlassAvailabilityPreservesTheCurrentScheme() {
        for scheme in [ColorScheme.light, .dark] {
            for reduced in [false, true] {
                var environment = EnvironmentValues()
                environment.colorScheme = scheme
                environment.plozzReduceTransparency = reduced
                if #available(iOS 26.0, tvOS 26.0, *) {
                    XCTAssertEqual(environment.playerUsesNativeGlass, !reduced)
                } else {
                    XCTAssertFalse(environment.playerUsesNativeGlass)
                }
                environment.plozzReducePanelGlass = true
                XCTAssertFalse(environment.playerUsesNativeGlass)
                XCTAssertEqual(environment.colorScheme, scheme)
            }
        }
    }

    func testExplicitPanelPreviewCannotOverrideReducedTransparency() {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        environment.plozzReduceTransparency = true
        environment.plozzReducePanelGlass = false
        XCTAssertFalse(environment.playerUsesNativeGlass)
        XCTAssertEqual(environment.colorScheme, .light)
    }

    func testPanelsFollowTheResolvedProfileAndAccessibilityPreferenceWithoutAnotherGate() {
        for preference in TransparencyPreference.allCases {
            for systemReduced in [false, true] {
                var environment = EnvironmentValues()
                let expected = preference.reducesTransparency(systemReduceTransparency: systemReduced)
                environment.plozzReduceTransparency = expected
                XCTAssertEqual(environment.plozzReducePanelGlass, expected)
                environment.plozzReduceTransparency = !expected
                XCTAssertEqual(environment.plozzReducePanelGlass, !expected,
                               "Panels must read the live preference, not a copied launch-time value.")
            }
        }
    }

    func testMaterialPreviewsCanStillSelectEachActualSurfaceExplicitly() {
        var environment = EnvironmentValues()
        environment.plozzReducePanelGlass = true
        XCTAssertTrue(environment.plozzReducePanelGlass)
        environment.plozzReducePanelGlass = false
        XCTAssertFalse(environment.plozzReducePanelGlass)
    }
}
