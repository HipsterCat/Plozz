#if os(tvOS)
import XCTest
import UIKit
@testable import AppShell

@MainActor
final class SearchPageFocusObserverTests: XCTestCase {
    func testHeaderFocusDoesNotCountAsSearchPageEntry() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let observer = makeObserver(in: window)
        let header = UIButton(frame: CGRect(x: 80, y: 72, width: 175, height: 58))
        let keyboard = UIButton(frame: CGRect(x: 300, y: 250, width: 60, height: 60))
        let result = UIButton(frame: CGRect(x: 300, y: 500, width: 220, height: 330))
        [header, keyboard, result].forEach { window.addSubview($0) }
        XCTAssertFalse(observer.containsFocus(header))
        XCTAssertTrue(observer.containsFocus(keyboard))
        XCTAssertTrue(observer.containsFocus(result))
        XCTAssertFalse(observer.containsFocus(nil))
    }

    func testVirtualKeyboardAndHeaderItemsUseTheirOwnFrames() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let observer = makeObserver(in: window)
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        let header = VirtualFocusItem(
            parent: container,
            frame: CGRect(x: 80, y: 72, width: 175, height: 58)
        )
        let keyboard = VirtualFocusItem(
            parent: container,
            frame: CGRect(x: 300, y: 250, width: 60, height: 60)
        )
        XCTAssertFalse(observer.containsFocus(header))
        XCTAssertTrue(observer.containsFocus(keyboard))
    }

    func testOtherWindowsCannotReleaseTheEntryGate() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let other = UIWindow(frame: window.frame)
        let observer = makeObserver(in: window)
        let button = UIButton(frame: CGRect(x: 300, y: 250, width: 60, height: 60))
        other.addSubview(button)
        XCTAssertFalse(observer.containsFocus(button))
    }

    func testDisabledFocusTargetCannotReleaseTheEntryGate() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let observer = makeObserver(in: window)
        let previous = UIButton(frame: CGRect(x: 100, y: 200, width: 200, height: 60))
        window.addSubview(previous)
        previous.isEnabled = false
        XCTAssertFalse(observer.containsFocus(previous))
    }

    func testReportsActualContentFocusOnlyOncePerEntry() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let observer = makeObserver(in: window)
        let header = UIButton(frame: CGRect(x: 80, y: 72, width: 175, height: 58))
        let keyboard = UIButton(frame: CGRect(x: 300, y: 250, width: 60, height: 60))
        window.addSubview(header)
        window.addSubview(keyboard)
        var reports = 0
        observer.onFocusEntered = { reports += 1 }
        observer.isEnabled = true
        observer.reportFocus(header)
        XCTAssertEqual(reports, 0)
        observer.reportFocus(keyboard)
        observer.reportFocus(keyboard)
        XCTAssertEqual(reports, 1)
        observer.isEnabled = true
        observer.reportFocus(keyboard)
        XCTAssertEqual(reports, 2)
        observer.stop()
        observer.reportFocus(keyboard)
        XCTAssertEqual(reports, 2)
    }

    func testDetachedObserverCannotReportContentFocus() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let observer = makeObserver(in: window)
        let keyboard = UIButton(frame: CGRect(x: 300, y: 250, width: 60, height: 60))
        window.addSubview(keyboard)
        observer.removeFromSuperview()
        XCTAssertFalse(observer.containsFocus(keyboard))
    }

    private func makeObserver(in window: UIWindow) -> SearchPageFocusObserver.ObserverView {
        let observer = SearchPageFocusObserver.ObserverView(
            frame: CGRect(x: 0, y: 140, width: 1920, height: 940)
        )
        window.addSubview(observer)
        return observer
    }
}

@MainActor
private final class VirtualFocusItem: NSObject, UIFocusItem {
    let frame: CGRect
    weak var parentFocusEnvironment: (any UIFocusEnvironment)?
    var preferredFocusEnvironments: [any UIFocusEnvironment] { [] }
    var focusItemContainer: (any UIFocusItemContainer)? { nil }
    var canBecomeFocused: Bool { true }

    init(parent: any UIFocusEnvironment, frame: CGRect) {
        self.parentFocusEnvironment = parent
        self.frame = frame
    }

    func setNeedsFocusUpdate() {}
    func updateFocusIfNeeded() {}
    func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool { true }
    func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {}
}
#endif
