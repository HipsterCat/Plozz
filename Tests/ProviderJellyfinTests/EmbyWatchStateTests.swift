import CoreModels
import CoreNetworking
import Foundation
import XCTest
@testable import ProviderJellyfin

final class EmbyWatchStateTests: XCTestCase {
    func testMarkWatchedSurvivesResumeClearAndProviderReload() async throws {
        let http = EmbyWatchStateHTTP()
        let provider = makeProvider(http: http)
        let store = InMemoryWatchMutationStore()
        let reconciler = WatchStateReconciler(store: store, applier: EmbyWatchApplier(provider: provider))
        await reconciler.enqueue(completedMutation())
        await reconciler.drain()

        XCTAssertTrue(store.load().pending.isEmpty)
        let reloaded = try await makeProvider(http: http).item(id: "episode")
        XCTAssertTrue(reloaded.isPlayed, "Assert the server state, not the optimistic badge or HTTP 200")
        XCTAssertEqual(reloaded.resumePosition, 0)
        let state = await http.state
        XCTAssertEqual(state.PlayCount, 1)
        XCTAssertTrue(state.IsFavorite)
        let requests = await http.requests
        XCTAssertEqual(requests.filter { $0.path.hasSuffix("/PlayedItems/episode") }.count, 1)
        XCTAssertFalse(requests.contains { $0.path.contains("/Sessions/") || $0.path.contains("/ActiveEncodings") })
    }

    func testPlaybackCompletionReplacesCheckpointWithoutUndoingPlayedState() async throws {
        let http = EmbyWatchStateHTTP()
        let provider = makeProvider(http: http)
        let store = InMemoryWatchMutationStore()
        let reconciler = WatchStateReconciler(store: store, applier: EmbyWatchApplier(provider: provider))
        await reconciler.beginLiveSession(accountID: "server", itemID: "episode")
        var checkpoint = completedMutation()
        checkpoint.capturedAt = checkpoint.capturedAt.addingTimeInterval(-30)
        checkpoint.played = nil
        checkpoint.clearResume = false
        checkpoint.resumePosition = 120
        await reconciler.enqueue(checkpoint)
        await reconciler.drain()
        let beforeStop = await http.requests
        XCTAssertTrue(beforeStop.isEmpty)

        await reconciler.finishLiveSession(
            accountID: "server", itemID: "episode", mutation: completedMutation()
        )
        let reloaded = try await makeProvider(http: http).item(id: "episode")
        XCTAssertTrue(reloaded.isPlayed)
        XCTAssertEqual(reloaded.resumePosition, 0)
        XCTAssertTrue(store.load().pending.isEmpty)
    }

    func testResumeWritesPreserveBothPlayedAndUnplayedState() async throws {
        for played in [true, false] {
            let http = EmbyWatchStateHTTP(played: played)
            let provider = makeProvider(http: http)
            for seconds in [120.0, 0, -5] {
                try await provider.setResumePosition(seconds, itemID: "episode")
                let state = await http.state
                XCTAssertEqual(state.Played, played)
                XCTAssertEqual(state.PlaybackPositionTicks, Int64(max(seconds, 0) * 10_000_000))
                XCTAssertTrue(state.IsFavorite)
                XCTAssertEqual(state.PlayCount, played ? 1 : 0)
            }
        }
    }

    func testEveryResumeWriteReadsCurrentServerPlayedState() async throws {
        let http = EmbyWatchStateHTTP(played: true)
        let provider = makeProvider(http: http)
        try await provider.setResumePosition(120, itemID: "episode")
        let first = await http.state
        XCTAssertTrue(first.Played)

        try await provider.setPlayed(false, itemID: "episode")
        try await provider.setResumePosition(240, itemID: "episode")
        let second = await http.state
        XCTAssertFalse(second.Played)
        let requests = await http.requests
        XCTAssertEqual(requests.filter { $0.method == .get }.count, 2)
    }

    func testFailedStateReadKeepsResumeWriteQueuedWithoutGuessingUnwatched() async throws {
        let http = EmbyWatchStateHTTP(played: true)
        await http.setReadFailure(.serverUnreachable)
        let provider = makeProvider(http: http)
        let store = InMemoryWatchMutationStore()
        let reconciler = WatchStateReconciler(store: store, applier: EmbyWatchApplier(provider: provider))
        var mutation = completedMutation()
        mutation.played = nil
        mutation.clearResume = true
        await reconciler.enqueue(mutation)
        await reconciler.drain()

        XCTAssertEqual(store.load().pending.first?.targets, mutation.targets)
        let failedRequests = await http.requests
        XCTAssertFalse(failedRequests.contains { $0.method == .post })
        let beforeRetry = await http.state
        XCTAssertTrue(beforeRetry.Played)

        await http.setReadFailure(nil)
        let restarted = WatchStateReconciler(store: store, applier: EmbyWatchApplier(provider: provider))
        await restarted.drain()
        XCTAssertTrue(store.load().pending.isEmpty)
        let afterRetry = await http.state
        XCTAssertTrue(afterRetry.Played)
        XCTAssertEqual(afterRetry.PlaybackPositionTicks, 0)
    }

    func testMissingOrMalformedPlayedStateNeverSendsAnUnsafeWrite() async throws {
        for response in [
            #"{"Id":"episode"}"#,
            #"{"Id":"episode","UserData":{}}"#,
            #"{"Id":"episode","UserData":{"Played":null}}"#,
            #"{"Id":"episode","UserData":{"Played":"true"}}"#
        ] {
            let http = StubHTTPClient()
            http.stub(pathSuffix: "/Users/user/Items/episode", json: response)
            http.stub(pathSuffix: "/Users/user/Items/episode/UserData", json: "{}")
            do {
                try await makeProvider(http: http).setResumePosition(0, itemID: "episode")
                XCTFail("Missing watched state must fail instead of defaulting to false")
            } catch {
                XCTAssertEqual(error as? AppError, .decoding)
            }
            XCTAssertFalse(http.sentMethods.contains(.post))
        }
    }

    func testJellyfinRetainsItsPartialUpdateWithoutAnExtraRead() async throws {
        let http = EmbyWatchStateHTTP(played: true, kind: .jellyfin)
        let provider = makeProvider(http: http, kind: .jellyfin)
        try await provider.setResumePosition(0, itemID: "episode")
        let state = await http.state
        XCTAssertTrue(state.Played)
        let requests = await http.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.path, "/UserItems/episode/UserData")
        let body = try XCTUnwrap(requests.first?.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["Played"])
    }

    private func makeProvider(http: any HTTPClient, kind: ProviderKind = .emby) -> JellyfinProvider {
        JellyfinProvider(session: .init(
            server: .init(id: "server", name: "Server", baseURL: URL(string: "https://emby.example.test")!, provider: kind),
            userID: "user", userName: "User", deviceID: "device", accessToken: "fixture"
        ), http: http)
    }

    private func completedMutation() -> WatchMutation {
        WatchMutation(
            capturedAt: Date(), canonicalMediaID: "episode", seasonNumber: 1, episodeNumber: 1,
            played: true, clearResume: true,
            targets: [.init(accountID: "server", itemID: "episode", providerKind: .emby)],
            kind: .episode
        )
    }
}

private struct EmbyWatchApplier: WatchMutationApplying {
    let provider: JellyfinProvider

    func setPlayed(_ played: Bool, on target: WatchMutationTarget) async throws {
        try await provider.setPlayed(played, itemID: target.itemID)
    }

    func setResumePosition(_ seconds: TimeInterval, on target: WatchMutationTarget, capturedAt: Date) async throws {
        try await provider.setResumePosition(seconds, itemID: target.itemID, capturedAt: capturedAt)
    }

    func scrobbleTrakt(_ intent: TraktScrobbleIntent) async throws {}
}

/// Emby 4.10.0.40 returns HTTP 200 but saves Played=false when a UserData
/// position update omits Played. Jellyfin leaves an omitted Played unchanged.
private actor EmbyWatchStateHTTP: HTTPClient {
    struct State: Codable, Sendable {
        var Played: Bool
        var PlaybackPositionTicks: Int64 = 0
        var PlayCount: Int
        var IsFavorite = true
        var LastPlayedDate: String?
    }

    private struct Item: Encodable {
        let Id = "episode"
        let Name = "Episode"
        let `Type` = "Episode"
        let UserData: State
    }

    private struct Update: Decodable {
        let PlaybackPositionTicks: Int64
        let LastPlayedDate: String?
        let Played: Bool?
    }

    private let kind: ProviderKind
    private var readFailure: AppError?
    private(set) var state: State
    private(set) var requests: [Endpoint] = []

    init(played: Bool = false, kind: ProviderKind = .emby) {
        self.kind = kind
        state = State(Played: played, PlayCount: played ? 1 : 0)
    }

    func setReadFailure(_ error: AppError?) { readFailure = error }

    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append(endpoint)
        let body: Data
        switch (endpoint.method, endpoint.path) {
        case (.get, "/Users/user/Items/episode"):
            if let readFailure { throw readFailure }
            body = try JSONEncoder().encode(Item(UserData: state))
        case (.post, "/Users/user/PlayedItems/episode"):
            state.Played = true
            state.PlayCount = max(state.PlayCount, 1)
            state.PlaybackPositionTicks = 0
            body = try JSONEncoder().encode(state)
        case (.delete, "/Users/user/PlayedItems/episode"):
            state.Played = false
            state.PlayCount = 0
            state.PlaybackPositionTicks = 0
            body = try JSONEncoder().encode(state)
        case (.post, "/Users/user/Items/episode/UserData"), (.post, "/UserItems/episode/UserData"):
            let update = try JSONDecoder().decode(Update.self, from: XCTUnwrap(endpoint.body))
            state.Played = update.Played ?? (kind == .emby ? false : state.Played)
            state.PlaybackPositionTicks = update.PlaybackPositionTicks
            state.LastPlayedDate = update.LastPlayedDate
            body = Data()
        default:
            throw AppError.notFound
        }
        return (body, HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
