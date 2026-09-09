import XCTest
import AppRuntime
import CoreModels
import CoreNetworking
import ProviderPlex

private actor PlexCompletionHTTPClient: HTTPClient {
    private(set) var requests: [Endpoint] = []
    private var rejectsDismissal = false

    func rejectDismissal() { rejectsDismissal = true }

    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append(endpoint)
        if rejectsDismissal && endpoint.path == "/actions/removeFromContinueWatching" {
            throw AppError.notFound
        }
        return (
            Data("{}".utf8),
            HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}

final class PlexCompletionVersusDismissalTests: XCTestCase {
    private func reconciler(http: PlexCompletionHTTPClient) -> WatchStateReconciler {
        let provider = PlexProvider(
            session: UserSession(
                server: MediaServer(
                    id: "plex", name: "Test", baseURL: URL(string: "https://plex.example")!, provider: .plex
                ),
                userID: "user", userName: "Test", deviceID: "device", accessToken: "TOKEN"
            ),
            http: http
        )
        let applier = AppShellWatchMutationApplier(
            resolveProvider: { _ in provider },
            applyTrakt: { _ in }, applySimkl: { _ in }, applyAniList: { _ in }, applyMAL: { _ in }
        )
        return WatchStateReconciler(store: InMemoryWatchMutationStore(), applier: applier)
    }

    func testCompletingAnEpisodeScrobblesAndClearsProgressWithoutDismissingTheShow() async throws {
        let http = PlexCompletionHTTPClient()
        let reconciler = reconciler(http: http)
        let episode = MediaItem(id: "42", title: "Episode", kind: .episode, sourceAccountID: "plex")
        let mutation = try XCTUnwrap(WatchMutationFactory.playbackStop(
            item: episode, position: 2_500, watchedPercent: 99,
            primaryAccountID: "plex", crossServerSync: false
        ))
        await reconciler.enqueue(mutation)
        await reconciler.drain()
        let requests = await http.requests
        XCTAssertEqual(requests.map(\.path), ["/:/scrobble", "/:/progress"])
        XCTAssertEqual(requests.last?.queryItems.first { $0.name == "time" }?.value, "0")
    }

    func testMarkingWatchedClearsProgressWithoutDismissingForEveryMediaKind() async throws {
        for kind in [MediaItemKind.movie, .episode, .season, .series] {
            let http = PlexCompletionHTTPClient()
            let reconciler = reconciler(http: http)
            let item = MediaItem(id: "42", title: "Item", kind: kind, sourceAccountID: "plex")
            let mutation = try XCTUnwrap(WatchMutationFactory.playedToggle(
                item: item, played: true, primaryAccountID: "plex", crossServerSync: false
            ))
            await reconciler.enqueue(mutation)
            await reconciler.drain()
            let requests = await http.requests
            XCTAssertEqual(requests.map(\.path), ["/:/scrobble", "/:/progress"], "\(kind)")
        }
    }

    func testWritingZeroPositionIsNotAnExplicitDismissal() async {
        let http = PlexCompletionHTTPClient()
        let reconciler = reconciler(http: http)
        await reconciler.enqueue(WatchMutation(
            capturedAt: Date(), canonicalMediaID: "episode", resumePosition: 0,
            targets: [.init(accountID: "plex", itemID: "42")]
        ))
        await reconciler.drain()
        let requests = await http.requests
        XCTAssertEqual(requests.map(\.path), ["/:/progress"])
    }

    func testExplicitRemovalStillDismissesWithoutMarkingWatchedOrErasingResume() async throws {
        let http = PlexCompletionHTTPClient()
        let reconciler = reconciler(http: http)
        let episode = MediaItem(id: "42", title: "Episode", kind: .episode, sourceAccountID: "plex")
        let mutation = try XCTUnwrap(WatchMutationFactory.removeFromContinueWatching(
            item: episode, primaryAccountID: "plex", crossServerSync: false
        ))
        await reconciler.enqueue(mutation)
        await reconciler.drain()
        let requests = await http.requests
        XCTAssertEqual(requests.map(\.path), ["/actions/removeFromContinueWatching"])
    }

    func testUnsupportedExplicitDismissalFallsBackToClearingProgress() async {
        let http = PlexCompletionHTTPClient()
        await http.rejectDismissal()
        let reconciler = reconciler(http: http)
        await reconciler.enqueue(WatchMutation(
            capturedAt: Date(), canonicalMediaID: "episode", clearResume: true,
            targets: [.init(accountID: "plex", itemID: "42")]
        ))
        await reconciler.drain()
        let requests = await http.requests
        XCTAssertEqual(requests.map(\.path), ["/actions/removeFromContinueWatching", "/:/progress"])
        let pending = await reconciler.pendingCount
        XCTAssertEqual(pending, 0)
    }
}
