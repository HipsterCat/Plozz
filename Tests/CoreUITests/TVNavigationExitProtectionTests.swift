#if os(tvOS) && canImport(UIKit)
import XCTest
import UIKit
@testable import CoreUI

@MainActor
final class TVNavigationExitProtectionTests: XCTestCase {
    private var window: UIWindow!
    private var selected: UIViewController!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        selected = UIViewController()
        window.rootViewController = selected
        window.makeKeyAndVisible()
        selected.view.layoutIfNeeded()
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        selected = nil
        super.tearDown()
    }

    func testUnpresentedRootContainsFocusedView() {
        let focusedView = UIView()
        selected.view.addSubview(focusedView)

        XCTAssertTrue(
            TVNavigationExitProtectionFocus.isUnpresentedRootView(focusedView, in: window)
        )
    }

    func testUnrelatedOverlayFocusIsNotProtected() {
        let overlay = UIView()
        window.addSubview(overlay)

        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isUnpresentedRootView(overlay, in: window)
        )
    }

    func testTextInputAndItsSubviewsAreNotProtected() {
        let searchField = UITextField()
        selected.view.addSubview(searchField)
        let inputSubview = UIView()
        searchField.addSubview(inputSubview)

        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isUnpresentedRootView(searchField, in: window)
        )
        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isUnpresentedRootView(inputSubview, in: window)
        )
    }

    func testPresentedControllerDisablesProtection() {
        let modal = UIViewController()
        let focusedView = UIView()
        selected.view.addSubview(focusedView)
        selected.present(modal, animated: false)

        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isUnpresentedRootView(focusedView, in: window)
        )
    }

    func testCoordinatorDetachesWhenMarkerLeavesItsWindow() {
        let coordinator = TVNavigationExitProtection.Coordinator()
        coordinator.update(isEnabled: true, navigationHasFocus: true, window: window)
        XCTAssertEqual(exitProtectionRecognizers(in: window).count, 1)

        coordinator.move(to: nil)
        XCTAssertTrue(exitProtectionRecognizers(in: window).isEmpty)
    }

    func testCoordinatorMovesRecognizerBetweenWindows() {
        let secondWindow = UIWindow(frame: window.frame)
        let coordinator = TVNavigationExitProtection.Coordinator()
        coordinator.update(isEnabled: true, navigationHasFocus: true, window: window)

        coordinator.move(to: secondWindow)

        XCTAssertTrue(exitProtectionRecognizers(in: window).isEmpty)
        XCTAssertEqual(exitProtectionRecognizers(in: secondWindow).count, 1)
    }

    func testCoordinatorTracksPreferenceAndCustomNavigationFocus() throws {
        let coordinator = TVNavigationExitProtection.Coordinator()
        coordinator.update(isEnabled: false, navigationHasFocus: true, window: window)
        let recognizer = try XCTUnwrap(exitProtectionRecognizers(in: window).first)
        XCTAssertFalse(recognizer.isEnabled)

        coordinator.update(isEnabled: true, navigationHasFocus: true, window: window)
        XCTAssertTrue(recognizer.isEnabled)

        coordinator.update(isEnabled: true, navigationHasFocus: false, window: window)
        XCTAssertFalse(recognizer.isEnabled)

        coordinator.update(isEnabled: false, navigationHasFocus: true, window: window)
        XCTAssertFalse(recognizer.isEnabled)
    }

    func testBackPressIsDeferredUntilShortPressRecognitionFinishes() throws {
        let coordinator = TVNavigationExitProtection.Coordinator()
        coordinator.update(isEnabled: true, navigationHasFocus: true, window: window)
        let recognizer = try XCTUnwrap(exitProtectionRecognizers(in: window).first)

        XCTAssertTrue(recognizer.delaysTouchesBegan)
        XCTAssertTrue(recognizer.delaysTouchesEnded)
        XCTAssertTrue(recognizer.cancelsTouchesInView)
        XCTAssertEqual(
            recognizer.allowedPressTypes,
            [NSNumber(value: UIPress.PressType.menu.rawValue)]
        )
    }

    func testPresentedDescendantDisablesProtection() {
        let child = UIViewController()
        selected.addChild(child)
        selected.view.addSubview(child.view)
        child.didMove(toParent: selected)
        let focusedView = UIView()
        child.view.addSubview(focusedView)
        XCTAssertTrue(
            TVNavigationExitProtectionFocus.isUnpresentedRootView(focusedView, in: window)
        )
        child.present(UIViewController(), animated: false)
        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isUnpresentedRootView(focusedView, in: window)
        )
    }

    func testNonViewFocusEnvironmentResolvesItsContainingView() {
        let parent = NonViewFocusItem(parent: selected.view)
        let proxy = NonViewFocusItem(parent: parent)

        XCTAssertTrue(
            TVNavigationExitProtectionFocus.containingView(of: proxy) === selected.view
        )
        XCTAssertTrue(
            TVNavigationExitProtectionFocus.containingView(of: selected) === selected.view
        )
        XCTAssertNil(TVNavigationExitProtectionFocus.containingView(of: NonViewFocusItem(parent: nil)))
    }

    func testInvalidFocusEnvironmentCycleDoesNotLoop() {
        let first = NonViewFocusItem(parent: nil)
        let second = NonViewFocusItem(parent: first)
        first.parentFocusEnvironment = second

        XCTAssertNil(TVNavigationExitProtectionFocus.containingView(of: first))
    }

    func testFocusInAnotherWindowIsNotProtected() {
        let focusedView = UIView()
        selected.view.addSubview(focusedView)
        let otherWindow = UIWindow(frame: window.frame)
        otherWindow.rootViewController = UIViewController()
        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isUnpresentedRootView(focusedView, in: otherWindow)
        )
    }

    func testUnattachedAndHiddenPresentationsDoNotBlockNavigation() {
        let focusedView = UIView()
        selected.view.addSubview(focusedView)
        let presentation = UIViewController()
        XCTAssertFalse(
            TVNavigationExitProtectionFocus.blocksNavigation(
                presentation, focusedView: focusedView, in: window
            )
        )

        selected.view.addSubview(presentation.view)
        XCTAssertTrue(
            TVNavigationExitProtectionFocus.blocksNavigation(
                presentation, focusedView: focusedView, in: window
            )
        )
        presentation.view.isHidden = true
        XCTAssertFalse(
            TVNavigationExitProtectionFocus.blocksNavigation(
                presentation, focusedView: focusedView, in: window
            )
        )
    }

    func testSearchPresentationOnlyBlocksFocusInsideSearch() {
        let focusedNavigation = UIView()
        selected.view.addSubview(focusedNavigation)
        let search = UISearchController(searchResultsController: UIViewController())
        selected.view.addSubview(search.view)
        let focusedSearch = UIView()
        search.view.addSubview(focusedSearch)

        XCTAssertFalse(
            TVNavigationExitProtectionFocus.blocksNavigation(
                search, focusedView: focusedNavigation, in: window
            )
        )
        XCTAssertTrue(
            TVNavigationExitProtectionFocus.blocksNavigation(
                search, focusedView: focusedSearch, in: window
            )
        )
    }

    private func exitProtectionRecognizers(in window: UIWindow) -> [UIGestureRecognizer] {
        (window.gestureRecognizers ?? []).filter {
            $0.name == "Plozz navigation exit protection"
        }
    }
}

@MainActor
private final class NonViewFocusItem: NSObject, UIFocusItem {
    weak var parentFocusEnvironment: (any UIFocusEnvironment)?
    var preferredFocusEnvironments: [any UIFocusEnvironment] { [] }
    var focusItemContainer: (any UIFocusItemContainer)? { nil }
    var canBecomeFocused: Bool { true }
    var frame: CGRect { .zero }

    init(parent: (any UIFocusEnvironment)?) {
        parentFocusEnvironment = parent
        super.init()
    }

    func setNeedsFocusUpdate() {}
    func updateFocusIfNeeded() {}
    func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool { true }
    func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {}
}
#endif
