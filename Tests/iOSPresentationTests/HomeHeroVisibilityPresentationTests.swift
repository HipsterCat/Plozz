#if os(iOS)
import CoreModels
import CoreUI
import FeatureHomeCore
@testable import MetadataKit
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import AppShelliOS

@MainActor
final class HomeHeroVisibilityPresentationTests: XCTestCase {
    func testActualHomeRemovesCompletedEmptyHeroWithoutChangingItsSettings() async throws {
        let app = PlozziOSAppModel()
        let original = app.profiles.activeProfileID
        let profile = app.profiles.add(name: "Empty Hero fixture", isAwaitingSetup: false)
        app.selectProfile(profile.id)
        defer {
            app.selectProfile(original)
            app.profiles.remove(profile.id)
        }
        let provider = EmptyHeroHomeProvider()
        let model = HomeViewModel(
            accounts: [ResolvedAccount(account: provider.account, provider: provider)],
            layoutStore: InMemoryHomeLayoutStore(),
            currentVisibility: { app.settings.homeVisibility.visibility }
        )
        await model.load()
        XCTAssertNotNil(model.state.value)
        app.settings.hero.settings.sources = [.collection]
        app.settings.hero.settings.collections = []
        app.settings.hero.settings.isEnabled = false
        for sizeClass in [UserInterfaceSizeClass.compact, .regular] {
            let home = NavigationStack {
                PlozziOSHomeView(appModel: app, viewModel: model, onAddServer: {}, onShowSettings: {})
            }
            .environment(app)
            .environment(HeroTrailerController())
            try await withWindow(home, sizeClass: sizeClass) { window in
                let scroll = try XCTUnwrap(self.scrollViews(in: window).first)
                let rowsHeight = scroll.contentSize.height
                let rowsInset = scroll.adjustedContentInset.top
                app.settings.hero.settings.isEnabled = true
                try await self.settle(window)
                try await Task.sleep(for: .milliseconds(500))
                window.layoutIfNeeded()
                XCTAssertEqual(scroll.contentSize.height, rowsHeight, accuracy: 1,
                               "An empty curation must remove the Hero and its reserved height.")
                XCTAssertEqual(scroll.adjustedContentInset.top, rowsInset, accuracy: 1)
                XCTAssertTrue(app.settings.hero.settings.isEnabled)
                XCTAssertEqual(app.settings.hero.settings.sources, [.collection])

                app.settings.hero.settings.collections = [
                    HeroCollectionSelection(
                        accountID: "unavailable-account", libraryID: "movies",
                        collectionID: "missing-collection", title: "Unavailable collection"
                    )
                ]
                try await self.settle(window)
                try await Task.sleep(for: .milliseconds(500))
                window.layoutIfNeeded()
                XCTAssertEqual(scroll.contentSize.height, rowsHeight, accuracy: 1,
                               "An unavailable saved collection must also finish without a placeholder.")
                XCTAssertEqual(app.settings.hero.settings.collections.count, 1,
                               "Presentation must not erase saved collection choices.")
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "empty-hero-\(sizeClass)"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                app.settings.hero.settings.isEnabled = false
                app.settings.hero.settings.collections = []
            }
        }
    }

    func testPortraitAndLandscapeFirstPaintIdentitiesCannotReuseEachOthersPinnedArtwork() {
        let identity = "home:movie"
        XCTAssertEqual(PlozziOSHeroArtworkFallback.cacheIdentity(identity, style: .landscape), identity)
        XCTAssertNotEqual(
            PlozziOSHeroArtworkFallback.cacheIdentity(identity, style: .compactPortrait),
            PlozziOSHeroArtworkFallback.cacheIdentity(identity, style: .landscape)
        )
        XCTAssertEqual(PlozziOSHeroArtworkFallback.cacheIdentity(identity, style: .compactPortrait),
                       "\(identity)|portrait-hero-v1")
    }

    func testOnlyCompactHeroesRequestThePortraitSelectionRegardlessOfLogoTiming() async throws {
        let portrait = try XCTUnwrap(URL(string: "https://metadata.example.test/clean-portrait.jpg"))
        let landscape = try XCTUnwrap(URL(string: "https://metadata.example.test/clean-landscape.jpg"))
        let cache = MetadataDiskCache(directory: nil)
        let router = heroArtworkRouter(settings: HeroArtworkProviderSettings(), cache: cache)
        var item = MediaItem(id: "movie", title: "Movie", kind: .movie, providerIDs: ["Tmdb": "42"])
        for (prefersPortrait, artwork) in [(true, portrait), (false, landscape)] {
            await cache.store(artwork, for: ArtworkRouter.providerCacheKey(
                query: MetadataQuery(item), kind: .hero, source: .tmdb, prefersPortraitHero: prefersPortrait
            ))
        }
        for hasLogo in [false, true] {
            item.logoURL = hasLogo ? URL(string: "https://library.example.test/logo.png") : nil
            for surfaceRole in [HeroTrailerSurfaceRole.home, .detail] {
                for style in [HeroArtworkStyle.compactPortrait, .landscape] {
                    let resolved = await PlozziOSHeroArtworkFallback.resolve(
                        for: item, style: style, surfaceRole: surfaceRole, router: router
                    )
                    XCTAssertEqual(resolved, style == .compactPortrait ? portrait : landscape)
                }
            }
        }
    }

    func testExternalHeroFallbackPlacementsMatchTheLibraryArtworkLadder() throws {
        let poster = try XCTUnwrap(URL(string: "https://library.example.test/poster.jpg"))
        let backdrop = try XCTUnwrap(URL(string: "https://library.example.test/backdrop.jpg"))
        let logo = try XCTUnwrap(URL(string: "https://library.example.test/logo.png"))
        for surfaceRole in [HeroTrailerSurfaceRole.home, .detail] {
            for style in [HeroArtworkStyle.compactPortrait, .landscape] {
                for hasLogo in [false, true] {
                    let item = MediaItem(
                        id: "hero-ladder", title: "Movie", kind: .movie,
                        posterURL: poster, backdropURL: backdrop, logoURL: hasLogo ? logo : nil
                    )
                    let presentation = HeroPresentation(
                        item: item, artworkStyle: style, surface: surfaceRole == .home ? .home : .detail
                    )
                    let placements = PlozziOSHeroArtworkFallback.placements(
                        surfaceRole: surfaceRole
                    )
                    let backdropPlacement: ArtworkPlacement = surfaceRole == .home ? .homeHero : .detailBackdrop
                    XCTAssertEqual(
                        placements, [backdropPlacement, .poster]
                    )
                    XCTAssertEqual(
                        presentation.artworkReferences,
                        placements.flatMap { item.artworkReferences(for: $0) }
                    )
                    XCTAssertFalse(placements.contains(.episodeThumbnail))
                }
            }
        }
    }

    func testExternalPosterOnlyHeroesRemainAvailableUntilTheirProviderIsDisabled() async throws {
        let poster = try XCTUnwrap(URL(string: "https://metadata.example.test/poster-only.jpg"))
        let settings = HeroArtworkProviderSettings()
        let router = heroArtworkRouter(settings: settings)
        for surfaceRole in [HeroTrailerSurfaceRole.home, .detail] {
            for style in [HeroArtworkStyle.compactPortrait, .landscape] {
                var item = MediaItem(
                    id: "poster-only", title: "Poster Only", kind: .movie, posterURL: poster
                )
                item.metadataProvenance[.posterURL] = MetadataAttribution(source: .tmdb)
                let presentation = HeroPresentation(
                    item: item, artworkStyle: style, surface: surfaceRole == .home ? .home : .detail
                )
                XCTAssertTrue(presentation.artworkReferences.isEmpty, "External art must not bypass the router.")
                settings.save(.init(orderMode: .custom, enabledOrder: ["tmdb"]))
                let resolved = await PlozziOSHeroArtworkFallback.resolve(
                    for: item, style: style, surfaceRole: surfaceRole, router: router
                )
                XCTAssertEqual(resolved, poster)
                settings.save(.init(orderMode: .custom, disabledOrder: ["tmdb"]))
                let disabled = await PlozziOSHeroArtworkFallback.resolve(
                    for: item, style: style, surfaceRole: surfaceRole, router: router
                )
                XCTAssertNil(disabled, "Do not restore disabled-provider posters through a raw URL fallback.")
            }
        }
    }

    func testExternalHeroFallbackIsIndependentOfWhetherTheLogoHasResolved() async throws {
        let poster = try XCTUnwrap(URL(string: "https://metadata.example.test/poster.jpg"))
        let backdrop = try XCTUnwrap(URL(string: "https://metadata.example.test/backdrop.jpg"))
        let logo = try XCTUnwrap(URL(string: "https://library.example.test/logo.png"))
        let router = heroArtworkRouter(settings: HeroArtworkProviderSettings())
        for surfaceRole in [HeroTrailerSurfaceRole.home, .detail] {
            for style in [HeroArtworkStyle.compactPortrait, .landscape] {
                for hasLogo in [false, true] {
                    var item = MediaItem(
                        id: "both-placements", title: "Movie", kind: .movie,
                        posterURL: poster, backdropURL: backdrop, logoURL: hasLogo ? logo : nil
                    )
                    item.metadataProvenance[.posterURL] = MetadataAttribution(source: .tmdb)
                    item.metadataProvenance[.backdropURL] = MetadataAttribution(source: .tmdb)
                    let presentation = HeroPresentation(
                        item: item, artworkStyle: style, surface: surfaceRole == .home ? .home : .detail
                    )
                    XCTAssertTrue(presentation.artworkReferences.isEmpty)
                    let resolved = await PlozziOSHeroArtworkFallback.resolve(
                        for: item, style: style, surfaceRole: surfaceRole, router: router
                    )
                    XCTAssertEqual(resolved, backdrop)
                }
            }
        }
    }

    func testExternalHeroPosterFallbackDoesNotUseAnEpisodesCachedStill() async throws {
        let still = try XCTUnwrap(URL(string: "https://metadata.example.test/episode-still.jpg"))
        var item = MediaItem(id: "episode", title: "Episode", kind: .episode, posterURL: still)
        item.parentTitle = "Show"
        item.seriesID = "show"
        item.metadataProvenance[.posterURL] = MetadataAttribution(source: .tmdb)
        let router = heroArtworkRouter(settings: HeroArtworkProviderSettings())
        for surfaceRole in [HeroTrailerSurfaceRole.home, .detail] {
            for style in [HeroArtworkStyle.compactPortrait, .landscape] {
                let resolved = await PlozziOSHeroArtworkFallback.resolve(
                    for: item, style: style, surfaceRole: surfaceRole, router: router
                )
                XCTAssertNil(resolved, "A show-level hero fallback must never reinterpret an episode still as a poster.")
            }
        }
    }

    private func heroArtworkRouter(
        settings: HeroArtworkProviderSettings, cache: MetadataDiskCache = MetadataDiskCache(directory: nil)
    ) -> ArtworkRouter {
        ArtworkRouter(
            config: .init(tmdb: .disabled),
            cache: cache,
            enrichmentBaseline: .init(order: [.tmdb], priority: .init(rules: [])),
            settingsStore: settings
        )
    }

    func testHeroSettingRemovesPlaceholderAndContentWithoutLeavingSpace() async throws {
        for sizeClass in [UserInterfaceSizeClass.compact, .regular] {
            for showsContent in [false, true] {
                let model = HeroFixtureModel()
                let style: HeroArtworkStyle = sizeClass == .compact ? .compactPortrait : .landscape
                let fixture = HeroFixture(model: model, style: style, showsContent: showsContent)
                try await withWindow(fixture, sizeClass: sizeClass) { window in
                    try self.assertHeroVisible(in: window)

                    model.settings.isEnabled = false
                    try await self.settle(window)
                    try self.assertRowsOnly(in: window)

                    model.settings.isEnabled = true
                    model.settings.sources = []
                    try await self.settle(window)
                    try self.assertRowsOnly(in: window)

                    model.settings.sources = HeroSettings.default.sources
                    try await self.settle(window)
                    try self.assertHeroVisible(in: window)
                }
            }
        }
    }

    func testEmptyAndPendingHeroSlotsUseTheSamePhoneAndTabletGeometry() async throws {
        for sizeClass in [UserInterfaceSizeClass.compact, .regular] {
            let model = HeroFixtureModel()
            model.settings.sources = [.collection]
            model.settings.collections = []
            let style: HeroArtworkStyle = sizeClass == .compact ? .compactPortrait : .landscape
            try await withWindow(HeroFixture(model: model, style: style, showsContent: false), sizeClass: sizeClass) {
                window in
                try self.assertRowsOnly(in: window)
                model.settings.collections = [
                    .init(accountID: "account", collectionID: "collection", title: "Collection")
                ]
                try await self.settle(window)
                try self.assertHeroVisible(in: window)
                model.recomputeComplete = true
                try await self.settle(window)
                try self.assertRowsOnly(in: window)
                model.hasItems = true
                try await self.settle(window)
                try self.assertHeroVisible(in: window)
            }
        }
    }

    func testColdLoadingScreenOmitsHeroOnFirstPaintAndRespondsToSettings() async throws {
        for sizeClass in [UserInterfaceSizeClass.compact, .regular] {
            let model = HeroFixtureModel()
            model.settings.isEnabled = false
            try await withWindow(LoadingFixture(model: model), sizeClass: sizeClass) { window in
                let scroll = try XCTUnwrap(self.scrollViews(in: window).first)
                let rowsHeight = scroll.contentSize.height
                let rowsTop = scroll.convert(.zero, to: window).y - scroll.contentOffset.y
                XCTAssertGreaterThanOrEqual(rowsTop, window.safeAreaInsets.top + 44 - 1)

                model.settings.isEnabled = true
                try await self.settle(window)
                let heroHeight = PlozziOSHeroMetrics.height(
                    style: sizeClass == .compact ? .compactPortrait : .landscape,
                    surfaceRole: .home, dynamicTypeSize: .large, containerHeight: window.bounds.height
                )
                XCTAssertEqual(scroll.contentSize.height - rowsHeight, heroHeight + 32, accuracy: 1)

                model.settings.sources = []
                try await self.settle(window)
                XCTAssertEqual(scroll.contentSize.height, rowsHeight, accuracy: 1)

                model.settings.sources = [.collection]
                model.settings.collections = []
                try await self.settle(window)
                XCTAssertEqual(scroll.contentSize.height, rowsHeight, accuracy: 1,
                               "Known-empty Collections must not reserve a Hero even on the first Home load.")
            }
        }
    }

    private func assertRowsOnly(in window: UIWindow) throws {
        XCTAssertNil(find("hero", in: window), "A disabled hero must not mount its content or placeholder.")
        let row = try XCTUnwrap(find("first-row", in: window))
        let frame = row.convert(row.bounds, to: window)
        XCTAssertEqual(frame.minY, window.safeAreaInsets.top + 44, accuracy: 1,
                       "The first row must start below navigation, without a hero-sized gap.")
    }

    private func assertHeroVisible(in window: UIWindow) throws {
        let hero = try XCTUnwrap(find("hero", in: window))
        let row = try XCTUnwrap(find("first-row", in: window))
        let heroFrame = hero.convert(hero.bounds, to: window)
        let rowFrame = row.convert(row.bounds, to: window)
        XCTAssertEqual(heroFrame.minY, 0, accuracy: 1, "Enabled heroes remain full bleed.")
        XCTAssertEqual(rowFrame.minY, heroFrame.maxY + 32, accuracy: 1)
    }

    private func find(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.lazy.compactMap { self.find(identifier, in: $0) }.first
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        window.layoutIfNeeded()
    }

    private func withWindow<Content: View>(
        _ content: Content,
        sizeClass: UserInterfaceSizeClass,
        exercise: (UIWindow) async throws -> Void
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let size = sizeClass == .compact
            ? CGSize(width: 390, height: 844)
            : CGSize(width: 1024, height: 768)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: content
            .environment(\.horizontalSizeClass, sizeClass)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.plozziOSHeroContainerHeight, size.height)
            .environment(\.themePalette, ThemePalette.dark))
        host.additionalSafeAreaInsets.top = 44
        host.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await settle(window)
        try await exercise(window)
    }
}

private final class HeroArtworkProviderSettings: MetadataProviderSettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value = MetadataProviderSettings(orderMode: .custom, enabledOrder: ["tmdb"])

    func load() -> MetadataProviderSettings {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func save(_ value: MetadataProviderSettings) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }
}

@MainActor
@Observable
private final class HeroFixtureModel {
    var settings = HeroSettings.default
    var recomputeComplete = false
    var hasItems = false
}

private struct HeroFixture: View {
    let model: HeroFixtureModel
    let style: HeroArtworkStyle
    let showsContent: Bool

    var body: some View {
        let slot = HomeHeroSlotState.resolve(
            settings: model.settings, hasItems: showsContent || model.hasItems,
            recomputeComplete: model.recomputeComplete
        )
        PlozziOSHomeScrollView(heroActive: slot != .hidden) {
            Group {
                if slot == .content {
                    Color.blue.frame(height: 500)
                } else {
                    PlozziOSHomeHeroSkeleton(style: style)
                }
            }
            .background(FrameProbe(identifier: "hero"))
        } rows: {
            Color.red.frame(height: 120)
                .background(FrameProbe(identifier: "first-row"))
            Color.clear.frame(height: 1200)
        }
    }
}

private struct LoadingFixture: View {
    let model: HeroFixtureModel

    var body: some View {
        PlozziOSHomeSkeletonScreen(heroActive: HomeHeroSlotState.resolve(
            settings: model.settings, hasItems: false, recomputeComplete: false
        ) != .hidden)
    }
}

private struct FrameProbe: UIViewRepresentable {
    let identifier: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = identifier
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct EmptyHeroHomeProvider: MediaProvider {
    let kind: ProviderKind = .jellyfin
    let account = Account(
        id: "empty-hero-account",
        server: MediaServer(
            id: "empty-hero-server", name: "Fixture",
            baseURL: URL(string: "https://fixture.invalid")!, provider: .jellyfin
        ),
        userID: "viewer", userName: "Viewer", deviceID: "fixture"
    )
    var session: UserSession { account.session(token: "fixture") }

    func libraries() async throws -> [MediaLibrary] {
        [MediaLibrary(id: "movies", title: "Movies", kind: .movie)]
    }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] {
        [MediaItem(id: "movie", title: "Available movie", kind: .movie)]
    }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: 0, totalCount: 0)
    }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
#endif
