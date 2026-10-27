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
    func testRapidNativeFocusCoalescesPagesAndCancelsPrunedDestinations() async throws {
        let (window, previous) = try await makeWindow()
        let model = Model()
        model.destinations = [.home, .watchlist, .liveTV, .search]
        let host = UIHostingController(rootView: Fixture(model: model))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await waitForPage(.home, model: model, window: window)
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        window.setNeedsFocusUpdate()
        window.updateFocusIfNeeded()
        let owner = try XCTUnwrap(find(NavigationRailFocusHostController.self, in: host))
        let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
        func focus(_ index: Int) throws {
            let items = focusItems(in: window).sorted {
                $0.frame.midX < $1.frame.midX
            }
            XCTAssertEqual(items.count, model.destinations.count, "Only navigation is eligible during traversal.")
            let target = try XCTUnwrap(items.indices.contains(index) ? items[index] : nil)
            XCTAssertTrue(owner.requestFocus(to: target, using: system))
        }
        let builds = model.contentBuilds
        for index in [1, 2, 3, 2, 1, 3] {
            try focus(index)
            try await Task.sleep(for: .milliseconds(20))
            XCTAssertEqual(model.selection, .home, "Rapid movement must not construct intermediate pages.")
        }
        XCTAssertEqual(model.contentBuilds, builds, "Bar-only focus updates must not rebuild page closures.")
        try await waitForPage(.search, model: model, window: window)
        XCTAssertNil(model.buttons[.watchlist])
        XCTAssertNil(model.buttons[.liveTV])
        try focus(1)
        try await Task.sleep(for: .milliseconds(20))
        model.destinations.removeAll { $0 == .watchlist }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(model.destinations.contains(model.selection), "Native focus may settle on another remaining item.")
        XCTAssertNil(model.buttons[.watchlist], "A removed destination must never construct its delayed preview.")
    }

    func testLiftedSettingsMovementPersistsOnlyAfterAnActualStep() async throws {
        let (window, previous) = try await makeWindow()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let model = NavigationStyleSettingsModel(
            store: NavigationStyleSettingsStore(defaults: defaults),
            layoutStore: NavigationLibraryLayoutStore(defaults: defaults)
        )
        model.style = .tabBar
        let keys = [NavigationLibraryLayout.homeKey, NavigationLibraryLayout.settingsKey]
        let host = UIHostingController(rootView: ReorderFixture(model: model, keys: keys))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(300))
        func input(in controller: UIViewController) -> (any SettingsAdjustmentRemoteInput)? {
            if let input = controller as? any SettingsAdjustmentRemoteInput { return input }
            return controller.children.lazy.compactMap { input(in: $0) }.first
        }
        let remote = try XCTUnwrap(input(in: host))
        XCTAssertTrue(model.libraryLayout.pinsSettingsInTopBar)
        remote.beginPress(.down)
        remote.stopRepeating()
        XCTAssertTrue(model.libraryLayout.pinsSettingsInTopBar, "An end-of-list press is not movement.")
        remote.beginPress(.up)
        remote.stopRepeating()
        XCTAssertFalse(model.libraryLayout.pinsSettingsInTopBar)
        XCTAssertEqual(model.librarySections(available: keys).enabled, Array(keys.reversed()))
        remote.beginPress(.down)
        remote.stopRepeating()
        XCTAssertEqual(model.librarySections(available: keys).enabled, keys)
        XCTAssertFalse(model.libraryLayout.pinsSettingsInTopBar, "Moving Settings back must not repin it.")
    }

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

    private func focusItems(in window: UIWindow) -> [any UIFocusItem] {
        var containers: [any UIFocusItemContainer] = [window]
        var visited = Set<ObjectIdentifier>()
        var items: [ObjectIdentifier: any UIFocusItem] = [:]
        while let container = containers.popLast() {
            guard visited.insert(ObjectIdentifier(container)).inserted else { continue }
            for item in container.focusItems(in: container.coordinateSpace.convert(window.bounds, from: window)) {
                if let child = item.focusItemContainer { containers.append(child) }
                if let view = item as? UIView { containers.append(view) }
                if item.canBecomeFocused, !(item is UIScrollView) { items[ObjectIdentifier(item)] = item }
            }
        }
        return Array(items.values)
    }

    private struct ReorderFixture: View {
        let model: NavigationStyleSettingsModel
        let keys: [String]

        var body: some View {
            LiftableReorderList(
                sections: model.librarySections(available: keys),
                disabledSectionTitle: "Hidden", disabledPlaceholder: "None",
                isLifting: .constant(false), allowsHiding: false,
                onMove: { model.recordNavigationMove(of: $0) },
                initialElement: NavigationLibraryLayout.settingsKey,
                row: { .init(title: Text(verbatim: $0)) },
                onChange: { model.applyLibrarySections($0, available: keys) }
            )
        }
    }

    @Observable
    final class Model {
        var selection = NavigationRailDestination.home
        var destinations: [NavigationRailDestination] =
            [.home, .watchlist, .liveTV, .search] + (1...20).map { .library("plex:\($0)") }
        @ObservationIgnored var buttons: [NavigationRailDestination: UIButton] = [:]
        @ObservationIgnored var contentBuilds = 0
    }

    private struct Fixture: View {
        @Bindable var model: Model

        var body: some View {
            SettingsNavigationShell(style: .tabBar, showsSettings: model.selection == .settings) { _ in
                TopBarNavigation(
                    destinations: model.destinations, selection: $model.selection,
                    preventsAccidentalExit: true,
                    content: { destination, active in
                        model.contentBuilds += 1
                        return AnyView(Probe(destination: destination, active: active, model: model)
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
