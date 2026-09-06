#if canImport(SwiftUI)
import XCTest
@testable import CoreUI

final class HomeHeroNavigationStateTests: XCTestCase {
    func testDownRecedesIntoContentAndUpReturnsToHero() {
        XCTAssertEqual(HomeHeroNavigationState.resolve(hasHero: true, isReceded: false), .hero)
        XCTAssertEqual(HomeHeroNavigationState.resolve(hasHero: true, isReceded: true), .content)
        XCTAssertEqual(HomeHeroNavigationState.resolve(hasHero: true, isReceded: false), .hero)
    }

    func testDisabledOrEmptyHeroDoesNotRequestCompactNavigation() {
        XCTAssertEqual(HomeHeroNavigationState.resolve(hasHero: false, isReceded: false), .absent)
        XCTAssertEqual(HomeHeroNavigationState.resolve(hasHero: false, isReceded: true), .absent)
    }

    func testUnrelatedSubviewsDoNotEraseHomeRegionPreference() {
        var state = HomeHeroNavigationPreference.defaultValue
        HomeHeroNavigationPreference.reduce(value: &state) { .hero }
        HomeHeroNavigationPreference.reduce(value: &state) { .absent }
        XCTAssertEqual(state, .hero)
        HomeHeroNavigationPreference.reduce(value: &state) { .content }
        XCTAssertEqual(state, .content)
        XCTAssertEqual(HomeHeroNavigationPreference.defaultValue, .absent)
    }
}
#endif
