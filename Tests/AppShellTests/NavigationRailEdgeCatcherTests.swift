#if os(tvOS)
import XCTest
import UIKit
@testable import AppShell

@MainActor
final class NavigationRailEdgeCatcherTests: XCTestCase {
    func testRowSwipeUsesMovementOriginRatherThanTouchDownCoordinates() {
        var travel = NavigationRailEdgeCatcher.SwipeTravel()
        // Measured scrolling-row input: touch-down was x=1919.5, but the first
        // movement sample jumps into the wide row's coordinate frame.
        travel.moved(to: CGPoint(x: 25655.846, y: 835.542))
        XCTAssertNil(travel.direction)
        travel.moved(to: CGPoint(x: 25447.068, y: 838.552))
        travel.moved(to: CGPoint(x: 25228.728, y: 867.150))
        XCTAssertEqual(travel.direction, .left)
    }

    func testRightSwipeFromRail() {
        var travel = NavigationRailEdgeCatcher.SwipeTravel()
        travel.moved(to: CGPoint(x: 1055.624, y: 543.01))
        travel.moved(to: CGPoint(x: 1213.402, y: 543.01))
        XCTAssertEqual(travel.direction, .right)
    }

    func testRestingThumbVerticalScrollingAndDiagonalMovementAreIgnored() {
        for end in [CGPoint(x: 110, y: 100), CGPoint(x: 105, y: 250), CGPoint(x: 200, y: 200)] {
            var travel = NavigationRailEdgeCatcher.SwipeTravel()
            XCTAssertNil(travel.direction)
            travel.moved(to: CGPoint(x: 100, y: 100))
            travel.moved(to: end)
            XCTAssertNil(travel.direction)
        }
    }

    func testNewContactCannotReusePreviousSwipeDirection() {
        var travel = NavigationRailEdgeCatcher.SwipeTravel()
        travel.moved(to: CGPoint(x: 200, y: 100))
        travel.moved(to: CGPoint(x: 100, y: 100))
        XCTAssertEqual(travel.direction, .left)
        travel = NavigationRailEdgeCatcher.SwipeTravel()
        travel.moved(to: CGPoint(x: 5000, y: 100))
        XCTAssertNil(travel.direction)
    }

    func testTouchObserverDoesNotReceivePhysicalPresses() {
        let recognizer = NavigationRailEdgeCatcher.BoundarySwipeRecognizer()
        XCTAssertTrue(recognizer.allowedPressTypes.isEmpty)
        XCTAssertEqual(recognizer.allowedTouchTypes, [NSNumber(value: UITouch.TouchType.indirect.rawValue)])
    }

    func testPressObserverDoesNotAlsoRecognizeTouchSwipes() {
        let recognizer = NavigationRailEdgeCatcher.LeftPressRecognizer()
        XCTAssertTrue(recognizer.allowedTouchTypes.isEmpty)
        XCTAssertEqual(recognizer.allowedPressTypes, [
            NSNumber(value: UIPress.PressType.leftArrow.rawValue),
            NSNumber(value: UIPress.PressType.rightArrow.rawValue)
        ])
    }

    func testObserversCannotInterfereWithNativeNavigation() {
        let nativePan = UIPanGestureRecognizer()
        let observers: [UIGestureRecognizer] = [
            NavigationRailEdgeCatcher.LeftPressRecognizer(),
            NavigationRailEdgeCatcher.BoundarySwipeRecognizer()
        ]
        for observer in observers {
            XCTAssertFalse(observer.canPrevent(nativePan))
            XCTAssertFalse(observer.canBePrevented(by: nativePan))
            XCTAssertFalse(observer.cancelsTouchesInView)
            XCTAssertFalse(observer.delaysTouchesBegan)
            XCTAssertFalse(observer.delaysTouchesEnded)
        }
    }

    func testDetachingInstallerRemovesBothObservers() {
        let window = UIWindow()
        let installer = NavigationRailEdgeCatcher.InstallerView()
        window.addSubview(installer)
        XCTAssertTrue(installer.recognizer.view === window)
        XCTAssertTrue(installer.swipeRecognizer.view === window)
        installer.removeFromSuperview()
        XCTAssertNil(installer.recognizer.view)
        XCTAssertNil(installer.swipeRecognizer.view)
    }
}
#endif
