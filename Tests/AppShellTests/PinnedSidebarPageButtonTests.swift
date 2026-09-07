#if os(tvOS)
import XCTest
@testable import AppShell

final class PinnedSidebarPageButtonTests: XCTestCase {
    func testArrivingAtEnabledCapsuleOpensNavigationWithoutActivation() {
        XCTAssertTrue(PinnedSidebarPageButton.shouldOpenOnFocus(
            hasFocus: true, isFocusEnabled: true, isNavigationExpanded: false
        ))
    }

    func testLeavingCapsuleOrOpeningMenuDoesNotIssueAnotherRequest() {
        XCTAssertFalse(PinnedSidebarPageButton.shouldOpenOnFocus(
            hasFocus: false, isFocusEnabled: true, isNavigationExpanded: false
        ))
        XCTAssertFalse(PinnedSidebarPageButton.shouldOpenOnFocus(
            hasFocus: true, isFocusEnabled: true, isNavigationExpanded: true
        ))
    }

    func testReturningToSearchCannotImmediatelyReopenNavigation() {
        XCTAssertFalse(PinnedSidebarPageButton.shouldOpenOnFocus(
            hasFocus: true, isFocusEnabled: false, isNavigationExpanded: false
        ))
    }
}
#endif
