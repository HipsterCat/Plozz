#if os(tvOS)
import XCTest
import CoreModels
@testable import AppShell

final class NavigationRailPresentationTests: XCTestCase {
    func testSearchHidesCollapsedRailWithoutReservingItsInset() {
        let presentation = make(.search)
        XCTAssertTrue(presentation.usesPageButton)
        XCTAssertFalse(presentation.isRailVisible)
        XCTAssertFalse(presentation.isRailEnabled)
        XCTAssertEqual(presentation.contentInset, 0)
        XCTAssertEqual(presentation.headerHeight, NavigationRailMetrics.searchHeaderHeight)
    }

    func testOpeningSearchRevealsTheRailBeforeRequestingFocus() {
        let opening = make(.search, opening: true)
        XCTAssertTrue(opening.isRailEnabled)
        XCTAssertTrue(opening.isRailVisible)
        let expanded = make(.search, expanded: true)
        XCTAssertTrue(expanded.isRailEnabled)
        XCTAssertTrue(expanded.isRailVisible)
        XCTAssertEqual(expanded.contentInset, 0)
        XCTAssertEqual(expanded.headerHeight, opening.headerHeight)
    }

    func testOtherRootDestinationsKeepPinnedNavigation() {
        for destination: NavigationRailDestination in [.home, .watchlist, .settings, .music, .allLibraries] {
            let presentation = make(destination)
            XCTAssertFalse(presentation.usesPageButton)
            XCTAssertTrue(presentation.isRailVisible)
            XCTAssertTrue(presentation.isRailEnabled)
            XCTAssertEqual(presentation.contentInset, NavigationRailMetrics.contentInset)
            XCTAssertEqual(presentation.headerHeight, 0)
        }
    }

    func testDetailsKeepNavigationHiddenEvenDuringAnOpenRequest() {
        let presentation = NavigationRailPresentation(
            destination: .search,
            chromeHidden: true,
            isExpanded: true,
            isOpening: true
        )
        XCTAssertFalse(presentation.isRailVisible)
        XCTAssertFalse(presentation.isRailEnabled)
        XCTAssertEqual(presentation.contentInset, 0)
        XCTAssertFalse(presentation.showsPageButton)
        XCTAssertEqual(presentation.headerHeight, 0)
    }

    private func make(
        _ destination: NavigationRailDestination,
        expanded: Bool = false,
        opening: Bool = false
    ) -> NavigationRailPresentation {
        NavigationRailPresentation(
            destination: destination,
            chromeHidden: false,
            isExpanded: expanded,
            isOpening: opening
        )
    }
}
#endif
