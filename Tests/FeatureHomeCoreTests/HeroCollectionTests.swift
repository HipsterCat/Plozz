import CoreModels
import Foundation
import XCTest
@testable import FeatureHomeCore

final class HeroCollectionTests: XCTestCase {
    private let selection = HeroCollectionSelection(
        accountID: "account", libraryID: "library", collectionID: "collection", title: "Favorites"
    )

    private func item(_ id: String, kind: MediaItemKind = .movie, watched: Bool = false) -> MediaItem {
        MediaItem(
            id: id, title: id, kind: kind, hasBeenPlayed: watched,
            backdropURL: URL(string: "https://example.com/\(id).jpg")
        )
    }

    private var settings: HeroSettings {
        var settings = HeroSettings.default
        settings.sources = [.collection]
        settings.collections = [selection]
        return settings
    }

    func testSelectionIsPartOfConfigurationOnlyWhileSourceIsEnabled() throws {
        var changed = settings
        changed.collections = [.init(accountID: "other", libraryID: "library", collectionID: "collection", title: "Favorites")]
        XCTAssertNotEqual(HeroConfigurationKey(settings: settings), HeroConfigurationKey(settings: changed))
        changed = settings
        changed.collections = [.init(accountID: "account", libraryID: "library", collectionID: "different", title: "Favorites")]
        XCTAssertNotEqual(HeroConfigurationKey(settings: settings), HeroConfigurationKey(settings: changed))
        changed.collections = settings.collections + changed.collections
        XCTAssertNotEqual(HeroConfigurationKey(settings: settings), HeroConfigurationKey(settings: changed))
        changed.sources = [.watchlist]
        var disabled = changed
        disabled.collections = []
        XCTAssertEqual(HeroConfigurationKey(settings: changed), HeroConfigurationKey(settings: disabled))
        let key = HeroConfigurationKey(settings: settings)
        XCTAssertEqual(try JSONDecoder().decode(HeroConfigurationKey.self, from: JSONEncoder().encode(key)), key)
    }

    func testShortPagesContinueInOrderWithAccountOwnership() async throws {
        let provider = CollectionProvider(items: (0..<7).map { item("\($0)") })
        let result = try await HeroCollectionLoader.load(selection: selection, limit: 5, provider: provider, visibility: .default)
        XCTAssertEqual(result.items.map(\.id), ["0", "1", "2", "3", "4"])
        XCTAssertTrue(result.items.allSatisfy { $0.sourceAccountID == "account" })
        XCTAssertEqual(result.totalCount, 7)
        let requests = await provider.requests
        XCTAssertEqual(requests.map(\.startIndex), [0, 2, 4])
        XCTAssertEqual(requests.map(\.limit), [5, 3, 1])
    }

    func testLegacyConfigurationKeyMigratesAndExplicitEmptyWins() throws {
        let legacy = #"{"sources":["collection"],"maxItems":8,"hideWatched":true,"collection":{"accountID":"account","libraryID":"library","collectionID":"collection","title":"Favorites"}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(HeroConfigurationKey.self, from: Data(legacy.utf8)),
            HeroConfigurationKey(settings: settings)
        )
        let cleared = legacy.dropLast() + #","collections":[]}"#
        XCTAssertTrue(try JSONDecoder().decode(HeroConfigurationKey.self, from: Data(cleared.utf8)).collections.isEmpty)
    }

    func testMultipleCollectionsMixAndDeduplicateAcrossLibrariesAndAccounts() async {
        var configured = settings
        configured.collections += [
            .init(accountID: "account", libraryID: "shows", collectionID: "shows", title: "Shows"),
            .init(accountID: "other-account", collectionID: "personal", title: "Personal")
        ]
        let selections = configured.collections
        var film = item("film").taggingSource("account")
        film.providerIDs["Tmdb"] = "123"
        let show = item("show", kind: .series).taggingSource("account")
        let second = item("second-film").taggingSource("account")
        var duplicate = item("different-provider-id").taggingSource("other-account")
        duplicate.title = film.title
        duplicate.providerIDs["tmdb"] = "123"
        let other = item("other-film").taggingSource("other-account")
        let members = [[film, second], [show, film], [duplicate, other]]
        let requests = CollectionRequests()
        let result = await HeroCurator().curateResult(
            settings: configured, continueWatching: [], watchlist: [],
            collectionProvider: { selection, limit in
                await requests.record(selection)
                XCTAssertLessThanOrEqual(limit, HeroFreshnessSnapshot.rawDiscoveryLimit)
                let index = try XCTUnwrap(selections.firstIndex { $0.id == selection.id })
                return .init(items: members[index], startIndex: 0, totalCount: members[index].count)
            }
        )
        XCTAssertEqual(result.items.map(\.id), ["film", "show", "second-film", "other-film"])
        XCTAssertEqual(Set(result.items.compactMap(\.sourceAccountID)), ["account", "other-account"])
        let fetched = await requests.selections
        XCTAssertEqual(fetched, selections)
    }

    func testMultipleCollectionsRespectDisplayLimitAndDoNotTreatFailureAsPartialSuccess() async {
        var configured = settings
        configured.maxItems = 2
        configured.collections.append(.init(accountID: "account", libraryID: "shows", collectionID: "shows", title: "Shows"))
        let first = selection
        let members = [item("one"), item("two"), item("three")]
        let limited = await HeroCurator().curateResult(
            settings: configured, continueWatching: [], watchlist: [],
            collectionProvider: { selected, _ in
                let values = selected.id == first.id ? members : Array(members.reversed())
                return .init(items: values, startIndex: 0, totalCount: values.count)
            }
        )
        XCTAssertEqual(limited.items.map(\.id), ["one", "three"])
        let failed = await HeroCurator().curateResult(
            settings: configured, continueWatching: [], watchlist: [],
            collectionProvider: { selected, _ in
                if selected.id != first.id { throw AppError.serverUnreachable }
                return .init(items: members, startIndex: 0, totalCount: members.count)
            }
        )
        XCTAssertEqual(failed.collectionState, .failed(.serverUnreachable))
        XCTAssertTrue(failed.items.isEmpty)
        let cancelled = await HeroCurator().curateResult(
            settings: configured, continueWatching: [], watchlist: [],
            collectionProvider: { selected, _ in
                if selected.id != first.id { throw CancellationError() }
                return .init(items: members, startIndex: 0, totalCount: members.count)
            }
        )
        XCTAssertEqual(cancelled.collectionState, .idle)
        XCTAssertTrue(cancelled.items.isEmpty)
    }

    func testLaterCollectionsParticipateBeforeTheCombinedCandidateLimit() async throws {
        let members = (0...HeroFreshnessSnapshot.rawDiscoveryLimit).map { item("film-\($0)") }
        var configured = settings
        configured.maxItems = 1
        configured.collections = members.map {
            .init(accountID: "account", libraryID: "library", collectionID: $0.id, title: $0.title)
        }
        var history = HeroExposureHistory()
        for member in members.dropLast() { history.record(member) }
        let result = await HeroCurator().curateResult(
            settings: configured, continueWatching: [], watchlist: [],
            freshness: HeroFreshnessSnapshot(history: history, sessionSeed: 1),
            collectionProvider: { selection, _ in
                let member = try XCTUnwrap(members.first { $0.id == selection.collectionID })
                return .init(items: [member], startIndex: 0, totalCount: 1)
            }
        )
        XCTAssertEqual(result.items.map(\.id), [try XCTUnwrap(members.last).id])
    }

    func testAlternateCollectionArtworkSurvivesMissingOrBrokenFirstCopyAndCandidateCap() async {
        for kind in [MediaItemKind.movie, .series] {
            for missingArtwork in [true, false] {
                var first = item("first", kind: kind)
                first.providerIDs["Tmdb"] = "42"
                if missingArtwork { first.backdropURL = nil }
                var alternate = item("alternate", kind: kind)
                alternate.providerIDs["tmdb"] = "42"
                let usableURL = alternate.backdropURL
                let result = await curateCollections(
                    [[first], [alternate]],
                    validate: { $0.contains { $0 == usableURL } }
                )
                XCTAssertEqual(result.items.map(\.id), ["alternate"])
                XCTAssertEqual(result.items.first?.sourceAccountID, "account-1")
                XCTAssertEqual(result.candidatePool.buckets.first?.items.map(\.id), ["alternate"])
                XCTAssertEqual(result.durableItems.map(\.id), ["alternate"])
            }
        }
    }

    func testWatchedEvidenceFromAnyCollectionCopyHonorsHideWatchedAndLatestMutations() async {
        for kind in [MediaItemKind.movie, .series] {
            var first = item("first", kind: kind)
            first.providerIDs["Tmdb"] = "42"
            var alternate = item("alternate", kind: kind, watched: true)
            alternate.providerIDs["tmdb"] = "42"
            let hidden = await curateCollections([[first], [alternate]])
            XCTAssertTrue(hidden.items.isEmpty, "A cold identity index must not hide fetched watch evidence.")
            let shown = await curateCollections([[first], [alternate]], hideWatched: false)
            XCTAssertEqual(shown.items.map(\.id), ["first"])
            XCTAssertEqual(shown.items.first?.hasBeenPlayed, true)
            let markedUnwatched = await curateCollections(
                [[first], [alternate]],
                mutations: [.init(itemIDs: ["alternate"], scopedItemIDs: ["account-1:alternate"], played: false)]
            )
            XCTAssertEqual(markedUnwatched.items.map(\.id), ["first"])
            XCTAssertEqual(markedUnwatched.items.first?.hasBeenPlayed, false)
        }
    }

    func testAlternateCopiesDoNotConsumeOtherTitlesCandidateSlots() async {
        var first = item("first")
        first.providerIDs["Tmdb"] = "42"
        var alternate = item("alternate")
        alternate.providerIDs["tmdb"] = "42"
        let result = await curateCollections([[first, item("other")], [alternate]], maxItems: 2)
        XCTAssertEqual(result.items.map(\.id), ["first", "other"])
    }

    func testAlternateArtworkGroupingKeepsTransitiveAliasesInOneSlide() async {
        var first = item("first")
        first.providerIDs["Imdb"] = "tt42"
        var bridge = item("bridge")
        bridge.providerIDs = ["Imdb": "tt42", "Tmdb": "42"]
        var alternate = item("alternate")
        alternate.providerIDs["Tmdb"] = "42"
        let result = await curateCollections([[first], [bridge], [alternate]], maxItems: 3)
        XCTAssertEqual(result.items.map(\.id), ["first"])
    }

    func testCollectionAlternateEvidenceSurvivesCachingAndRefreshOnlyMutations() async throws {
        for kind in [MediaItemKind.movie, .series] {
            var first = item("first", kind: kind)
            first.providerIDs["Tmdb"] = "42"
            var alternate = item("alternate", kind: kind)
            alternate.providerIDs["tmdb"] = "42"
            let result = await curateCollections([[first], [alternate]])
            let cached = try JSONDecoder().decode(
                [MediaItem].self, from: JSONEncoder().encode(result.durableItems)
            )
            let curator = HeroCurator()
            let watched = MediaItemMutation(
                itemIDs: ["alternate"], scopedItemIDs: ["account-1:alternate"], played: true
            )
            XCTAssertTrue(curator.reconcile(cached, settings: settings, watchMutations: [watched]).isEmpty)
            let unrelated = MediaItemMutation(
                itemIDs: ["alternate"], scopedItemIDs: ["another-account:alternate"], played: true
            )
            XCTAssertEqual(
                curator.reconcile(cached, settings: settings, watchMutations: [unrelated]).map(\.id), ["first"]
            )

            alternate.hasBeenPlayed = true
            let shown = await curateCollections([[first], [alternate]], hideWatched: false)
            let selected = try XCTUnwrap(shown.items.first)
            XCTAssertEqual(selected.sources.first?.id, "account-0:first")
            XCTAssertEqual(selected.sources.first?.hasBeenPlayed, false)
            XCTAssertEqual(selected.sources.first { $0.id == "account-1:alternate" }?.hasBeenPlayed, true)
            let unwatched = MediaItemMutation(
                itemIDs: ["alternate"], scopedItemIDs: ["account-1:alternate"], played: false
            )
            let restored = curator.reconcile(shown.items, settings: settings, watchMutations: [unwatched])
            XCTAssertEqual(restored.map(\.id), ["first"])
            XCTAssertEqual(restored.first?.hasBeenPlayed, false)
        }
    }

    func testCollectionAlternateAliasesDeduplicateAgainstOtherHeroSources() async {
        var first = item("first")
        first.providerIDs["Imdb"] = "tt42"
        var bridge = item("bridge")
        bridge.providerIDs = ["Imdb": "tt42", "Tmdb": "42"]
        var watchlist = item("watchlist").taggingSource("watchlist-account")
        watchlist.providerIDs["Tmdb"] = "42"
        for sources: [HeroSourceKind] in [[.collection, .watchlist], [.watchlist, .collection]] {
            let result = await curateCollections(
                [[first, item("other")], [bridge]], maxItems: 3,
                sources: sources, watchlist: [watchlist]
            )
            XCTAssertEqual(result.items.count, 2)
            XCTAssertEqual(result.items.first?.id, sources.first == .collection ? "first" : "watchlist")
            XCTAssertEqual(result.items.last?.id, "other")
        }
    }

    func testTransitiveCollectionWatchEvidenceAndKindBoundaries() async {
        var first = item("first")
        first.providerIDs["Imdb"] = "tt42"
        var bridge = item("bridge")
        bridge.providerIDs = ["Imdb": "tt42", "Tmdb": "42"]
        var alternate = item("alternate", watched: true)
        alternate.providerIDs["Tmdb"] = "42"
        let hidden = await curateCollections([[first], [bridge], [alternate]])
        XCTAssertTrue(hidden.items.isEmpty)
        alternate.kind = .series
        let separateKind = await curateCollections([[first], [bridge], [alternate]])
        XCTAssertEqual(separateKind.items.map(\.id), ["first"])
    }

    private func curateCollections(
        _ buckets: [[MediaItem]], maxItems: Int = 1, hideWatched: Bool = true,
        mutations: [MediaItemMutation] = [],
        sources: [HeroSourceKind] = [.collection],
        watchlist: [MediaItem] = [],
        validate: @escaping HeroArtworkValidating = HeroArtworkValidator.presence
    ) async -> HeroCurationResult {
        var configured = settings
        configured.maxItems = maxItems
        configured.hideWatched = hideWatched
        configured.sources = sources
        configured.collections = buckets.indices.map {
            .init(accountID: "account-\($0)", collectionID: "\($0)", title: "Collection \($0)")
        }
        let pages = Dictionary(uniqueKeysWithValues: buckets.enumerated().map { index, items in
            (String(index), items.map { $0.taggingSource("account-\(index)") })
        })
        return await HeroCurator().curateResult(
            settings: configured, continueWatching: [], watchlist: watchlist,
            watchMutations: mutations,
            collectionProvider: { selection, _ in
                let items = try XCTUnwrap(pages[selection.collectionID])
                return .init(items: items, startIndex: 0, totalCount: items.count)
            },
            artworkValidator: validate
        )
    }

    @MainActor
    func testCachedMixedMembershipRequiresEverySelectedViewerToRemainAccessible() {
        let provider = CollectionProvider(items: [])
        let account = ResolvedAccount(account: Account(id: "account", from: provider.session), provider: provider)
        var configured = settings
        configured.collections.append(.init(
            accountID: "account", libraryID: "shows", collectionID: "other",
            title: "Other viewer", serverUserID: "parent"
        ))
        let store = InMemoryHomeContentStore()
        store.saveHeroCandidatePool(
            .init(buckets: [.init(source: .collection, items: [item("private").taggingSource("account")])]),
            for: HeroConfigurationKey(settings: configured)
        )
        let model = HomeViewModel(accounts: [account], layoutStore: InMemoryHomeLayoutStore(), contentStore: store)
        XCTAssertNil(model.cachedHeroItems(for: configured))
    }

    func testLargeCollectionsCanSampleBeyondTheFirstWindow() async throws {
        let provider = CollectionProvider(items: (0..<100).map { item("\($0)") })
        let result = try await HeroCollectionLoader.load(
            selection: selection, limit: 4, provider: provider, visibility: .default, seed: 96
        )
        XCTAssertEqual(result.items.map(\.id), ["96", "97", "98", "99"])
        let requests = await provider.requests
        XCTAssertEqual(requests.map(\.startIndex), [0, 96, 98])
    }

    func testDisabledCollectionLibraryDoesNotFetch() async throws {
        let provider = CollectionProvider(items: [item("movie")])
        var visibility = HomeLibraryVisibility.default
        visibility.disabledKeys = [try XCTUnwrap(selection.libraryKey)]
        let result = try await HeroCollectionLoader.load(selection: selection, limit: 8, provider: provider, visibility: visibility)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.totalCount, 0)
        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testKnownHiddenMemberLibraryIsFilteredWithoutChangingItsOwnership() async throws {
        let provider = CollectionProvider(items: [
            item("hidden").taggingLibrary("hidden"), item("visible").taggingLibrary("visible")
        ])
        var visibility = HomeLibraryVisibility.default
        visibility.disabledKeys = ["account:hidden"]
        let result = try await HeroCollectionLoader.load(selection: selection, limit: 8, provider: provider, visibility: visibility)
        XCTAssertEqual(result.items.map(\.id), ["visible"])
        XCTAssertEqual(result.items.first?.libraryID, "visible")
    }

    func testPersonalCollectionKeepsMixedMembersAndKnownLibraryVisibility() async throws {
        let personal = HeroCollectionSelection(
            accountID: "account", collectionID: "personal", title: "Personal", serverUserID: "viewer"
        )
        let provider = CollectionProvider(items: [
            item("movie").taggingLibrary("movies"), item("series", kind: .series).taggingLibrary("shows"),
            item("hidden").taggingLibrary("hidden")
        ])
        var visibility = HomeLibraryVisibility.default
        visibility.disabledKeys = ["account:hidden"]
        let page = try await HeroCollectionLoader.load(
            selection: personal, limit: 8, provider: provider, visibility: visibility
        )
        XCTAssertEqual(page.items.map(\.id), ["movie", "series"])
        XCTAssertEqual(page.items.compactMap(\.libraryID), ["movies", "shows"])
        XCTAssertTrue(page.items.allSatisfy { $0.sourceAccountID == "account" })
        var changed = settings
        changed.collections = [personal]
        XCTAssertNotEqual(HeroConfigurationKey(settings: settings), HeroConfigurationKey(settings: changed))
    }

    func testRepeatedOrFailedPagesAreNotPartialSuccess() async {
        for provider in [
            CollectionProvider(items: [item("a"), item("b"), item("c")], repeats: true),
            CollectionProvider(items: [item("a"), item("b"), item("c")], failureIndex: 2)
        ] {
            do {
                _ = try await HeroCollectionLoader.load(selection: selection, limit: 8, provider: provider, visibility: .default)
                XCTFail("A broken collection page must fail the load")
            } catch {
                XCTAssertTrue(error is AppError)
            }
        }
    }

    @MainActor
    func testUnavailableAccountCannotRestoreOrLoadSelectedCollection() async throws {
        let store = InMemoryHomeContentStore()
        store.saveHeroCandidatePool(
            .init(buckets: [.init(source: .collection, items: [item("movie").taggingSource("account")])]),
            for: HeroConfigurationKey(settings: settings)
        )
        let model = HomeViewModel(accounts: [], layoutStore: InMemoryHomeLayoutStore(), contentStore: store)
        XCTAssertNil(model.cachedHeroItems(for: settings))
        let page = try await model.heroCollectionContent(selection, limit: 8, hideWatched: false)
        XCTAssertEqual(page.totalCount, 0)
    }

    func testFreshCollectionWindowDoesNotKeepUnverifiedOldMembership() {
        let old = HeroFreshnessCandidatePool(buckets: [.init(source: .collection, items: [item("removed")])])
        let fresh = HeroFreshnessCandidatePool(buckets: [.init(source: .collection, items: [item("new")])])
        XCTAssertEqual(
            fresh.preservingUnseen(from: old, history: .init()).buckets.first?.items.map(\.id), ["new"]
        )
    }

    @MainActor
    func testDifferentServerViewerCannotRestoreOrFetchSelection() async throws {
        let provider = CollectionProvider(items: [item("movie")])
        let account = ResolvedAccount(
            account: Account(id: "account", from: provider.session),
            provider: provider, plexHomeUserID: "child"
        )
        var configured = settings
        configured.collections = [.init(
            accountID: "account", libraryID: "library", collectionID: "collection",
            title: "Favorites", serverUserID: "parent"
        )]
        let selection = try XCTUnwrap(configured.collections.first)
        let store = InMemoryHomeContentStore()
        store.saveHeroCandidatePool(
            .init(buckets: [.init(source: .collection, items: [item("movie").taggingSource("account")])]),
            for: HeroConfigurationKey(settings: configured)
        )
        let model = HomeViewModel(accounts: [account], layoutStore: InMemoryHomeLayoutStore(), contentStore: store)
        XCTAssertNil(model.cachedHeroItems(for: configured))
        let page = try await model.heroCollectionContent(selection, limit: 8, hideWatched: false)
        XCTAssertTrue(page.items.isEmpty)
        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCurationUsesMovieAndShowMembersAndExistingWatchRules() async {
        let members = [item("film"), item("show", kind: .series), item("episode", kind: .episode), item("seen", watched: true)]
        let result = await HeroCurator().curateResult(
            settings: settings, continueWatching: [], watchlist: [], recentlyAdded: [],
            collectionProvider: { _, _ in MediaPage(items: members, startIndex: 0, totalCount: members.count) }
        )
        XCTAssertEqual(result.items.map(\.id), ["film", "show"])
        XCTAssertEqual(result.candidatePool.buckets.first?.source, .collection)
        XCTAssertEqual(result.durableItems.map(\.id), ["film", "show"])
    }

    func testDisabledOrUnselectedSourceDoesNotFetch() async {
        for configured in [HeroSettings.default, {
            var value = settings
            value.collections = []
            return value
        }()] {
            _ = await HeroCurator().curateResult(
                settings: configured, continueWatching: [], watchlist: [], recentlyAdded: [],
                collectionProvider: { _, _ in
                    XCTFail("Only an enabled, selected collection should fetch")
                    throw AppError.invalidResponse
                }
            )
        }
    }

    func testEmptyCollectionIsAuthoritativeButFailureAndCancellationAreNot() async {
        let empty = await HeroCurator().curateResult(
            settings: settings, continueWatching: [], watchlist: [], recentlyAdded: [],
            collectionProvider: { _, _ in .init(items: [], startIndex: 0, totalCount: 0) }
        )
        XCTAssertTrue(isAuthoritative(empty))
        let failed = await HeroCurator().curateResult(
            settings: settings, continueWatching: [], watchlist: [], recentlyAdded: [],
            collectionProvider: { _, _ in throw AppError.serverUnreachable }
        )
        XCTAssertEqual(failed.collectionState, .failed(.serverUnreachable))
        XCTAssertFalse(isAuthoritative(failed))
        let cancelled = await HeroCurator().curateResult(
            settings: settings, continueWatching: [], watchlist: [], recentlyAdded: [],
            collectionProvider: { _, _ in throw CancellationError() }
        )
        XCTAssertEqual(cancelled.collectionState, .idle)
        XCTAssertFalse(isAuthoritative(cancelled))
    }

    private func isAuthoritative(_ result: HeroCurationResult) -> Bool {
        HeroEmptyCuration.isAuthoritative(
            settings: settings, continueWatching: [], watchlist: [], recentlyAdded: [],
            randomLibraries: [], seerConnected: false, collectionState: result.collectionState
        )
    }
}

private actor CollectionRequests {
    private(set) var selections: [HeroCollectionSelection] = []
    func record(_ selection: HeroCollectionSelection) { selections.append(selection) }
}

private actor CollectionProvider: MediaProvider {
    nonisolated let kind: ProviderKind = .jellyfin
    nonisolated let session = UserSession(
        server: MediaServer(id: "server", name: "Server", baseURL: URL(string: "https://example.com")!, provider: .jellyfin),
        userID: "user", userName: "Viewer", deviceID: "device", accessToken: "test-token"
    )
    private let items: [MediaItem]
    private let repeats: Bool
    private var failureIndex: Int?
    private(set) var requests: [PageRequest] = []

    init(items: [MediaItem], repeats: Bool = false, failureIndex: Int? = nil) {
        self.items = items
        self.repeats = repeats
        self.failureIndex = failureIndex
    }

    func collectionMembers(of collectionID: String, page: PageRequest) async throws -> MediaPage {
        try respond(page)
    }

    func collections(in libraryID: String, page: PageRequest) async throws -> MediaPage {
        try respond(page)
    }

    private func respond(_ page: PageRequest) throws -> MediaPage {
        requests.append(page)
        if failureIndex == page.startIndex { throw AppError.serverUnreachable }
        return .init(
            items: Array(items.dropFirst(repeats ? 0 : page.startIndex).prefix(min(2, page.limit))),
            startIndex: page.startIndex, totalCount: items.count
        )
    }

    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { throw AppError.notFound }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage { throw AppError.notFound }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    nonisolated func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
