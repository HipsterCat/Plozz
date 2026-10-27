#if os(tvOS)
import CoreModels
import CoreUI
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import AppShell

@MainActor
final class TopBarPresentationHostedTests: XCTestCase {
    func testHorizontalFocusOwnerAllowsLeftRightAndKeepsSidebarPolicyUnchanged() {
        let owner = NavigationRailFocusHostController()
        owner.isNavigationFocused = true
        XCTAssertFalse(owner.allowsFocusUpdate(heading: .right))
        XCTAssertTrue(owner.allowsFocusUpdate(heading: .down))
        owner.contentExitHeading = .down
        XCTAssertTrue(owner.allowsFocusUpdate(heading: .left))
        XCTAssertTrue(owner.allowsFocusUpdate(heading: .right))
        XCTAssertFalse(owner.allowsFocusUpdate(heading: .down))
        owner.isNavigationFocused = false
        XCTAssertTrue(owner.allowsFocusUpdate(heading: .down))
    }

    func testHorizontalSelectionMountsOnlyTheRequestedLibraryAndRetainsLiveTV() async throws {
        let (window, previous) = try await makeWindow()
        let model = Model()
        let host = UIHostingController(rootView: Fixture(model: model))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }

        let visits = [NavigationRailDestination.liveTV] + (1...20).map { .library("plex:\($0)") }
        for destination in visits {
            model.selection = destination
            try await waitForPage(destination, model: model, window: window)
            XCTAssertEqual(model.buttons[destination]?.title(for: .normal), destination.storageValue)
            for (other, button) in model.buttons where other != destination && other != .liveTV {
                XCTAssertNil(button.window, "Unselected library grids must not accumulate behind the strip.")
            }
            XCTAssertNil(find(UITabBarController.self, in: host), "Horizontal navigation must not start native tab transitions.")
        }
        let liveTV = try XCTUnwrap(model.buttons[.liveTV])
        model.selection = .liveTV
        try await waitForPage(.liveTV, model: model, window: window)
        XCTAssertTrue(model.buttons[.liveTV] === liveTV, "The guide must retain its state across library visits.")
    }

    func testSettingsReturnPreservesTheHorizontalFocusOwner() async throws {
        let (window, previous) = try await makeWindow()
        let model = Model()
        let host = UIHostingController(rootView: Fixture(model: model))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await waitForPage(.home, model: model, window: window)
        let owner = try XCTUnwrap(find(NavigationRailFocusHostController.self, in: host))
        for _ in 0..<3 {
            for destination in [NavigationRailDestination.settings, .watchlist, .liveTV, .home] {
                model.selection = destination
                window.layoutIfNeeded()
                if destination != .settings {
                    try await waitForPage(destination, model: model, window: window)
                } else {
                    try await Task.sleep(for: .milliseconds(200))
                    XCTAssertEqual(model.selection, .settings, "Hidden chrome must not overwrite Settings selection.")
                    XCTAssertFalse(owner.isNavigationFocused)
                }
                XCTAssertTrue(find(NavigationRailFocusHostController.self, in: host) === owner)
            }
        }
    }

    private func makeWindow() async throws -> (UIWindow, UIWindow?) {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        return (UIWindow(windowScene: scene), scene.windows.first(where: \.isKeyWindow))
    }

    private func waitForPage(_ destination: NavigationRailDestination, model: Model, window: UIWindow) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        repeat {
            window.layoutIfNeeded()
            if model.buttons[destination]?.window === window { return }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        XCTFail("Missing horizontal destination: \(destination)")
    }

    private func find<T: UIViewController>(_ type: T.Type, in controller: UIViewController) -> T? {
        if let result = controller as? T { return result }
        return controller.children.lazy.compactMap { self.find(type, in: $0) }.first
    }

    @Observable
    final class Model {
        var selection = NavigationRailDestination.home
        let destinations: [NavigationRailDestination] =
            [.home, .watchlist, .liveTV, .search] + (1...20).map { .library("plex:\($0)") }
        @ObservationIgnored var buttons: [NavigationRailDestination: UIButton] = [:]
    }

    private struct Fixture: View {
        @Bindable var model: Model

        var body: some View {
            SettingsNavigationShell(style: .tabBar, showsSettings: model.selection == .settings) { _ in
                TopBarNavigation(
                    destinations: model.destinations, selection: $model.selection,
                    preventsAccidentalExit: true,
                    content: { destination, active in
                        AnyView(Probe(destination: destination, active: active, model: model)
                            .frame(width: 500, height: 100))
                    },
                    label: { AnyView(Label($0.storageValue, systemImage: "square")) }
                )
            } settings: {
                Text("Settings")
            }
        }
    }

    private struct Probe: UIViewRepresentable {
        let destination: NavigationRailDestination
        let active: Bool
        let model: Model

        func makeUIView(context: Context) -> UIButton {
            let button = UIButton(type: .system)
            button.setTitle(destination.storageValue, for: .normal)
            model.buttons[destination] = button
            return button
        }

        func updateUIView(_ button: UIButton, context: Context) {
            button.isEnabled = active && context.environment.isEnabled
        }
    }
}
#endif
