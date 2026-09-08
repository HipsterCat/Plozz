#if os(tvOS)
import XCTest
import UIKit
import SwiftUI
import CoreModels
@testable import AppShell

@MainActor
final class NavigationRowFocusRequesterTests: XCTestCase {
    func testOpeningLongNavigationRevealsSelectedSettingsBeforeNativeFocus() async throws {
        let profile = Profile(name: "Viewer")
        let entries = (0..<30).map { index in
            NavigationRailLibraryEntry(
                key: "account:\(index)",
                library: AggregatedLibrary(
                    accountID: "account", accountName: "Account", serverName: "Server",
                    providerKind: .jellyfin,
                    library: MediaLibrary(id: "\(index)", title: "Library \(index)", kind: .movie)
                )
            )
        }
        func rail(token: Int, opening: Bool) -> NavigationRailView {
            NavigationRailView(
                profile: profile, entries: entries,
                destinations: [.home] + entries.map(\.destination) + [.settings],
                selection: .constant(.settings), isExpandedOutward: .constant(false),
                onOpenProfileSwitcher: {}, focusRequestToken: token,
                opensExpanded: opening
            )
        }
        let host = UIHostingController(rootView: rail(token: 0, opening: false))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let scroll = try XCTUnwrap(
            descendantViews(of: host.view).compactMap { $0 as? UIScrollView }
                .first { $0.contentSize.height > $0.bounds.height }
        )
        XCTAssertGreaterThan(scroll.contentOffset.y, 0, "Initial entry must reveal a selected row below the fold")
        scroll.setContentOffset(.zero, animated: false)
        host.rootView = rail(token: 1, opening: true)
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        host.view.layoutIfNeeded()
        let markers = descendantViews(of: scroll).compactMap { $0 as? NavigationRowFocusRequester.RequestView }
        let lastMarker = try XCTUnwrap(markers.max {
            $0.convert($0.bounds, to: scroll).maxY < $1.convert($1.bounds, to: scroll).maxY
        })
        let lastFrame = lastMarker.convert(lastMarker.bounds, to: scroll)
        XCTAssertGreaterThan(scroll.contentOffset.y, 0)
        XCTAssertGreaterThanOrEqual(lastFrame.minY, scroll.bounds.minY - 1, "\(lastFrame) in \(scroll.bounds)")
        XCTAssertLessThanOrEqual(lastFrame.maxY, scroll.bounds.maxY + 1, "\(lastFrame) in \(scroll.bounds)")
        let target = try XCTUnwrap(NavigationRowFocusRequester.target(for: lastMarker, in: window))
        XCTAssertFalse(target === scroll, "Entry must resolve a destination row, not the scroll container")
    }

    private func descendantViews(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendantViews(of: $0) }
    }

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
