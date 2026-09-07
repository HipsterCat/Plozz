#if os(tvOS)
import XCTest
import UIKit
@testable import AppShell

@MainActor
final class NavigationRowFocusRequesterTests: XCTestCase {
    func testHandoffReevaluatesWindowAndConfirmsActualRowFocus() {
        let window = UIWindow()
        let row = UIButton()
        let focusSystem = FocusSystemStub(nextFocusedItem: row)
        XCTAssertTrue(NavigationRowFocusRequester.handoff(to: row, in: window, using: focusSystem))
        XCTAssertEqual(focusSystem.requests.count, 2)
        XCTAssertTrue(focusSystem.requests[0] === row)
        XCTAssertTrue(focusSystem.requests[1] === window)
        XCTAssertEqual(focusSystem.committedRequestCount, 2)
    }

    func testHandoffDoesNotAcknowledgeFocusRemainingOnCapsule() {
        let window = UIWindow()
        let row = UIButton()
        let capsule = UIButton()
        let focusSystem = FocusSystemStub(nextFocusedItem: capsule)
        XCTAssertFalse(NavigationRowFocusRequester.handoff(to: row, in: window, using: focusSystem))
    }

    func testFindsFocusableRowInsideNonFocusableLayoutContainer() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let container = UIView(frame: CGRect(x: 20, y: 100, width: 426, height: 200))
        let row = UIButton(frame: CGRect(x: 54, y: 42, width: 318, height: 64))
        container.addSubview(row)
        window.addSubview(container)
        let marker = UIView(frame: CGRect(x: 86, y: 152, width: 294, height: 44))
        window.addSubview(marker)
        XCTAssertFalse(container.canBecomeFocused)
        XCTAssertTrue(NavigationRowFocusRequester.target(for: marker, in: window) === row)
    }

    func testChoosesRowRatherThanLargerFocusableContainer() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let broad = UIButton(frame: CGRect(x: 0, y: 100, width: 426, height: 200))
        let row = UIButton(frame: CGRect(x: 54, y: 142, width: 318, height: 64))
        let marker = UIView(frame: CGRect(x: 66, y: 152, width: 294, height: 44))
        [broad, row, marker].forEach { window.addSubview($0) }
        XCTAssertTrue(NavigationRowFocusRequester.target(for: marker, in: window) === row)
    }

    func testDisabledRowAndHeaderCapsuleAreNotTargets() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let header = UIButton(frame: CGRect(x: 83, y: 72, width: 174.5, height: 58))
        let row = UIButton(frame: CGRect(x: 54, y: 142, width: 318, height: 64))
        row.isEnabled = false
        let marker = UIView(frame: CGRect(x: 66, y: 152, width: 294, height: 44))
        [header, row, marker].forEach { window.addSubview($0) }
        XCTAssertNil(NavigationRowFocusRequester.target(for: marker, in: window))
        row.isEnabled = true
        XCTAssertTrue(NavigationRowFocusRequester.target(for: marker, in: window) === row)
    }

    func testUnlaidOutMarkerDoesNotChooseAnArbitraryControl() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let row = UIButton(frame: window.bounds)
        let marker = UIView(frame: .zero)
        window.addSubview(row)
        window.addSubview(marker)
        XCTAssertNil(NavigationRowFocusRequester.target(for: marker, in: window))
    }
}

@MainActor
private final class FocusSystemStub: NavigationFocusUpdating {
    private let nextFocusedItem: any UIFocusItem
    private(set) var focusedItem: (any UIFocusItem)?
    private(set) var requests: [any UIFocusEnvironment] = []
    private(set) var committedRequestCount = 0

    init(nextFocusedItem: any UIFocusItem) { self.nextFocusedItem = nextFocusedItem }

    func requestFocusUpdate(to environment: any UIFocusEnvironment) {
        requests.append(environment)
    }

    func updateFocusIfNeeded() {
        committedRequestCount = requests.count
        focusedItem = nextFocusedItem
    }
}
#endif
