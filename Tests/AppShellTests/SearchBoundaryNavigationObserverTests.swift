#if os(tvOS)
import XCTest
import UIKit
@testable import AppShell

@MainActor
final class SearchBoundaryNavigationObserverTests: XCTestCase {
    func testFailedLeftInsideNativeSearchCanOpenNavigation() {
        let search = UISearchController(searchResultsController: UIViewController())
        let item = SearchFocusItem(parent: search)
        XCTAssertTrue(SearchBoundaryNavigationObserver.shouldOpen(
            heading: .left, previous: item, current: item
        ))
    }

    func testOtherDirectionsAndSuccessfulMovesDoNotOpenNavigation() {
        let search = UISearchController(searchResultsController: UIViewController())
        let first = SearchFocusItem(parent: search)
        let second = SearchFocusItem(parent: search)
        for heading: UIFocusHeading in [.right, .up, .down, []] {
            XCTAssertFalse(SearchBoundaryNavigationObserver.shouldOpen(
                heading: heading, previous: first, current: first
            ))
        }
        XCTAssertFalse(SearchBoundaryNavigationObserver.shouldOpen(
            heading: .left, previous: first, current: second
        ))
        XCTAssertFalse(SearchBoundaryNavigationObserver.shouldOpen(
            heading: .left, previous: first, current: nil
        ))
    }

    func testUnrelatedModalCannotOpenSearchNavigation() {
        let alert = UIViewController()
        let item = SearchFocusItem(parent: alert)
        XCTAssertFalse(SearchBoundaryNavigationObserver.shouldOpen(
            heading: .left, previous: item, current: item
        ))
    }

    func testTextSelectionStillBelongsToTheSearchField() throws {
        let field = UITextField()
        field.text = "Search"
        let cursor = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: 3))
        field.selectedTextRange = field.textRange(from: cursor, to: cursor)
        XCTAssertFalse(SearchBoundaryNavigationObserver.shouldOpen(
            heading: .left, previous: field, current: field
        ))
    }
}

@MainActor
private final class SearchFocusItem: NSObject, UIFocusItem {
    weak var parentFocusEnvironment: (any UIFocusEnvironment)?
    var frame: CGRect { CGRect(x: 0, y: 0, width: 1760, height: 66) }
    var canBecomeFocused: Bool { true }
    var focusItemContainer: (any UIFocusItemContainer)? { nil }
    var preferredFocusEnvironments: [any UIFocusEnvironment] { [] }

    init(parent: any UIFocusEnvironment) { parentFocusEnvironment = parent }
    func setNeedsFocusUpdate() {}
    func updateFocusIfNeeded() {}
    func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool { true }
    func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {}
}
#endif
