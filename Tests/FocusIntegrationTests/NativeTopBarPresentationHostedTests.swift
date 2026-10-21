#if os(tvOS)
import CoreModels
import CoreUI
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import AppShell

@MainActor
final class NativeTopBarPresentationHostedTests: XCTestCase {
    func testRapidNativeTabChangesAndDetailReturnsKeepDistinctControllers() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let model = TransitionModel()
        let host = UIHostingController(rootView: TransitionFixture(model: model))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        for _ in 0..<20 {
            for destination in [NavigationRailDestination.settings, .watchlist, .home] {
                model.selection = destination
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            model.path = ["detail"]
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            model.path = []
        }
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        func tabController(_ controller: UIViewController) -> UITabBarController? {
            if let tabs = controller as? UITabBarController { return tabs }
            return controller.children.lazy.compactMap { tabController($0) }.first
        }
        let tabs = try XCTUnwrap(tabController(host))
        let controllers = try XCTUnwrap(tabs.viewControllers).map(ObjectIdentifier.init)
        XCTAssertEqual(controllers.count, 3)
        XCTAssertEqual(Set(controllers).count, 3)
        XCTAssertNotNil(tabs.selectedViewController)
        XCTAssertEqual(model.selection, .home)
    }

    @Observable
    final class TransitionModel {
        var selection = NavigationRailDestination.home
        var path: [String] = []
    }

    private struct TransitionFixture: View {
        @Bindable var model: TransitionModel

        var body: some View {
            NativeTopBarNavigation(
                destinations: [.home, .watchlist, .settings], selection: $model.selection,
                preventsAccidentalExit: false,
                content: { destination, _ in
                    AnyView(
                        NavigationStack(path: destination == .home ? $model.path : .constant([])) {
                            Text(verbatim: destination.storageValue)
                                .navigationDestination(for: String.self) { Text(verbatim: $0) }
                        }
                    )
                },
                label: { AnyView(Label($0.storageValue, systemImage: "square")) }
            )
        }
    }

    func testLibrariesHaveDistinctNativeTabsAndOnlyTheSelectedRootIsActive() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let model = Model()
        let host = FocusHost(rootView: Fixture(model: model))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }

        for destination in model.destinations {
            model.selection = destination
            let ready = ContinuousClock.now + .seconds(5)
            repeat {
                window.layoutIfNeeded()
                if let button = model.buttons[destination], button.window != nil, button.isEnabled,
                   model.buttons.allSatisfy({ other, view in
                       other == destination || !view.isEnabled || view.window == nil
                   }) { break }
                try await Task.sleep(for: .milliseconds(20))
            } while ContinuousClock.now < ready
            let button = try XCTUnwrap(model.buttons[destination])
            XCTAssertNotNil(button.window, "Each library must mount its own content.")
            XCTAssertTrue(button.isEnabled)
            XCTAssertEqual(button.title(for: .normal), destination.storageValue)
            XCTAssertEqual(model.selection, destination)
            for (other, view) in model.buttons where other != destination {
                XCTAssertFalse(view.isEnabled && view.window != nil, "A retained \(other) root must not consume routes.")
            }
            let focus = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
            host.target = button
            let focused = ContinuousClock.now + .seconds(3)
            repeat {
                window.layoutIfNeeded()
                focus.requestFocusUpdate(to: host)
                focus.updateFocusIfNeeded()
                if button.isFocused { break }
                try await Task.sleep(for: .milliseconds(20))
            } while ContinuousClock.now < focused
            XCTAssertTrue(button.isFocused, "\(destination) must accept native content focus.")
        }

        let removed = NavigationRailDestination.library("server-b:movies")
        model.destinations.removeAll { $0 == removed }
        model.selection = NavigationRailPlan.resolvedSelection(removed, destinations: model.destinations)
        window.layoutIfNeeded()
        XCTAssertEqual(model.selection, .home)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        attachment.name = "Horizontal navigation with library shortcuts"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private final class FocusHost<Content: View>: UIHostingController<Content> {
        weak var target: UIView?

        override var preferredFocusEnvironments: [any UIFocusEnvironment] {
            target.map { [$0] } ?? super.preferredFocusEnvironments
        }
    }

    @Observable
    final class Model {
        var selection = NavigationRailDestination.home
        var destinations: [NavigationRailDestination] = [
            .home, .library("server-a:movies"), .library("server-b:movies"),
            .allLibraries, .liveTV, .search, .settings
        ]
        @ObservationIgnored var buttons: [NavigationRailDestination: UIButton] = [:]
    }

    private struct Fixture: View {
        @Bindable var model: Model

        var body: some View {
            NativeTopBarNavigation(
                destinations: model.destinations, selection: $model.selection,
                preventsAccidentalExit: false,
                content: { destination, active in
                    AnyView(Probe(destination: destination, active: active, model: model)
                        .frame(width: 500, height: 100))
                },
                label: { destination in
                    switch destination {
                    case let .library(key):
                        let library = AggregatedLibrary(
                            accountID: key, accountName: key, serverName: key, providerKind: .jellyfin,
                            library: MediaLibrary(id: "movies", title: "Movies", kind: .movie)
                        )
                        return AnyView(MainTabView.navigationLibraryLabel(
                            .init(key: key, library: library), usesCompactSidebarText: false
                        ))
                    default:
                        return AnyView(Label(destination.storageValue, systemImage: "square"))
                    }
                }
            )
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
            button.isEnabled = active
        }
    }
}
#endif
