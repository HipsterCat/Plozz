#if os(iOS)
import UIKit
import XCTest
@testable import AppShelliOS

@MainActor
final class SettingsTabDelegateTests: XCTestCase {
    func testOverflowUsesOneBarAndRestoresMoreWithoutReplacingTheTabStack() async throws {
        let root = UIViewController()
        let tabs = UITabBarController()
        let pages = (0..<6).map { _ in UIViewController() }
        tabs.viewControllers = pages
        root.addChild(tabs)
        let more = tabs.moreNavigationController
        let moreRoot = try XCTUnwrap(more.viewControllers.first)
        let original = NavigationDelegate()
        more.delegate = original
        let controller = bridge(in: root)
        let overflow = PlozziOSOverflowNavigation()
        controller.overflowNavigation = overflow
        defer { controller.restore() }
        controller.install()

        more.setViewControllers([moreRoot, pages[5]], animated: false)
        controller.navigationController(more, willShow: pages[5], animated: false)
        controller.navigationController(more, didShow: pages[5], animated: false)
        await Task.yield()

        XCTAssertTrue(more.isNavigationBarHidden, "The outer bar must not sit above the page's NavigationStack.")
        XCTAssertEqual(overflow.destinationIndex, 5)
        XCTAssertTrue(more.topViewController === pages[5], "Keep the original tab controller and its navigation state.")
        XCTAssertGreaterThan(original.willShowCount, 0)
        XCTAssertGreaterThan(original.didShowCount, 0)

        more.setViewControllers([moreRoot], animated: false)
        controller.navigationController(more, willShow: moreRoot, animated: false)
        controller.navigationController(more, didShow: moreRoot, animated: false)
        await Task.yield()

        XCTAssertFalse(more.isNavigationBarHidden)
        XCTAssertNil(overflow.destinationIndex)
        controller.restore()
        XCTAssertTrue(more.delegate === original)
    }

    func testRemovingOverflowBridgeRestoresOriginalNavigationBarVisibility() {
        let root = UIViewController()
        let tabs = UITabBarController()
        let pages = (0..<6).map { _ in UIViewController() }
        tabs.viewControllers = pages
        root.addChild(tabs)
        let more = tabs.moreNavigationController
        let controller = bridge(in: root)
        controller.overflowNavigation = PlozziOSOverflowNavigation()
        controller.install()
        controller.navigationController(more, willShow: pages[5], animated: false)
        XCTAssertTrue(more.isNavigationBarHidden)

        controller.restore()

        XCTAssertFalse(more.isNavigationBarHidden)
    }

    func testOverlappingBridgesNeverForwardToEachOther() {
        let root = UIViewController()
        let tabs = UITabBarController()
        let original = Delegate()
        tabs.delegate = original
        root.addChild(tabs)
        let first = bridge(in: root)
        let second = bridge(in: root)
        defer { first.restore(); second.restore() }

        for _ in 0..<4 {
            first.install()
            second.install()
        }
        let selection = #selector(UITabBarControllerDelegate.tabBarController(_:didSelect:))
        XCTAssertTrue(second.responds(to: selection))
        XCTAssertTrue(second.forwardingTarget(for: selection) as AnyObject === original)
        XCTAssertFalse(second.responds(to: NSSelectorFromString("plozzUnknownDelegateSelector")))

        first.restore()
        XCTAssertTrue(tabs.delegate === second, "A displaced bridge must not uninstall its replacement.")
        second.restore()
        XCTAssertTrue(tabs.delegate === original)
    }

    func testSettingsRemainsAnActionAndOtherSelectionsReachOriginalDelegate() {
        let root = UIViewController()
        let tabs = UITabBarController()
        let original = Delegate()
        let home = UIViewController()
        let settings = UIViewController()
        tabs.viewControllers = [home, settings]
        tabs.delegate = original
        root.addChild(tabs)
        let controller = bridge(in: root)
        defer { controller.restore() }
        var actions = 0
        controller.action = { actions += 1 }
        controller.install()

        XCTAssertFalse(controller.tabBarController(tabs, shouldSelect: settings))
        XCTAssertEqual(actions, 1)
        XCTAssertEqual(original.selections, 0)
        XCTAssertFalse(controller.tabBarController(tabs, shouldSelect: home))
        XCTAssertEqual(original.selections, 1)
        XCTAssertEqual(actions, 1)
    }

    func testNativeTabSelectionPreservesSettingsActionAndForwarding() {
        let root = UIViewController()
        let tabs = UITabBarController()
        let original = Delegate()
        let home = UITab(title: "Home", image: nil, identifier: "home") { _ in UIViewController() }
        let settings = UITab(title: "Settings", image: nil, identifier: "settings") { _ in UIViewController() }
        tabs.tabs = [home, settings]
        tabs.delegate = original
        root.addChild(tabs)
        let controller = bridge(in: root)
        defer { controller.restore() }
        var actions = 0
        controller.action = { actions += 1 }
        controller.install()

        XCTAssertFalse(controller.tabBarController(tabs, shouldSelectTab: settings))
        XCTAssertEqual(actions, 1)
        XCTAssertFalse(controller.tabBarController(tabs, shouldSelectTab: home))
        XCTAssertEqual(original.selections, 1)
    }

    func testRemovalDoesNotOverwriteAnExternallyReplacedDelegate() {
        let root = UIViewController()
        let tabs = UITabBarController()
        let original = Delegate()
        let replacement = Delegate()
        tabs.delegate = original
        root.addChild(tabs)
        let controller = bridge(in: root)
        controller.install()
        tabs.delegate = replacement

        controller.restore()

        XCTAssertTrue(tabs.delegate === replacement)
    }

    private func bridge(in root: UIViewController) -> PlozziOSSettingsTabAction.Controller {
        let controller = PlozziOSSettingsTabAction.Controller()
        controller.tabIndex = 1
        root.addChild(controller)
        return controller
    }

    private final class Delegate: NSObject, UITabBarControllerDelegate {
        var selections = 0

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            selections += 1
            return false
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            selections += 1
            return false
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {}
    }

    private final class NavigationDelegate: NSObject, UINavigationControllerDelegate {
        var willShowCount = 0
        var didShowCount = 0

        func navigationController(
            _ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool
        ) {
            willShowCount += 1
        }

        func navigationController(
            _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
        ) {
            didShowCount += 1
        }
    }
}
#endif
