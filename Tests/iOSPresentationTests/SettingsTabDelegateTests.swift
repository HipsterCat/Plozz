#if os(iOS)
import UIKit
import XCTest
@testable import AppShelliOS

@MainActor
final class SettingsTabDelegateTests: XCTestCase {
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
}
#endif
