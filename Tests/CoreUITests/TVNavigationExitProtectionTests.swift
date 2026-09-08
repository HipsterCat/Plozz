#if os(tvOS) && canImport(UIKit)
import XCTest
import UIKit
@testable import CoreUI

@MainActor
final class TVNavigationExitProtectionTests: XCTestCase {
    private var window: UIWindow!
    private var tabs: UITabBarController!
    private var selected: UIViewController!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        tabs = UITabBarController()
        selected = UIViewController()
        tabs.viewControllers = [selected, UIViewController()]
        tabs.selectedIndex = 0
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        tabs.view.layoutIfNeeded()
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        tabs = nil
        selected = nil
        super.tearDown()
    }

    func testTabBarFocusIsProtected() {
        let focusedView = UIView()
        tabs.tabBar.addSubview(focusedView)

        XCTAssertTrue(
            TVNavigationExitProtectionFocus.isRootNavigationView(focusedView, in: window)
        )
    }

    func testSelectedContentFocusIsNotProtected() {
        let focusedView = UIView()
        selected.view.addSubview(focusedView)

        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isRootNavigationView(focusedView, in: window)
        )
    }

    func testInactiveTabContentIsNotMistakenForSidebarChrome() {
        let inactive = tabs.viewControllers![1]
        tabs.view.addSubview(inactive.view)
        let focusedView = UIView()
        inactive.view.addSubview(focusedView)

        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isRootNavigationView(focusedView, in: window)
        )
    }

    func testSidebarControllerFocusIsProtectedWithoutPrivateTypeChecks() {
        let content = selected!
        // Native SwiftUI tabs use UITab; legacy addChild registers every child
        // as tab content, which cannot represent a separate sidebar controller.
        tabs.tabs = [
            UITab(title: "Home", image: nil, identifier: "home") { _ in content }
        ]
        let sidebar = UIViewController()
        tabs.addChild(sidebar)
        tabs.view.addSubview(sidebar.view)
        sidebar.didMove(toParent: tabs)
        let focusedView = UIView()
        sidebar.view.addSubview(focusedView)

        XCTAssertTrue(
            TVNavigationExitProtectionFocus.isRootNavigationView(focusedView, in: window)
        )
    }

    func testUnrelatedOverlayFocusIsNotProtected() {
        let overlay = UIView()
        window.addSubview(overlay)

        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isRootNavigationView(overlay, in: window)
        )
    }

    func testTextInputInNavigationChromeIsNotProtected() {
        let sidebar = UIViewController()
        tabs.addChild(sidebar)
        tabs.view.addSubview(sidebar.view)
        sidebar.didMove(toParent: tabs)
        let searchField = UITextField()
        sidebar.view.addSubview(searchField)

        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isRootNavigationView(searchField, in: window)
        )
    }

    func testPushedDetailDisablesProtectionEvenWithTabBarFocus() {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        tabs.viewControllers = [navigation]
        navigation.pushViewController(UIViewController(), animated: false)
        let focusedView = UIView()
        tabs.tabBar.addSubview(focusedView)

        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isRootNavigationView(focusedView, in: window)
        )
    }

    func testPresentedControllerDisablesProtectionEvenWithTabBarFocus() {
        let modal = UIViewController()
        tabs.present(modal, animated: false)
        let focusedView = UIView()
        tabs.tabBar.addSubview(focusedView)

        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isRootNavigationView(focusedView, in: window)
        )
    }

    func testCoordinatorDetachesWhenMarkerLeavesItsWindow() {
        let coordinator = TVNavigationExitProtection.Coordinator()
        coordinator.update(isEnabled: true, window: window)
        XCTAssertEqual(exitProtectionRecognizers(in: window).count, 1)

        coordinator.move(to: nil)
        XCTAssertTrue(exitProtectionRecognizers(in: window).isEmpty)
    }

    func testCoordinatorMovesRecognizerBetweenWindows() {
        let secondWindow = UIWindow(frame: window.frame)
        let coordinator = TVNavigationExitProtection.Coordinator()
        coordinator.update(isEnabled: true, window: window)

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

    func testCustomNavigationYieldsToPresentedContentAndTextInput() {
        let focusedView = UIView()
        selected.view.addSubview(focusedView)
        XCTAssertTrue(
            TVNavigationExitProtectionFocus.isUnpresentedRootView(focusedView, in: window)
        )
        let textField = UITextField()
        selected.view.addSubview(textField)
        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isUnpresentedRootView(textField, in: window)
        )
        selected.present(UIViewController(), animated: false)
        XCTAssertFalse(
            TVNavigationExitProtectionFocus.isUnpresentedRootView(focusedView, in: window)
        )
    }

    private func exitProtectionRecognizers(in window: UIWindow) -> [UIGestureRecognizer] {
        (window.gestureRecognizers ?? []).filter {
            $0.name == "Plozz navigation exit protection"
        }
    }
}
#endif
