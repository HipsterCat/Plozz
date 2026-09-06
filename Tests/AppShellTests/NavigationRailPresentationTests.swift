#if os(tvOS)
import XCTest
import CoreModels
import CoreUI
@testable import AppShell

final class NavigationRailPresentationTests: XCTestCase {
    func testVisibleHomeHeroUsesOverlayButtonInsteadOfPinnedIcons() {
        let hero = make(.home, homeHero: .hero)
        XCTAssertTrue(hero.usesPageButton)
        XCTAssertTrue(hero.showsPageButton)
        XCTAssertFalse(hero.isRailVisible)
        XCTAssertFalse(hero.isRailEnabled)
        XCTAssertEqual(hero.headerHeight, 0, "Home button overlays full-bleed hero, unlike Search header")
        XCTAssertFalse(hero.shouldEnterSearchContent)
        XCTAssertFalse(hero.isPageButtonEnabled(hasEnteredContent: true))
        XCTAssertTrue(hero.isPageButtonEnabled(hasEnteredContent: false, hasEnteredHero: true))
    }

    func testHomeDownShowsCollapsedRailWithoutShiftingContentGutter() {
        let hero = make(.home, homeHero: .hero)
        let content = make(.home, homeHero: .content)
        XCTAssertFalse(content.usesPageButton)
        XCTAssertTrue(content.isRailVisible)
        XCTAssertTrue(content.isRailEnabled)
        XCTAssertFalse(content.opensExpanded)
        XCTAssertEqual(content.contentInset, hero.contentInset)
        XCTAssertEqual(content.headerHeight, hero.headerHeight)
    }

    func testHomeButtonOpensFullMenuWithoutChangingVisibleRegion() {
        let opening = make(.home, opening: true, homeHero: .hero)
        let expanded = make(.home, expanded: true, homeHero: .hero)
        XCTAssertTrue(opening.opensExpanded)
        XCTAssertTrue(opening.isRailVisible)
        XCTAssertTrue(expanded.isRailVisible)
        XCTAssertTrue(expanded.showsPageButton)
        XCTAssertFalse(expanded.isPageButtonEnabled(hasEnteredContent: true, hasEnteredHero: true))
        XCTAssertFalse(expanded.shouldEnterSearchContent)
        XCTAssertTrue(make(.home, homeHero: .hero).isEdgeNavigationEnabled())
    }

    func testHeroPreferenceCannotHideNavigationOnOtherDestinations() {
        for destination: NavigationRailDestination in [.watchlist, .music, .settings, .allLibraries] {
            XCTAssertFalse(make(destination, homeHero: .hero).usesPageButton)
            XCTAssertTrue(make(destination, homeHero: .hero).isRailVisible)
        }
        XCTAssertTrue(make(.search, homeHero: .hero).shouldEnterSearchContent)
    }

    func testSearchHidesCollapsedRailWithoutReservingItsInset() {
        let presentation = make(.search)
        XCTAssertTrue(presentation.usesPageButton)
        XCTAssertFalse(presentation.isRailVisible)
        XCTAssertFalse(presentation.isRailEnabled)
        XCTAssertEqual(presentation.contentInset, 0)
        XCTAssertEqual(presentation.headerHeight, NavigationRailMetrics.searchHeaderHeight)
        XCTAssertTrue(presentation.shouldEnterSearchContent)
        XCTAssertFalse(presentation.opensExpanded)
    }

    func testOpeningSearchRevealsTheRailBeforeRequestingFocus() {
        let opening = make(.search, opening: true)
        XCTAssertTrue(opening.isRailEnabled)
        XCTAssertTrue(opening.isRailVisible)
        XCTAssertTrue(opening.opensExpanded)
        XCTAssertFalse(opening.shouldEnterSearchContent)
        let expanded = make(.search, expanded: true)
        XCTAssertTrue(expanded.isRailEnabled)
        XCTAssertTrue(expanded.isRailVisible)
        XCTAssertEqual(expanded.contentInset, 0)
        XCTAssertEqual(expanded.headerHeight, opening.headerHeight)
        XCTAssertFalse(expanded.shouldEnterSearchContent)
        XCTAssertFalse(expanded.opensExpanded)
    }

    func testSearchCapsuleCannotWinEntryOrNavigationDismissal() {
        let search = make(.search)
        XCTAssertFalse(search.isPageButtonEnabled(hasEnteredContent: false))
        XCTAssertTrue(search.isPageButtonEnabled(hasEnteredContent: true))
        XCTAssertFalse(make(.search, opening: true).isPageButtonEnabled(hasEnteredContent: true))
        XCTAssertFalse(make(.search, expanded: true).isPageButtonEnabled(hasEnteredContent: true))
        XCTAssertFalse(make(.search).isPageButtonEnabled(hasEnteredContent: false))
    }

    func testSearchPageKeepsLeftPressesAndSwipesForNativeNavigation() {
        XCTAssertFalse(make(.search).isEdgeNavigationEnabled())
        XCTAssertFalse(make(.search, opening: true).isEdgeNavigationEnabled())
    }

    func testExpandedSearchNavigationStillAllowsRightToReturnToThePage() {
        XCTAssertTrue(make(.search, expanded: true).isEdgeNavigationEnabled())
    }

    func testSearchResultsAllowLeadingEdgeNavigationButNotWhileMenuIsOpening() {
        XCTAssertTrue(make(.search).isEdgeNavigationEnabled(searchResultsHaveFocus: true))
        XCTAssertFalse(make(.search, opening: true).isEdgeNavigationEnabled(searchResultsHaveFocus: true))
    }

    func testOtherRootDestinationsKeepPinnedNavigation() {
        for destination: NavigationRailDestination in [.home, .watchlist, .settings, .music, .allLibraries] {
            let presentation = make(destination)
            XCTAssertFalse(presentation.usesPageButton)
            XCTAssertTrue(presentation.isRailVisible)
            XCTAssertTrue(presentation.isRailEnabled)
            XCTAssertTrue(presentation.isEdgeNavigationEnabled())
            XCTAssertEqual(presentation.contentInset, NavigationRailMetrics.contentInset)
            XCTAssertEqual(presentation.headerHeight, 0)
            XCTAssertFalse(presentation.shouldEnterSearchContent)
            XCTAssertFalse(make(destination, opening: true).opensExpanded)
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
        XCTAssertFalse(presentation.isEdgeNavigationEnabled())
        XCTAssertFalse(presentation.isEdgeNavigationEnabled(searchResultsHaveFocus: true))
        XCTAssertEqual(presentation.contentInset, 0)
        XCTAssertFalse(presentation.showsPageButton)
        XCTAssertEqual(presentation.headerHeight, 0)
        XCTAssertFalse(presentation.shouldEnterSearchContent)
        XCTAssertFalse(presentation.opensExpanded)
    }

    private func make(
        _ destination: NavigationRailDestination,
        expanded: Bool = false,
        opening: Bool = false,
        homeHero: HomeHeroNavigationState = .absent
    ) -> NavigationRailPresentation {
        NavigationRailPresentation(
            destination: destination,
            chromeHidden: false,
            isExpanded: expanded,
            isOpening: opening,
            homeHero: homeHero
        )
    }
}
#endif
