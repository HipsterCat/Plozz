import XCTest
@testable import FeaturePlayback

final class LiveChannelHUDInactivityTests: XCTestCase {
    func testNoInputRetainsTheExistingFourSecondGrace() {
        let inactivity = LiveChannelHUDInactivity()
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 10), 4)
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 13), 1)
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 14), 0)
    }

    func testNativeMovementExtendsAlreadyRunningFullscreenCountdown() {
        var inactivity = LiveChannelHUDInactivity()
        inactivity.recordInteraction(at: 5.23)
        inactivity.recordInteraction(at: 5.65)
        XCTAssertEqual(
            inactivity.remainingDelay(startedAt: 1.8, now: 5.89),
            3.76,
            accuracy: 0.001
        )
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 1.8, now: 9.65), 0, accuracy: 0.001)
    }

    func testMovementAtRowBoundaryAlsoRenewsGraceWithoutFocusChanging() {
        var inactivity = LiveChannelHUDInactivity()
        inactivity.recordInteraction(at: 13)
        inactivity.recordInteraction(at: 16)
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 17), 3)
    }

    func testLateOlderActivityCannotShortenCurrentDeadline() {
        var inactivity = LiveChannelHUDInactivity()
        inactivity.recordInteraction(at: 20)
        inactivity.recordInteraction(at: 19)
        XCTAssertEqual(inactivity.remainingDelay(startedAt: 10, now: 21), 3)
    }
}

#if DEBUG && os(tvOS)
import UIKit

@MainActor
final class LiveChannelFocusActivityObserverTests: XCTestCase {
    func testNativeFocusAndDirectionalPressesRefreshOnlyThisHUDWithoutConsumingInput() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let observer = LiveChannelFocusActivityObserver.ObserverView(
            frame: CGRect(x: 100, y: 100, width: 300, height: 100)
        )
        let control = FocusItem(frame: CGRect(x: 140, y: 120, width: 60, height: 44))
        let outside = FocusItem(frame: CGRect(x: 440, y: 120, width: 60, height: 44))
        window.addSubview(observer)
        window.addSubview(control)
        window.addSubview(outside)
        defer { observer.stop() }
        var events = 0
        observer.onActivity = { events += 1 }

        observer.reportActivity(for: control)
        XCTAssertEqual(events, 1)
        XCTAssertFalse(observer.observePress(.rightArrow, focusedItem: control))
        XCTAssertFalse(observer.observePress(.rightArrow, focusedItem: control))
        XCTAssertEqual(events, 3)
        XCTAssertFalse(observer.observePress(.select, focusedItem: control))
        XCTAssertFalse(observer.observePress(.playPause, focusedItem: control))
        XCTAssertEqual(events, 3)
        observer.reportActivity(for: outside)
        XCTAssertFalse(observer.observePress(.leftArrow, focusedItem: outside))
        XCTAssertEqual(events, 3)
    }

    func testOtherWindowsAndDetachedHUDCannotReportActivity() {
        let firstWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let secondWindow = UIWindow(frame: firstWindow.frame)
        let observer = LiveChannelFocusActivityObserver.ObserverView(frame: firstWindow.bounds)
        let otherControl = FocusItem(frame: CGRect(x: 10, y: 10, width: 80, height: 44))
        firstWindow.addSubview(observer)
        secondWindow.addSubview(otherControl)
        var events = 0
        observer.onActivity = { events += 1 }
        observer.reportActivity(for: otherControl)
        XCTAssertEqual(events, 0)
        observer.removeFromSuperview()
        observer.reportActivity(for: otherControl)
        XCTAssertEqual(events, 0)
        XCTAssertFalse(firstWindow.gestureRecognizers?.contains { $0.delegate === observer } ?? false)
    }

    func testStopRemovesOwnedPressObserverAndDoesNotChangeExistingRecognizers() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let existing = UITapGestureRecognizer()
        window.addGestureRecognizer(existing)
        let observer = LiveChannelFocusActivityObserver.ObserverView(frame: window.bounds)
        window.addSubview(observer)
        XCTAssertTrue(window.gestureRecognizers?.contains { $0.delegate === observer } ?? false)
        observer.stop()
        XCTAssertFalse(window.gestureRecognizers?.contains { $0.delegate === observer } ?? false)
        XCTAssertTrue(window.gestureRecognizers?.contains { $0 === existing } ?? false)
    }

    private final class FocusItem: UIView {
        override var canBecomeFocused: Bool { true }
    }
}
#endif
