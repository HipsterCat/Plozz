import CoreModels
import CoreUI
import FeatureHome
import FeatureHomeCore
import MetadataKit
import SwiftUI

struct EpisodeBreadcrumbFixture: View {
    @State private var path: [MediaItem] = []
    @State private var entered = false
    @State private var model = EpisodeBreadcrumbModel()
    private let seriesNavigation = ProcessInfo.processInfo.arguments.contains("--series-navigation")
    private var focusStyle: CardFocusStyle {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--outlined") { return .outlined }
        if arguments.contains("--highlight") { return .highlight }
        return .system
    }

    var body: some View {
        NavigationStack(path: $path) {
            Button("Go to Episode") { path.append(model.provider.episode) }
                .navigationDestination(for: MediaItem.self) { item in
                    ItemDetailView(
                        viewModel: item.kind == .episode ? model.episode : model.show,
                        onPlay: { _ in }, onSelectChild: { path.append($0) },
                        onNavigate: { path.append($0) }
                    )
                    .environment(model.trailer)
                    .environment(model.background)
                    .mediaItemActionHandler(model.actions)
                    .overlay(alignment: .topTrailing) {
                        Text(verbatim: "\(item.id)|\(item.seasonID ?? "-")|\(item.sourceAccountID ?? "-")")
                            .accessibilityIdentifier("breadcrumb-route")
                            .allowsHitTesting(false)
                    }
                }
        }
        .environment(\.themePalette, .dark)
        .environment(\.plozzCardFocusStyle, focusStyle)
        .preferredColorScheme(.dark)
        .task {
            guard !entered else { return }
            entered = true
            if seriesNavigation {
                await model.prepareRelated()
                DetailTransitionNavigation.prepare(for: model.provider.series)
                path.append(model.provider.series)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--from-show") {
                path.append(model.provider.series)
            }
            path.append(model.provider.episode)
        }
    }
}

@MainActor
private final class EpisodeBreadcrumbModel {
    let provider: EpisodeBreadcrumbProvider
    let episode: ItemDetailViewModel
    let show: ItemDetailViewModel
    let relatedStore = RelatedTitlesStore(directory: nil)
    let actions = EpisodeBreadcrumbActions()
    let trailer = HeroTrailerController()
    let background = HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore(
        HeroBackgroundSettings(homeTrailerEnabled: false, detailMode: .off)
    ))

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        provider = EpisodeBreadcrumbProvider(
            isUpcoming: arguments.contains("--upcoming"),
            hasBrowser: arguments.contains("--series-navigation"),
            relatedCount: arguments.contains("--related-empty") ? 0 : (arguments.contains("--related-single") ? 1 : 3)
        )
        episode = Self.detail(provider.episode, provider: provider)
        let related = provider.related
        let loader = RelatedTitlesLoader(
            resolver: RelatedTitlesResolver(providers: []), store: relatedStore,
            search: { _, _ in related }
        )
        show = Self.detail(provider.series, provider: provider, relatedTitlesLoader: loader)
    }

    func prepareRelated() async {
        await relatedStore.store(RelatedTitlesRecord(
            seedKey: MetadataQuery(provider.series).seriesScoped.enrichmentCacheKey,
            titles: provider.related.map {
                RelatedTitle(title: $0.title, year: nil, kind: .series,
                             providerIDs: $0.providerIDs, source: .tmdb)
            },
            refreshedAt: Date()
        ))
    }

    private static func detail(
        _ item: MediaItem, provider: EpisodeBreadcrumbProvider,
        relatedTitlesLoader: RelatedTitlesLoader? = nil
    ) -> ItemDetailViewModel {
        ItemDetailViewModel(
            provider: provider, itemID: item.id, initialItem: item,
            sourceAccountID: "breadcrumb-account",
            onlineTrailerResolver: { _ in [] }, playableVideoIDResolver: { _ in nil },
            trailerCache: TrailerResolutionCache(), relatedTitlesLoader: relatedTitlesLoader
        )
    }
}

@MainActor
private final class EpisodeBreadcrumbActions: MediaItemActionHandling {
    func actions(for item: MediaItem, context: MediaItemActionContext) -> [MediaItemAction] {
        MediaItemActionCatalog.actions(for: item, supportsWatchState: false, context: context)
    }
    func perform(_ action: MediaItemAction, on item: MediaItem, context: MediaItemActionContext) {}
}

private struct EpisodeBreadcrumbProvider: MediaProvider {
    let isUpcoming: Bool
    let hasBrowser: Bool
    let relatedCount: Int

    var kind: ProviderKind { .jellyfin }
    var session: UserSession {
        UserSession(
            server: MediaServer(id: "breadcrumb-account", name: "Fixture",
                               baseURL: URL(string: "https://fixture.invalid")!, provider: kind),
            userID: "fixture", userName: "Fixture", deviceID: "fixture", accessToken: ""
        )
    }
    var series: MediaItem {
        var item = MediaItem(id: "show", title: "Fixture Show", kind: .series, overview: "Series plot",
                             sourceAccountID: "breadcrumb-account")
        if hasBrowser {
            item.people = (1...12).map {
                MediaPerson(id: "actor-\($0)", name: "Fixture Actor \($0)", role: "Character \($0)")
            }
        }
        return item
    }
    var episode: MediaItem {
        var item = MediaItem(
            id: "episode", title: "Fixture Episode", kind: .episode,
            overview: "Episode plot", parentTitle: "Fixture Show",
            seasonNumber: 2, episodeNumber: 3, seriesID: "show", seasonID: "season-2",
            runtime: 1800, allowsTitleBasedMetadataMatching: false, sourceAccountID: "breadcrumb-account"
        )
        if isUpcoming { item.scheduledAirDate = .distantFuture }
        return item
    }
    var related: [MediaItem] {
        guard hasBrowser else { return [] }
        return (0..<relatedCount).map {
            MediaItem(id: "related-\($0)", title: "Related Show \($0)", kind: .series,
                      providerIDs: ["Tmdb": "\(100 + $0)"], allowsTitleBasedMetadataMatching: false)
        }
    }
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { id == "show" ? series : episode }
    func children(of itemID: String) async throws -> [MediaItem] {
        guard hasBrowser else { return [] }
        if itemID == "show" {
            return [MediaItem(id: "season-2", title: "Season 2", kind: .season,
                              seasonNumber: 2, seriesID: "show")]
        }
        return (1...12).map { index in
            var item = episode
            item.id = "episode-\(index)"
            item.episodeNumber = index
            item.title = "Fixture Episode \(index)"
            return item
        }
    }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: 0, totalCount: 0)
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
