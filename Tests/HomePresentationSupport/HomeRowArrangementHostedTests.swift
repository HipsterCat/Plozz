import CoreImage
import CoreModels
import CoreUI
#if os(tvOS)
@testable import FeatureHome
#elseif os(iOS)
@testable import AppShelliOS
#endif
@testable import FeatureSettings
import Observation
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class HomeRowArrangementHostedTests: XCTestCase {
    func testReorderRemovalPreservesOtherSettingsAndRemainsAvailableToAdd() throws {
        let suite = "HomeReorderRemoval.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        let visibility = HomeLibraryVisibilityModel(store: store)
        visibility.useRowDefaults(.combined)
        let catalog = HomeSectionCatalog(libraries: [])
        var session = HomeSectionReorderSession(catalog: catalog, visibility: visibility.visibility)
        let original = catalog.sections(in: session.visibility).enabled
        visibility.setContinueWatchingShowsSeriesArtwork(false)
        try session.remove(.global(.continueWatching), savingTo: visibility)
        XCTAssertEqual(catalog.sections(in: session.visibility).enabled, original.filter { $0 != .global(.continueWatching) })
        XCTAssertTrue(catalog.sections(in: store.load()).disabled.contains(.global(.continueWatching)))
        XCTAssertFalse(store.load().continueWatchingShowsSeriesArtwork)
        XCTAssertThrowsError(try session.remove(.server(accountID: "missing", section: "missing"), savingTo: visibility))
        try visibility.setHomeSectionVisible(true, id: .global(.continueWatching), catalog: catalog)
        XCTAssertEqual(catalog.sections(in: store.load()).enabled.last, .global(.continueWatching))
        XCTAssertFalse(store.load().continueWatchingShowsSeriesArtwork)
    }

    func testReorderSnapshotSavesKnownRowsBeforeOrAfterDiscoveryWithoutLosingPreferences() async throws {
        for completesBeforeMove in [false, true] {
            let suite = "HomeReorderSnapshot.\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = HomeLibraryVisibilityStore(defaults: defaults)
            let visibility = HomeLibraryVisibilityModel(store: store)
            visibility.useRowDefaults(.matchServer)
            let requested = expectation(description: "Native layout discovery remains pending")
            let provider = HomeSettingsLibraryProvider(
                name: "Slow server", kind: .plex,
                homeLayout: .init(
                    sections: [.init(id: "native", kind: .recommendations)], source: .promotedHubs
                ),
                holdsHome: true, onFirstHomeRequest: { requested.fulfill() }
            )
            defer { Task { await provider.resumeHome() } }
            let account = ResolvedAccount(account: Account(from: provider.session), provider: provider)
            let inventory = HomeSectionCatalogModel()
            let load = Task { await inventory.load(libraries: [], accounts: [account], visibility: visibility) }
            await fulfillment(of: [requested], timeout: 5)
            var session = HomeSectionReorderSession(catalog: inventory.catalog, visibility: visibility.visibility)
            let original = session.catalog.sections(in: session.visibility).enabled
            XCTAssertGreaterThan(original.count, 1)
            let saved = store.load()
            try session.move(original, savingTo: visibility)
            XCTAssertEqual(store.load(), saved, "Entering Reorder or making no move must not freeze a preset.")
            if completesBeforeMove {
                await provider.resumeHome()
                await load.value
                XCTAssertEqual(session.catalog.sections(in: session.visibility).enabled, original)
            }
            visibility.setContinueWatchingShowsSeriesArtwork(false)
            let reordered = Array(original.reversed())
            try session.move(reordered, savingTo: visibility)
            XCTAssertEqual(store.load().rowCustomization?.defaults, .custom)
            XCTAssertFalse(store.load().continueWatchingShowsSeriesArtwork,
                           "Saving a reorder must not overwrite unrelated settings changed after entry.")
            if !completesBeforeMove {
                await provider.resumeHome()
                await load.value
            }
            XCTAssertEqual(inventory.catalog.sections(in: visibility.visibility).enabled, reordered)
            XCTAssertEqual(inventory.catalog.sections(in: store.load()).enabled, reordered)
            XCTAssertTrue(inventory.catalog.sections(in: visibility.visibility).disabled.contains(
                .server(accountID: account.account.id, section: "native")
            ), "Late discoveries remain available to add without changing the saved arrangement.")
            XCTAssertFalse(inventory.isLoading)
        }
    }

    #if os(tvOS)
    func testAddSectionIsFocusableBeforeDiscoveryFinishes() async throws {
        let suite = "HomeAddImmediateFocus.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(store: HomeLibraryVisibilityStore(defaults: defaults))
        visibility.useRowDefaults(.combined)
        visibility.setGlobalRowEnabled(false, for: .recentlyAdded)
        let requested = expectation(description: "Discovery remains pending while adding a known section")
        let provider = HomeSettingsLibraryProvider(
            name: "Slow server", holdsHome: true, onFirstHomeRequest: { requested.fulfill() }
        )
        defer { Task { await provider.resumeHome() } }
        let account = ResolvedAccount(account: Account(from: provider.session), provider: provider)
        let inventory = HomeSectionCatalogModel()
        try await withWindow {
            HomeAddSectionView(inventory: inventory, visibility: visibility, libraries: [], accounts: [account])
                .frame(width: SettingsFormMetrics.pageWidth)
        } inspect: { window in
            await self.fulfillment(of: [requested], timeout: 5)
            XCTAssertTrue(inventory.isLoading)
            let lines = try await self.capture(window, name: "Add section during pending discovery")
            let label = try XCTUnwrap(lines.first { $0.0.contains("Recently Added") }).1
            let point = CGPoint(x: label.midX * window.bounds.width, y: (1 - label.midY) * window.bounds.height)
            let item = try XCTUnwrap(self.focusableItem(at: point, in: window),
                                    "Known sections must remain enabled while optional discovery runs.")
            let system = try XCTUnwrap(UIFocusSystem(for: window))
            system.requestFocusUpdate(to: item)
            system.updateFocusIfNeeded()
            let focused = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in system.focusedItem === item }, object: nil
            )
            await self.fulfillment(of: [focused], timeout: 2)
            XCTAssertTrue(inventory.isLoading, "Focus must not depend on the held provider finishing.")
            try visibility.setHomeSectionVisible(true, id: .global(.recentlyAdded), catalog: inventory.currentCatalog(
                libraries: [], accounts: [account], visibility: visibility
            ))
            await provider.resumeHome()
            let finished = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in !inventory.isLoading }, object: nil
            )
            await self.fulfillment(of: [finished], timeout: 5)
            XCTAssertTrue(inventory.catalog.sections(in: visibility.visibility).enabled.contains(.global(.recentlyAdded)))
        }
        await provider.resumeHome()
    }

    func testReorderRemainsFocusableDuringSlowDiscoveryAndFailure() async throws {
        let suite = "HomeReorderDiscovery.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(store: HomeLibraryVisibilityStore(defaults: defaults))
        visibility.useRowDefaults(.combined)
        let requested = expectation(description: "Server discovery remains pending")
        let provider = HomeSettingsLibraryProvider(
            name: "Slow server", homeError: .serverUnreachable, holdsHome: true,
            onFirstHomeRequest: { requested.fulfill() }
        )
        defer { Task { await provider.resumeHome() } }
        let account = ResolvedAccount(account: Account(from: provider.session), provider: provider)
        let inventory = HomeSectionCatalogModel()
        try await withWindow {
            HomeRowsSettingsView(libraries: [], accounts: [account], visibility: visibility, inventory: inventory)
                .frame(width: SettingsFormMetrics.pageWidth)
        } inspect: { window in
            await self.fulfillment(of: [requested], timeout: 5)
            XCTAssertTrue(inventory.isLoading)
            XCTAssertGreaterThan(inventory.catalog.sections(in: visibility.visibility).enabled.count, 1)
            try await self.assertReorderFocusable(in: window, name: "Reorder during pending discovery")
            await provider.resumeHome()
            let finished = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in !inventory.isLoading }, object: nil
            )
            await self.fulfillment(of: [finished], timeout: 5)
            XCTAssertEqual(inventory.serverFailures[account.account.id], .serverUnreachable)
            try await self.assertReorderFocusable(in: window, name: "Reorder after discovery failure")
            let requests = await provider.homeRequests
            XCTAssertEqual(requests, 1, "An idle page must not retry a failed server automatically.")
        }
        await provider.resumeHome()
    }

    private func assertReorderFocusable(in window: UIWindow, name: String) async throws {
        let lines = try await capture(window, name: name)
        let label = try XCTUnwrap(lines.first { $0.0.contains("Reorder") }).1
        let point = CGPoint(x: label.midX * window.bounds.width, y: (1 - label.midY) * window.bounds.height)
        XCTAssertNotNil(focusableItem(at: point, in: window),
                        "Known sections must be reorderable without waiting for server discovery.")
    }

    private func focusableItem(at point: CGPoint, in window: UIWindow) -> (any UIFocusItem)? {
        var containers: [any UIFocusItemContainer] = [window]
        var seen = Set<ObjectIdentifier>()
        while let container = containers.popLast() {
            guard seen.insert(ObjectIdentifier(container)).inserted else { continue }
            let bounds = container.coordinateSpace.convert(window.bounds, from: window)
            for item in container.focusItems(in: bounds) {
                if let child = item.focusItemContainer { containers.append(child) }
                if let view = item as? UIView { containers.append(view) }
                let frame = container.coordinateSpace.convert(item.frame, to: window)
                if !(item is UIScrollView), item.canBecomeFocused, frame.contains(point) { return item }
            }
        }
        return nil
    }
    #endif

    func testPresetSelectionRefreshesRecoveredNativeSectionsBeforeSavingCustomRows() async throws {
        let suite = "HomePresetRecovery.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(store: HomeLibraryVisibilityStore(defaults: defaults))
        visibility.useRowDefaults(.combined)
        let provider = HomeSettingsLibraryProvider(
            name: "Recovered server", homeError: .serverUnreachable, kind: .plex,
            homeLayout: .init(sections: [.init(id: "native", kind: .recommendations)], source: .promotedHubs)
        )
        let account = ResolvedAccount(account: Account(from: provider.session), provider: provider)
        let inventory = HomeSectionCatalogModel()
        await inventory.load(libraries: [], accounts: [account], visibility: visibility)
        XCTAssertEqual(inventory.serverFailures[account.account.id], .serverUnreachable)

        try await withWindow {
            HomeRowsSettingsView(libraries: [], accounts: [account], visibility: visibility, inventory: inventory)
        } inspect: { window in
            _ = try await self.capture(window, name: "Preset before server recovery")
            await provider.setHomeError(nil)
            visibility.useRowDefaults(.matchServer)
            let native = HomeRowID.server(accountID: account.account.id, section: "native")
            let recovered = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    !inventory.isLoading && inventory.serverFailures.isEmpty
                        && inventory.catalog.sections(in: visibility.visibility).enabled == [native]
                }, object: nil
            )
            await self.fulfillment(of: [recovered], timeout: 5)
            try visibility.setHomeSectionVisible(true, id: .libraries, catalog: inventory.catalog)
            XCTAssertEqual(inventory.catalog.sections(in: visibility.visibility).enabled, [native, .libraries])
            _ = try await self.capture(window, name: "Preset after server recovery")
        }
    }

    #if os(iOS)
    func testMobilePresetScrollsWithSectionsWhileToolbarRemainsVisible() async throws {
        let suite = "HomeScrollingPreset.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(store: HomeLibraryVisibilityStore(defaults: defaults))
        let provider = HomeSettingsLibraryProvider(name: "Library server", kind: .mediaShare)
        let account = ResolvedAccount(account: Account(from: provider.session), provider: provider)
        let libraries = (1...18).map {
            AggregatedLibrary(
                accountID: account.account.id, accountName: "Viewer", serverName: "Library server",
                providerKind: .mediaShare,
                library: MediaLibrary(id: "library-\($0)", title: "Library \($0)", kind: .movie)
            )
        }
        let choices = HomeRowChoice.shared + libraries.flatMap(HomeRowChoice.baseRows)
        visibility.applyRows(.init(enabled: choices.map(\.id), disabled: []), choices: choices)
        for (width, size, scheme): (CGFloat, DynamicTypeSize, ColorScheme) in [
            (390, .large, .dark), (390, .large, .light),
            (320, .accessibility5, .dark), (1024, .accessibility3, .dark)
        ] {
            let inventory = HomeSectionCatalogModel()
            try await withWindow(size: CGSize(width: width, height: 900), colorScheme: scheme) {
                NavigationStack {
                    HomeRowsSettingsView(
                        libraries: libraries, accounts: [account], visibility: visibility, inventory: inventory
                    )
                }
                .environment(\.dynamicTypeSize, size)
            } inspect: { window in
                let ready = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in
                        !inventory.isLoading && inventory.catalog.choices.contains {
                            $0.library?.library.id == "library-18"
                        }
                    }, object: nil
                )
                await self.fulfillment(of: [ready], timeout: 5)
                let before = try await self.capture(window, name: "Home preset header \(width) \(size) \(scheme)")
                let text = before.map(\.0).joined(separator: " ")
                for label in ["Preset", "Reorder", "Custom"] {
                    XCTAssertTrue(text.contains(label), text)
                }
                func scrollViews(_ view: UIView) -> [UIScrollView] {
                    (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
                }
                let scroll = try XCTUnwrap(scrollViews(window).first {
                    $0.contentSize.height > $0.bounds.height + 300
                })
                let initialOffset = scroll.contentOffset.y
                scroll.setContentOffset(CGPoint(x: 0, y: initialOffset + 300), animated: false)
                let after = try await self.capture(window, name: "Home scrolled preset \(width) \(size) \(scheme)")
                XCTAssertGreaterThan(scroll.contentOffset.y, initialOffset + 250)
                XCTAssertFalse(after.contains { $0.0.contains("Preset") },
                               "The preset must scroll away rather than remain pinned below the toolbar.")
                XCTAssertEqual(try self.y("Reorder", in: before), try self.y("Reorder", in: after), accuracy: 0.003)
                scroll.setContentOffset(CGPoint(x: 0, y: initialOffset), animated: false)
                let restored = try await self.capture(window, name: "Home preset restored \(width) \(size) \(scheme)")
                XCTAssertEqual(try self.y("Preset", in: before), try self.y("Preset", in: restored), accuracy: 0.003)
            }
        }
    }

    func testPushingAddSectionFinishesDiscoveryAfterTheRootDisappears() async throws {
        let suite = "HomeAddDiscovery.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(store: HomeLibraryVisibilityStore(defaults: defaults))
        visibility.useRowDefaults(.combined)
        let requested = expectation(description: "Root starts a held native-section request")
        let provider = HomeSettingsLibraryProvider(
            name: "Slow server", kind: .plex,
            homeLayout: .init(
                sections: [.init(id: "native", kind: .recommendations, title: "Native picks")], source: .promotedHubs
            ),
            holdsHome: true, onFirstHomeRequest: { requested.fulfill() }
        )
        let account = ResolvedAccount(account: Account(from: provider.session), provider: provider)
        let inventory = HomeSectionCatalogModel()
        let navigation = HomeCatalogNavigationFixture()
        try await withWindow {
            HomeCatalogNavigationHost(navigation: navigation, inventory: inventory, visibility: visibility, accounts: [account])
        } inspect: { window in
            await self.fulfillment(of: [requested], timeout: 5)
            XCTAssertTrue(inventory.isLoading)
            navigation.path = ["add"]
            let pushed = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in navigation.rootDisappeared && navigation.addAppeared }, object: nil
            )
            await self.fulfillment(of: [pushed], timeout: 5)
            await provider.resumeHome()
            let native = HomeRowID.server(accountID: account.account.id, section: "native")
            let discovered = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    !inventory.isLoading && inventory.catalog.sections(in: visibility.visibility).disabled.contains(native)
                }, object: nil
            )
            await self.fulfillment(of: [discovered], timeout: 5)
            let lines = try await self.capture(window, name: "Native section discovered on Add section")
            XCTAssertTrue(lines.contains { $0.0.contains("Native picks") }, lines.map(\.0).joined(separator: " "))
            try visibility.setHomeSectionVisible(true, id: native, catalog: inventory.catalog)
            navigation.path = []
            let returned = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in !navigation.addAppeared }, object: nil
            )
            await self.fulfillment(of: [returned], timeout: 5)
            XCTAssertTrue(inventory.catalog.sections(in: visibility.visibility).enabled.contains(native))
        }
        await provider.resumeHome()
    }
    #endif

    func testMergeNextUpControlIsReadableAndReflectsHiddenContinueWatching() async throws {
        let suite = "HomeNextUpControl.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(
            store: HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        )
        for scheme: ColorScheme in [.light, .dark] {
            for size: DynamicTypeSize in [.large, .accessibility3] {
                visibility.setGlobalRowEnabled(true, for: .continueWatching)
                try await withWindow {
                    ScrollView {
                        ContinueWatchingNextUpControl(visibility: visibility)
                            .padding(32)
                    }
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.themePalette, scheme == .light ? ThemePalette.light : .dark)
                    .environment(\.colorScheme, scheme)
                    .background(scheme == .light ? Color.white : Color.black)
                    #if os(tvOS)
                    .frame(width: 900, height: 650)
                    #endif
                } inspect: { window in
                    let lines = try await self.capture(
                        window, name: "Merge Next Up \(scheme) \(size)", scale: window.traitCollection.displayScale
                    )
                    let text = lines.map(\.0).joined(separator: " ")
                    XCTAssertTrue(text.contains("Merge Next Up rows"), text)
                    XCTAssertTrue(text.contains("next episodes"), text)
                    visibility.setGlobalRowEnabled(false, for: .continueWatching)
                    let disabled = try await self.capture(
                        window, name: "Merge Next Up with hidden Continue Watching", scale: window.traitCollection.displayScale
                    )
                    let disabledText = disabled.map(\.0).joined(separator: " ")
                    XCTAssertTrue(disabledText.contains("Add Continue Watching"), disabledText)
                }
            }
        }
    }

    #if os(iOS)
    func testMobileCustomizeHomeListsSectionsWithoutDetachedArtworkOrMergeControls() async throws {
        let suite = "MobileHomeNextUp.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        let visibility = HomeLibraryVisibilityModel(store: store)
        visibility.useRowDefaults(.combined)
        visibility.setMergeNextUpIntoContinueWatching(true)
        try await withWindow {
            NavigationStack {
                PlozziOSHomeSettingsView(
                    hero: HeroSettingsModel(store: InMemoryHeroSettingsStore()),
                    heroBackground: HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore()),
                    cards: CardStyleSettingsModel(),
                    visibility: visibility, accounts: []
                )
            }
        } inspect: { window in
            let lines = try await self.capture(window, name: "Mobile Home artwork without duplicate merge toggle")
            let text = lines.map(\.0).joined(separator: " ")
            XCTAssertTrue(text.contains("Reorder"), text)
            XCTAssertTrue(text.contains("Hero"), text)
            XCTAssertTrue(text.contains("Continue Watching"), text)
            XCTAssertFalse(text.contains("Artwork"), text)
            XCTAssertFalse(text.contains("Merge Next Up rows"), text)
            XCTAssertFalse(text.contains("No video libraries are available"), text)
            XCTAssertTrue(store.load().mergeNextUpIntoContinueWatching)

            visibility.setGlobalRowEnabled(false, for: .continueWatching)
            let hidden = try await self.capture(window, name: "Mobile Home with Continue Watching hidden")
            let hiddenText = hidden.map(\.0).joined(separator: " ")
            XCTAssertFalse(hiddenText.contains("Artwork"), hiddenText)
            XCTAssertFalse(hiddenText.contains("CONTINUE WATCHING"), "Do not leave an empty section for a hidden row.")
            XCTAssertFalse(hiddenText.contains("Merge Next Up rows"), hiddenText)
            XCTAssertTrue(store.load().mergeNextUpIntoContinueWatching)
        }
    }

    func testMobileSectionMergeSwitchPersistsWithoutChangingPreset() async throws {
        let suite = "MobileHomeRowsNextUp.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        let visibility = HomeLibraryVisibilityModel(store: store)
        visibility.useRowDefaults(.combined)
        try await withWindow {
            NavigationStack {
                HomeSectionSettingsView(
                    choice: HomeRowChoice.shared.first { $0.id == .global(.continueWatching) }!,
                    inventory: HomeSectionCatalogModel(), visibility: visibility, libraries: [], accounts: []
                )
            }
        } inspect: { window in
            _ = try await self.capture(window, name: "Mobile Rows on Home merge setting")
            func switches(_ view: UIView) -> [UISwitch] {
                (view as? UISwitch).map { [$0] } ?? view.subviews.flatMap(switches)
            }
            let control = try XCTUnwrap(switches(window).first)
            XCTAssertTrue(control.isOn)
            control.setOn(false, animated: false)
            control.sendActions(for: .valueChanged)
            let lines = try await self.capture(window, name: "Mobile Rows on Home with Next Up separate")
            XCTAssertFalse(store.load().mergeNextUpIntoContinueWatching)
            XCTAssertEqual(visibility.visibility.rowCustomization?.defaults, .combined)
            let text = lines.map(\.0).joined(separator: " ")
            XCTAssertTrue(text.contains("Continue Watching"), text)
            XCTAssertTrue(text.contains("Merge Next Up rows"), text)
        }
    }

    func testNativeReorderPreviewHasRoundedCorners() async throws {
        try await withWindow {
            LiftableReorderList(
                sections: .init(enabled: ["Alpha", "Beta"], disabled: []),
                disabledSectionTitle: "Hidden", disabledPlaceholder: "No hidden rows",
                isLifting: .constant(false),
                row: { .init(title: Text(verbatim: $0), subtitle: Text("Movies")) },
                onChange: { _ in }
            )
            .padding(24)
        } inspect: { window in
            _ = try await self.capture(window, name: "Native reorder rows")
            var views: [UIView] = [window]
            var collection: UICollectionView?
            while let view = views.popLast() {
                if let list = view as? UICollectionView {
                    collection = list
                    break
                }
                views += view.subviews
            }
            let list = try XCTUnwrap(collection)
            let index = IndexPath(item: 0, section: 0)
            let parameters = try XCTUnwrap(
                list.dragDelegate?.collectionView?(list, dragPreviewParametersForItemAt: index)
            )
            let path = try XCTUnwrap(parameters.visiblePath)
            let bounds = path.bounds
            XCTAssertGreaterThan(bounds.width, 200)
            XCTAssertGreaterThan(bounds.height, 40)
            XCTAssertTrue(path.contains(CGPoint(x: bounds.midX, y: bounds.midY)))
            for x in [bounds.minX + 1, bounds.maxX - 1] {
                for y in [bounds.minY + 1, bounds.maxY - 1] {
                    XCTAssertFalse(path.contains(CGPoint(x: x, y: y)), "Drag previews must cut out each corner.")
                }
            }
        }
    }

    func testOfflineServerDoesNotAddAGlobalWarningToHomeCustomization() async throws {
        let suite = "HomeSettingsOffline.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        let visibility = HomeLibraryVisibilityModel(store: store)
        let offline = HomeSettingsLibraryProvider(name: "Offline server", isOffline: true)
        let online = HomeSettingsLibraryProvider(name: "Available server", isOffline: false)
        visibility.applyRows(
            .init(enabled: [.global(.continueWatching)], disabled: [.global(.watchlist)]),
            choices: HomeRowChoice.shared
        )
        let saved = store.load()
        try await withWindow {
            NavigationStack {
                PlozziOSHomeSettingsView(
                    hero: HeroSettingsModel(store: InMemoryHeroSettingsStore()),
                    heroBackground: HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore()),
                    cards: CardStyleSettingsModel(),
                    visibility: visibility,
                    accounts: [offline, online].map {
                        ResolvedAccount(account: Account(from: $0.session), provider: $0)
                    }
                )
            }
        } inspect: { window in
            let deadline = ContinuousClock.now + .seconds(3)
            while await online.libraryRequests == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let offlineRequests = await offline.libraryRequests
            XCTAssertEqual(offlineRequests, 1)
            let lines = try await self.capture(window, name: "Home customization with an offline server")
            let text = lines.map(\.0).joined(separator: " ")
            XCTAssertTrue(text.contains("Reorder"), text)
            XCTAssertTrue(text.contains("Hero"), text)
            XCTAssertFalse(text.contains("Available server"), "Whole-library controls belong in Settings > Libraries.")
            XCTAssertFalse(text.contains("Movies"), text)
            XCTAssertFalse(text.contains("LIBRARIES"), text)
            XCTAssertFalse(text.contains("Some libraries are"), text)
            XCTAssertFalse(text.contains("Retry"), text)
            XCTAssertEqual(store.load(), saved)
        }
    }

    func testLibraryDiscoveryRefreshesForEffectiveCredentialsAndPlexViewerChanges() async throws {
        let suite = "HomeSettingsViewer.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(
            store: HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        )
        let first = HomeSettingsLibraryProvider(name: "Server", libraryTitle: "Original movies", kind: .plex)
        let rotated = HomeSettingsLibraryProvider(name: "Server", libraryTitle: "Updated movies", kind: .plex)
        let child = HomeSettingsLibraryProvider(name: "Server", libraryTitle: "Child movies", kind: .plex)
        let account = Account(from: first.session)
        let revision = CredentialRevision()
        let updates: [(ResolvedAccount, HomeSettingsLibraryProvider, String)] = [
            (.init(account: account, provider: first, plexHomeUserID: "owner"), first, "Original movies"),
            (.init(account: account, provider: rotated, plexHomeUserID: "owner",
                   credentialRevision: revision), rotated, "Updated movies"),
            (.init(account: account, provider: child, plexHomeUserID: "child",
                   credentialRevision: revision), child, "Child movies")
        ]
        let source = HomeSettingsAccountsFixture(accounts: [updates[0].0])
        try await withWindow {
            HomeSettingsViewerHost(source: source, visibility: visibility)
        } inspect: { window in
            for (resolved, provider, title) in updates {
                source.accounts = [resolved]
                let deadline = ContinuousClock.now + .seconds(3)
                while await provider.libraryRequests == 0, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(20))
                }
                let requests = await provider.libraryRequests
                XCTAssertEqual(requests, 1, title)
                let lines = try await self.capture(window, name: "Home settings \(title)")
                let text = lines.map(\.0).joined(separator: " ")
                XCTAssertTrue(text.contains("Reorder"), text)
                XCTAssertTrue(text.contains("Hero"), text)
                XCTAssertTrue(text.contains(title), "Expected the active viewer's \(title): \(text)")
            }
        }
    }

    func testLateLibraryFailureDoesNotRestoreRemovedLibraryManagementUI() async throws {
        let suite = "HomeSettingsLateFailure.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(
            store: HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        )
        let first = HomeSettingsLibraryProvider(name: "Server", libraryTitle: "Original movies")
        let delayed = HomeSettingsLibraryProvider(name: "Offline", isOffline: true, holdsLibraries: true)
        let current = HomeSettingsLibraryProvider(name: "Server", libraryTitle: "Current movies")
        defer { Task { await delayed.resumeLibraries() } }
        let account = Account(from: first.session)
        let source = HomeSettingsAccountsFixture(accounts: [
            .init(account: account, provider: first),
            .init(account: Account(from: delayed.session), provider: delayed)
        ])
        try await withWindow {
            HomeSettingsViewerHost(source: source, visibility: visibility)
        } inspect: { window in
            let deadline = ContinuousClock.now + .seconds(3)
            while await delayed.libraryRequests == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let delayedRequests = await delayed.libraryRequests
            XCTAssertEqual(delayedRequests, 1)
            source.accounts = [.init(account: account, provider: current)]
            let currentDeadline = ContinuousClock.now + .seconds(3)
            while await current.libraryRequests == 0, ContinuousClock.now < currentDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let currentRequests = await current.libraryRequests
            XCTAssertEqual(currentRequests, 1)
            let before = try await self.capture(window, name: "Current account libraries")
            XCTAssertTrue(before.map(\.0).joined(separator: " ").contains("Reorder"))
            await delayed.resumeLibraries()
            let after = try await self.capture(window, name: "Current libraries after stale failure")
            let text = after.map(\.0).joined(separator: " ")
            XCTAssertTrue(text.contains("Hero"), text)
            XCTAssertTrue(text.contains("Current movies"), text)
            XCTAssertFalse(text.contains("Original movies"), text)
        }
    }
    #endif

    func testMatchServerNamesEachFailedServerWithoutCallingOtherErrorsOffline() async throws {
        let suite = "HomeRowServerFailures.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(
            store: HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        )
        let offline = HomeSettingsLibraryProvider(name: "Basement", homeError: .serverUnreachable)
        let unauthorized = HomeSettingsLibraryProvider(name: "Cinema", homeError: .unauthorized)
        let invalid = HomeSettingsLibraryProvider(name: "Loft", homeError: .invalidResponse)
        let online = HomeSettingsLibraryProvider(name: "Available server")
        let accounts = [offline, unauthorized, invalid, online].map {
            ResolvedAccount(account: Account(from: $0.session), provider: $0)
        }
        await visibility.prepareServerDefaults(accounts: accounts)
        XCTAssertEqual(visibility.serverMatchFailures.count, 3)
        let inventory = HomeSectionCatalogModel()
        await inventory.load(libraries: [], accounts: accounts, visibility: visibility)

        try await withWindow {
            ScrollView {
                HomeCatalogStatus(inventory: inventory, accounts: accounts, libraries: [], retry: {})
                    .padding(24)
            }
            #if os(tvOS)
            .frame(width: 1050)
            #endif
        } inspect: { window in
            let lines = try await self.capture(window, name: "Named Home server failures")
            let text = lines.map(\.0).joined(separator: " ")
            XCTAssertTrue(text.contains("Basement is offline."), text)
            XCTAssertTrue(text.contains("Sign in to Cinema again."), text)
            XCTAssertTrue(text.contains("load sections from Loft."), text)
            XCTAssertFalse(text.contains("Cinema is offline"), text)
            XCTAssertFalse(text.contains("Loft is offline"), text)
            XCTAssertFalse(text.contains("Available server is offline"), text)
            XCTAssertFalse(text.contains("server arrangements"), text)
            XCTAssertFalse(text.contains("Keeping known rows"), text)

            await offline.setHomeError(nil)
            await inventory.load(libraries: [], accounts: accounts, visibility: visibility)
            let recovered = try await self.capture(window, name: "Recovered Home server")
            let recoveredText = recovered.map(\.0).joined(separator: " ")
            XCTAssertFalse(recoveredText.contains("Basement is offline"), recoveredText)
            XCTAssertTrue(recoveredText.contains("Sign in to Cinema again."), recoveredText)
            XCTAssertTrue(recoveredText.contains("load sections from Loft."), recoveredText)
        }
    }

    func testSharedArrangerReflectsCrossLibraryOrderAndPersistsEdits() async throws {
        let suite = "HomeRowArrangement.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        let visibility = HomeLibraryVisibilityModel(store: store)
        let accounts = ["Alpha", "Beta"].map { name in
            let provider = HomeSettingsLibraryProvider(name: name, kind: .mediaShare)
            return ResolvedAccount(account: Account(from: provider.session), provider: provider)
        }
        let libraries = accounts.map {
            AggregatedLibrary(
                accountID: $0.account.id, accountName: "Viewer", serverName: "Server",
                providerKind: .mediaShare,
                library: MediaLibrary(id: $0.account.server.name, title: "\($0.account.server.name) Movies", kind: .movie)
            )
        }

        let choices = libraries.flatMap(HomeRowChoice.baseRows) + HomeRowChoice.shared
        let ids: [HomeRowID] = [
            .global(.continueWatching), .library(libraries[0].key, kind: .recentlyAdded),
            .global(.watchlist), .library(libraries[1].key, kind: .recentlyAdded)
        ]
        let hidden = HomeRowChoice.shared.map(\.id).filter { !ids.contains($0) }
        visibility.applyRows(.init(enabled: ids, disabled: hidden), choices: choices)

        try await withWindow {
            #if os(iOS)
            NavigationStack {
                HomeRowsSettingsView(libraries: libraries, accounts: accounts, visibility: visibility)
            }
            #else
            HomeRowsSettingsView(libraries: libraries, accounts: accounts, visibility: visibility)
            .frame(width: 1050)
            #endif
        } inspect: { window in
            let before = try await self.capture(window, name: "Home arranger original order")
            XCTAssertFalse(before.contains { $0.0.contains("Merge Next Up rows") })
            XCTAssertTrue(before.contains { $0.0.contains("Hero") })
            XCTAssertGreaterThan(try self.y("Alpha", in: before), try self.y("Beta", in: before))
            XCTAssertTrue(before.contains { $0.0.contains("All libraries") })
            visibility.applyRows(.init(enabled: Array(ids.reversed()), disabled: hidden), choices: choices)
            let after = try await self.capture(window, name: "Home arranger reversed order")
            XCTAssertGreaterThan(try self.y("Beta", in: after), try self.y("Alpha", in: after))
            XCTAssertEqual(store.load().rowSections(choices: choices).enabled, Array(ids.reversed()))
        }
    }

    func testRowSubtitlesAndRanksRemainVisibleAtLargeTextSizes() async throws {
        for size in [DynamicTypeSize.large, .accessibility3] {
            try await withWindow {
                ScrollView {
                    LiftableReorderList(
                        sections: .init(enabled: ["Alpha", "Beta"], disabled: []),
                        disabledSectionTitle: "Hidden", disabledPlaceholder: "No hidden rows",
                        isLifting: .constant(false),
                        row: {
                            .init(
                                title: Text(verbatim: $0), providerKind: .jellyfin,
                                subtitle: Text("Movies"), providerMarkInSubtitle: true
                            )
                        }, onChange: { _ in }
                    )
                    .padding(30)
                }
                .environment(\.dynamicTypeSize, size)
                #if os(tvOS)
                .frame(width: 1050)
                #endif
            } inspect: { window in
                let text = try await self.capture(window, name: "Home row text size \(size)")
                XCTAssertGreaterThan(try self.y("Alpha", in: text), try self.y("Beta", in: text))
                XCTAssertEqual(text.filter { $0.0.contains("Movies") }.count, 2)
            }
        }
    }

    func testPresetSelectorReflectsSavedAndCustomLayoutsAtLargeTextSizes() async throws {
        let suite = "HomeRowPresets.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(
            store: HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        )
        for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
            for (preset, title): (HomeRowCustomization.Defaults, String) in [
                (.matchServer, "Match server"), (.combined, "Combined rows"), (.custom, "Custom")
            ] {
                visibility.useRowDefaults(preset)
                #if os(iOS)
                let windowSize: CGSize? = CGSize(width: 320, height: 900)
                #else
                let windowSize: CGSize? = nil
                #endif
                try await withWindow(size: windowSize) {
                    HomeRowPresetPicker(visibility: visibility)
                        .padding(24)
                        .environment(\.dynamicTypeSize, size)
                } inspect: { window in
                    let lines = try await self.capture(window, name: "Home preset \(title) text size \(size)")
                    let text = lines.map(\.0).joined(separator: " ")
                    // Wrapping hyphenates words; OCR can read the chevron as a stray single-letter word.
                    let readable = text.replacingOccurrences(of: "- ", with: "")
                        .filter { $0.isLetter || $0.isWhitespace }
                        .split(whereSeparator: \.isWhitespace).filter { $0.count > 1 }
                        .joined(separator: " ").lowercased()
                    XCTAssertTrue(text.contains("Preset"), text)
                    XCTAssertTrue(readable.contains(title.lowercased()), text)
                    XCTAssertEqual(visibility.visibility.rowCustomization?.defaults, preset)
                }
            }
        }
    }

    func testSourceFailuresAppearOnlyOnTheMainEditor() async throws {
        let suite = "HomeRootFailures.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(store: HomeLibraryVisibilityStore(defaults: defaults))
        visibility.applyRows(
            .init(enabled: [.global(.continueWatching)],
                  disabled: HomeRowChoice.shared.map(\.id).filter { $0 != .global(.continueWatching) }),
            choices: HomeRowChoice.shared
        )
        let provider = HomeSettingsLibraryProvider(name: "Basement", homeError: .serverUnreachable)
        let accounts = [ResolvedAccount(account: Account(from: provider.session), provider: provider)]
        let inventory = HomeSectionCatalogModel()
        let choice = try XCTUnwrap(HomeRowChoice.shared.first { $0.id == .global(.continueWatching) })
        await inventory.load(libraries: [], accounts: accounts, visibility: visibility)
        XCTAssertEqual(inventory.serverFailures.count, 1)
        for page in 0..<3 {
            try await withWindow {
                NavigationStack {
                    if page == 0 {
                        HomeRowsSettingsView(libraries: [], accounts: accounts, visibility: visibility, inventory: inventory)
                    } else if page == 1 {
                        HomeSectionSettingsView(
                            choice: choice, inventory: inventory, visibility: visibility, libraries: [], accounts: accounts
                        )
                    } else {
                        HomeAddSectionView(inventory: inventory, visibility: visibility, libraries: [], accounts: accounts)
                    }
                }
            } inspect: { window in
                let lines = try await self.capture(window, name: "Home source error placement \(page)")
                let text = lines.map(\.0).joined(separator: " ")
                XCTAssertEqual(text.contains("Basement is offline."), page == 0, text)
                XCTAssertEqual(lines.filter { $0.0.contains("Retry") }.count, page == 0 ? 1 : 0, text)
            }
        }
    }

    func testSourceRowsRenderTheSharedProviderAndTransportMarks() async throws {
        let sources: [(ProviderKind, MediaShareTransportKind?)] =
            [ProviderKind.jellyfin, .plex, .emby, .silo, .iptv].map { ($0, nil) }
            + MediaShareTransportKind.allCases.map { (.mediaShare, $0) }
            + [(.plex, nil)]
        let choices = sources.enumerated().map { index, source in
            if index == sources.count - 1 {
                return HomeRowChoice(serverRow: .init(
                    accountID: "server", serverName: "Native server", providerKind: .plex,
                    section: .init(id: "native", kind: .recommendations)
                ))
            }
            let library = AggregatedLibrary(
                accountID: "account", accountName: "Viewer", serverName: "Server",
                providerKind: source.0, transportKind: source.1,
                library: .init(id: "library-\(index)", title: "Movies", kind: .movie)
            )
            return HomeRowChoice(
                id: .library(library.key, kind: .recentlyAdded), title: "Recently Added",
                library: library, isProviderDefault: true
            )
        }
        var screenshots: [CGImage] = []
        for reference in [false, true] {
            try await withWindow(size: CGSize(width: 600, height: 1040)) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(choices.indices, id: \.self) { index in
                        Group {
                            if reference {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        choices[index].homeEditorTitle.font(.body.weight(.medium))
                                        HStack(spacing: 6) {
                                            ProviderBrandMark(
                                                provider: sources[index].0, size: 20, showsBackground: false,
                                                mediaShareTransport: sources[index].1
                                            )
                                            choices[index].homeEditorSource.font(.footnote).settingsRowSecondary()
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.forward").font(.footnote).settingsRowSecondary()
                                }
                                .multilineTextAlignment(.leading)
                                .frame(minHeight: 44)
                            } else {
                                HomeSectionChoiceLabel(choice: choices[index])
                            }
                        }
                        .frame(width: 380, height: 72)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea()
            } inspect: { window in
                let image = try await self.snapshot(window, name: reference ? "Shared mark references" : "Home source marks")
                screenshots.append(try XCTUnwrap(image.cgImage))
            }
        }
        func pixels(_ image: CGImage) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: 32, height: 32, bitsPerComponent: 8,
                    bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            }
            return bytes
        }
        for index in choices.indices {
            let rect = CGRect(x: 24, y: 24 + index * 80, width: 24, height: 72)
            let actual = try XCTUnwrap(screenshots[0].cropping(to: rect))
            let reference = try XCTUnwrap(screenshots[1].cropping(to: rect))
            let actualPixels = try pixels(actual)
            let referencePixels = try pixels(reference)
            XCTAssertTrue(stride(from: 0, to: referencePixels.count, by: 4).contains {
                let channels = referencePixels[$0..<$0 + 3]
                return (channels.max() ?? 0) - (channels.min() ?? 0) > 30
            }, "The shared reference must contain visible artwork.")
            XCTAssertTrue(actualPixels == referencePixels,
                          "Source \(sources[index]) must render the shared mark below the title beside the source.")
        }
    }

    func testReorderProviderMarkCanMoveBesideTheSubtitleWithoutChangingDefaultPlacement() async throws {
        for secondary in [false, true] {
            try await withWindow(size: CGSize(width: 900, height: 300)) {
                LiftableReorderList(
                    sections: .init(enabled: ["row"], disabled: []),
                    disabledSectionTitle: "Hidden", disabledPlaceholder: "No hidden rows",
                    isLifting: .constant(false), allowsHiding: false,
                    row: { _ in
                        .init(
                            title: Text("Recently Added"), symbolName: "rectangle.grid.1x2",
                            providerKind: .jellyfin, subtitle: Text("Movies"),
                            providerMarkInSubtitle: secondary
                        )
                    },
                    onChange: { _ in }
                )
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } inspect: { window in
                let image = try await self.snapshot(window, name: "Reorder secondary provider \(secondary)")
                let cgImage = try XCTUnwrap(image.cgImage)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
                func textFrame(_ text: String) throws -> CGRect {
                    let result = try XCTUnwrap(request.results?.first {
                        $0.topCandidates(1).first?.string.contains(text) == true
                    })
                    let candidate = try XCTUnwrap(result.topCandidates(1).first)
                    let range = try XCTUnwrap(candidate.string.range(of: text))
                    let rect = try XCTUnwrap(candidate.boundingBox(for: range)).boundingBox
                    return CGRect(
                        x: rect.minX * image.size.width, y: (1 - rect.maxY) * image.size.height,
                        width: rect.width * image.size.width, height: rect.height * image.size.height
                    )
                }
                let title = try textFrame("Recently Added")
                let source = try textFrame("Movies")
                let mark = try self.coloredArtworkBounds(in: cgImage)
                if secondary {
                    XCTAssertGreaterThan(mark.minY, title.maxY)
                    XCTAssertEqual(mark.midY, source.midY, accuracy: 5)
                    XCTAssertLessThanOrEqual(mark.maxX, source.minX)
                    XCTAssertGreaterThan(mark.midX, title.minX)
                } else {
                    XCTAssertLessThan(mark.maxX, title.minX,
                                      "Other reorder consumers must keep their leading provider mark.")
                }
            }
        }
    }

    private func coloredArtworkBounds(in image: CGImage) throws -> CGRect {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var bounds = CGRect.null
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let channels = bytes[offset..<(offset + 3)]
                if bytes[offset + 3] > 150,
                   (channels.max() ?? 0) - (channels.min() ?? 0) > 40 {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        XCTAssertFalse(bounds.isNull, "The provider mark must contain visible colored artwork.")
        return bounds
    }

    #if os(tvOS)
    func testAllHiddenNoticeStillProvidesANativeFocusTarget() async throws {
        try await withWindow {
            HomeContentNoticeView(notice: .noHomeRows, onReload: {})
        } inspect: { window in
            let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
            let host = try XCTUnwrap(window.rootViewController)
            let deadline = ContinuousClock.now + .seconds(3)
            while system.focusedItem == nil, ContinuousClock.now < deadline {
                window.layoutIfNeeded()
                system.requestFocusUpdate(to: host)
                system.updateFocusIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertNotNil(system.focusedItem)
            let text = try await self.capture(window, name: "All Home rows hidden")
            XCTAssertTrue(text.contains { $0.0.contains("Reload") })
        }
    }
    #endif

    private func withWindow<Content: View>(
        size: CGSize? = nil,
        colorScheme: ColorScheme = .dark,
        @ViewBuilder content: () -> Content,
        inspect: (UIWindow) async throws -> Void
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = size.map { CGRect(origin: .zero, size: $0) } ?? scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        window.rootViewController = UIHostingController(rootView:
            content()
                .environment(HeroSettingsModel(store: InMemoryHeroSettingsStore()))
                .environment(HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore()))
                .environment(CardStyleSettingsModel())
                .environment(\.themePalette, colorScheme == .dark ? ThemePalette.dark : ThemePalette.light)
                .environment(\.colorScheme, colorScheme)
                .environment(\.locale, Locale(identifier: "en_US"))
                .background(.black)
        )
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await inspect(window)
    }

    private func snapshot(_ window: UIWindow, name: String, scale: CGFloat = 1) async throws -> UIImage {
        try await Task.sleep(for: .milliseconds(400))
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }

    private func capture(_ window: UIWindow, name: String, scale: CGFloat = 1) async throws -> [(String, CGRect)] {
        let image = try await snapshot(window, name: name, scale: scale)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.001
        let original = try XCTUnwrap(image.cgImage)
        var images = [original]
        if scale > 1 {
            let inverted = CIImage(cgImage: original).applyingFilter("CIColorInvert")
            images.append(try XCTUnwrap(CIContext().createCGImage(inverted, from: inverted.extent)))
        }
        return try images.flatMap { image in
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { result in
                result.topCandidates(1).first.map { ($0.string, result.boundingBox) }
            }
        }
    }

    private func y(_ name: String, in lines: [(String, CGRect)]) throws -> CGFloat {
        try XCTUnwrap(lines.first { $0.0.contains(name) }, lines.map(\.0).joined(separator: " | ")).1.midY
    }
}

#if os(iOS)
@MainActor @Observable
private final class HomeCatalogNavigationFixture {
    var path: [String] = []
    var rootDisappeared = false
    var addAppeared = false
}

@MainActor
private struct HomeCatalogNavigationHost: View {
    @Bindable var navigation: HomeCatalogNavigationFixture
    let inventory: HomeSectionCatalogModel
    let visibility: HomeLibraryVisibilityModel
    let accounts: [ResolvedAccount]

    var body: some View {
        NavigationStack(path: $navigation.path) {
            HomeRowsSettingsView(libraries: [], accounts: accounts, visibility: visibility, inventory: inventory)
                .onDisappear { navigation.rootDisappeared = true }
                .navigationDestination(for: String.self) { _ in
                    HomeAddSectionView(inventory: inventory, visibility: visibility, libraries: [], accounts: accounts)
                        .onAppear { navigation.addAppeared = true }
                        .onDisappear { navigation.addAppeared = false }
                }
        }
    }
}

@MainActor @Observable
private final class HomeSettingsAccountsFixture {
    var accounts: [ResolvedAccount]
    init(accounts: [ResolvedAccount]) { self.accounts = accounts }
}

@MainActor
private struct HomeSettingsViewerHost: View {
    let source: HomeSettingsAccountsFixture
    let visibility: HomeLibraryVisibilityModel
    private let hero = HeroSettingsModel(store: InMemoryHeroSettingsStore())
    private let heroBackground = HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore())
    private let cards = CardStyleSettingsModel()

    var body: some View {
        NavigationStack {
            PlozziOSHomeSettingsView(
                hero: hero, heroBackground: heroBackground,
                cards: cards,
                visibility: visibility, accounts: source.accounts
            )
        }
    }
}
#endif

private actor HomeSettingsLibraryProvider: MediaProvider {
    let session: UserSession
    let isOffline: Bool
    let kind: ProviderKind
    private(set) var libraryRequests = 0
    private var homeError: AppError?
    private let libraryTitle: String
    private var holdsLibraries: Bool
    private var libraryContinuation: CheckedContinuation<Void, Never>?
    private let homeLayout: ServerHomeLayout?
    private var holdsHome: Bool
    private var homeContinuations: [CheckedContinuation<Void, Never>] = []
    private let onFirstHomeRequest: (@Sendable () -> Void)?
    private var requestedHome = false
    private(set) var homeRequests = 0

    init(
        name: String, isOffline: Bool = false, homeError: AppError? = nil,
        libraryTitle: String = "Movies", kind: ProviderKind = .jellyfin,
        holdsLibraries: Bool = false, homeLayout: ServerHomeLayout? = nil,
        holdsHome: Bool = false, onFirstHomeRequest: (@Sendable () -> Void)? = nil
    ) {
        self.isOffline = isOffline
        self.homeError = homeError
        self.libraryTitle = libraryTitle
        self.kind = kind
        self.holdsLibraries = holdsLibraries
        self.homeLayout = homeLayout
        self.holdsHome = holdsHome
        self.onFirstHomeRequest = onFirstHomeRequest
        session = UserSession(
            server: MediaServer(
                id: name, name: name,
                baseURL: URL(string: "https://home-settings.example.test")!, provider: kind
            ),
            userID: "viewer", userName: "Viewer", deviceID: "fixture", accessToken: "fixture"
        )
    }

    func setHomeError(_ error: AppError?) { homeError = error }
    func resumeLibraries() {
        holdsLibraries = false
        libraryContinuation?.resume()
        libraryContinuation = nil
    }
    func serverHomeLayout() async throws -> ServerHomeLayout? {
        homeRequests += 1
        if !requestedHome {
            requestedHome = true
            onFirstHomeRequest?()
        }
        if holdsHome { await withCheckedContinuation { homeContinuations.append($0) } }
        if let homeError { throw homeError }
        return homeLayout
    }

    func resumeHome() {
        holdsHome = false
        let pending = homeContinuations
        homeContinuations = []
        for continuation in pending { continuation.resume() }
    }

    func libraries() async throws -> [MediaLibrary] {
        libraryRequests += 1
        if holdsLibraries { await withCheckedContinuation { libraryContinuation = $0 } }
        if isOffline { throw AppError.serverUnreachable }
        return [MediaLibrary(id: "movies", title: libraryTitle, kind: .movie)]
    }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: page.startIndex, totalCount: 0)
    }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    nonisolated func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
