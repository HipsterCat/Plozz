import XCTest
import CoreModels
@testable import FeatureHomeCore

/// Global history is account-wide; discovery remains scoped to enabled libraries.
@MainActor
final class HomeAggregatorVisibilityTests: XCTestCase {

    func testNoHiddenLibraryUsesUnscopedFetch() async {
        let stub = ScopeRecordingStub(
            libraries: [library("L1", "Movies"), library("L2", "Shows")],
            continueWatching: [item("cw1")],
            latest: [item("l1")]
        )
        let accounts = [resolved("acct", provider: stub)]

        _ = await HomeAggregator().content(from: accounts, visibility: .default)

        XCTAssertTrue(stub.unscopedContinueWatchingCalled,
                      "With nothing hidden the aggregator must use the fast unscoped fetch")
        XCTAssertNil(stub.scopedContinueWatchingLibraries,
                     "No scoped fetch should happen when nothing is hidden")
    }

    func testHiddenLibraryDoesNotScopeGlobalHistory() async {
        let stub = ScopeRecordingStub(
            libraries: [library("L1", "Movies"), library("L2", "Shows")],
            continueWatching: [item("cw1")],
            latest: [item("l1")]
        )
        let accounts = [resolved("acct", provider: stub)]
        let visibility = HomeLibraryVisibility(disabledKeys: ["acct:L2"])

        let content = await HomeAggregator().content(from: accounts, visibility: visibility)

        XCTAssertTrue(stub.unscopedContinueWatchingCalled)
        XCTAssertNil(stub.scopedContinueWatchingLibraries,
                     "Catalog visibility must not scope global history")
        XCTAssertEqual(content.continueWatching.map(\.id), ["cw1"])
        XCTAssertEqual(stub.scopedLatestLibraries, ["L1"])
    }

    func testHidingOneAccountDoesNotScopeAnother() async {
        let hidden = ScopeRecordingStub(libraries: [library("L1", "A"), library("L2", "B")])
        let untouched = ScopeRecordingStub(libraries: [library("L1", "C")])
        let accounts = [
            resolved("acct-hidden", provider: hidden),
            resolved("acct-other", provider: untouched)
        ]
        let visibility = HomeLibraryVisibility(disabledKeys: ["acct-hidden:L2"])

        _ = await HomeAggregator().content(from: accounts, visibility: visibility)

        XCTAssertTrue(hidden.unscopedContinueWatchingCalled)
        XCTAssertNil(hidden.scopedContinueWatchingLibraries)
        XCTAssertEqual(hidden.scopedLatestLibraries, ["L1"])
        XCTAssertTrue(untouched.unscopedContinueWatchingCalled,
                      "An account with nothing hidden keeps the unscoped fetch")
        XCTAssertNil(untouched.scopedContinueWatchingLibraries)
    }

    func testGlobalHistorySurvivesAllCatalogsBeingHiddenInEveryLayout() async {
        for kind in [ProviderKind.jellyfin, .emby, .plex] {
            for individualRows in [false, true] {
                let stub = ScopeRecordingStub(
                    kind: kind, libraries: [library("catalog", "Catalog")],
                    continueWatching: [item("resume")]
                )
                let accounts = [resolved("acct", provider: stub)]
                let visibility = HomeLibraryVisibility(disabledKeys: ["acct:catalog"])
                let history: [MediaItem]
                if individualRows {
                    history = await HomeAggregator().unmergedContent(
                        from: accounts, visibility: visibility
                    ).continueWatching
                } else {
                    history = await HomeAggregator().content(
                        from: accounts, visibility: visibility
                    ).continueWatching
                }
                XCTAssertEqual(history.map(\.id), ["resume"])
                XCTAssertEqual(history.first?.sourceAccountID, "acct")
                XCTAssertTrue(stub.unscopedContinueWatchingCalled)
                XCTAssertNil(stub.scopedContinueWatchingLibraries)
                XCTAssertEqual(stub.scopedLatestLibraries, [])
            }
        }
    }

    func testLibraryFailureDoesNotReplaceSuccessfulHistoryWithAnError() async {
        let stub = ScopeRecordingStub(
            continueWatching: [item("resume")], libraryError: .rateLimited(retryAfter: 30)
        )
        let model = HomeViewModel(
            accounts: [resolved("acct", provider: stub)],
            layoutStore: InMemoryHomeLayoutStore(),
            contentStore: InMemoryHomeContentStore(),
            currentVisibility: { .init(disabledKeys: ["acct:catalog"]) }
        )
        await model.load()
        XCTAssertEqual(model.state.value?.continueWatching.map(\.id), ["resume"])
        XCTAssertNil(model.rowFailures[.continueWatching])
        XCTAssertEqual(model.rowFailures[.libraries], .rateLimited(retryAfter: 30))
        XCTAssertEqual(model.rowFailures[.recentlyAdded], .rateLimited(retryAfter: 30))
    }

    // MARK: - Helpers

    private func item(_ id: String) -> MediaItem { MediaItem(id: id, title: id, kind: .movie) }
    private func library(_ id: String, _ title: String) -> MediaLibrary {
        MediaLibrary(id: id, title: title, kind: .movie)
    }

    private func resolved(_ id: String, provider: any MediaProvider) -> ResolvedAccount {
        let server = MediaServer(id: "srv-\(id)", name: "S", baseURL: URL(string: "http://host")!, provider: provider.kind)
        let account = Account(id: id, server: server, userID: "u-\(id)", userName: "U", deviceID: "d-\(id)")
        return ResolvedAccount(account: account, provider: provider)
    }
}

/// `MediaProvider` stub that records whether the unscoped or the library-scoped
/// row methods were called (and with which library ids).
private final class ScopeRecordingStub: MediaProvider, @unchecked Sendable {
    let kind: ProviderKind
    let session: UserSession
    private let stubbedLibraries: [MediaLibrary]
    private let stubbedContinueWatching: [MediaItem]
    private let stubbedLatest: [MediaItem]
    private let libraryError: AppError?

    private(set) var unscopedContinueWatchingCalled = false
    private(set) var scopedContinueWatchingLibraries: [String]?
    private(set) var scopedLatestLibraries: [String]?

    init(
        kind: ProviderKind = .jellyfin,
        libraries: [MediaLibrary] = [],
        continueWatching: [MediaItem] = [],
        latest: [MediaItem] = [],
        libraryError: AppError? = nil
    ) {
        self.kind = kind
        self.libraryError = libraryError
        self.stubbedLibraries = libraries
        self.stubbedContinueWatching = continueWatching
        self.stubbedLatest = latest
        self.session = UserSession(
            server: MediaServer(id: "s", name: "Home", baseURL: URL(string: "http://host")!, provider: kind),
            userID: "u", userName: "User", deviceID: "d", accessToken: "TOKEN"
        )
    }

    func libraries() async throws -> [MediaLibrary] {
        if let libraryError { throw libraryError }
        return stubbedLibraries
    }

    func continueWatching(limit: Int) async throws -> [MediaItem] {
        unscopedContinueWatchingCalled = true
        return stubbedContinueWatching
    }

    func latest(limit: Int) async throws -> [MediaItem] { stubbedLatest }

    func continueWatching(limit: Int, inLibraries libraryIDs: [String]?) async throws -> [MediaItem] {
        guard let libraryIDs else { return try await continueWatching(limit: limit) }
        scopedContinueWatchingLibraries = libraryIDs
        return []
    }

    func latest(limit: Int, inLibraries libraryIDs: [String]?) async throws -> [MediaItem] {
        guard let libraryIDs else { return try await latest(limit: limit) }
        scopedLatestLibraries = libraryIDs
        return stubbedLatest
    }

    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: 0, totalCount: 0)
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
