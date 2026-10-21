import CoreModels
import CoreNetworking
import XCTest
@testable import ProviderJellyfin

final class AIOStreamsWatchHistoryTests: XCTestCase {
    private let bridgeInfo = #"{"Id":"server","aiostreams":{"features":{"history":1}}}"#
    private let resume = """
    {"Items":[{"Id":"movie","Type":"Movie",
      "UserData":{"PlaybackPositionTicks":1200000000,"LastPlayedDate":"2026-10-20T12:00:00Z"}}],
      "TotalRecordCount":1}
    """
    private let nextUp = """
    {"Items":[{"Id":"next","Type":"Episode","SeriesId":"series",
      "UserData":{"LastPlayedDate":"2026-10-19T12:00:00Z"}}],"TotalRecordCount":1}
    """

    private func provider(
        _ http: StubHTTPClient, kind: ProviderKind = .jellyfin, userID: String = "viewer"
    ) -> JellyfinProvider {
        JellyfinProvider(
            session: UserSession(
                server: MediaServer(
                    id: "server", name: "Home", baseURL: URL(string: "https://media.test/base")!,
                    provider: kind
                ),
                userID: userID, userName: "Viewer", deviceID: "test-device", accessToken: "TEST_TOKEN"
            ),
            http: http
        )
    }

    private func http(info: String? = nil) -> StubHTTPClient {
        let http = StubHTTPClient()
        http.stub(pathSuffix: "/System/Info/Public", json: info ?? bridgeInfo)
        http.stub(pathSuffix: "/Items/Resume", json: resume)
        http.stub(pathSuffix: "/Shows/NextUp", json: nextUp)
        return http
    }

    private func historyQueries(_ http: StubHTTPClient) -> [[URLQueryItem]] {
        zip(http.sentPaths, http.sentQueryItems).compactMap { path, query in
            path.hasSuffix("/Items/Resume") || path.hasSuffix("/Shows/NextUp") ? query : nil
        }
    }

    func testCombinedHistoryIgnoresCatalogRestrictionsWithoutInventingLibraryOwnership() async throws {
        for allowed in [["visible"], []] {
            let http = http()
            let provider = provider(http)
            let items = try await provider.continueWatching(limit: .max, inLibraries: allowed)
            XCTAssertEqual(items.map(\.id), ["movie", "next"])
            XCTAssertEqual(items.first?.resumePosition, 120)
            XCTAssertTrue(items.allSatisfy { $0.libraryID == nil })
            XCTAssertTrue(items.allSatisfy {
                $0.taggingSource("account").isVisibleOnHome(isLibraryVisible: { _ in false })
            }, "Disabling every virtual catalog must not remove account-wide history during Home filtering.")
            XCTAssertEqual(historyQueries(http).count, 2)
            XCTAssertTrue(historyQueries(http).allSatisfy { !$0.contains { $0.name == "ParentId" } })
            XCTAssertTrue(http.sentPaths.contains("/Users/viewer/Items/Resume"))
            XCTAssertEqual(http.queryItems(forPathSuffix: "/Shows/NextUp")?
                .first { $0.name == "UserId" }?.value, "viewer")
            let infoIndex = try XCTUnwrap(http.sentPaths.firstIndex(of: "/System/Info/Public"))
            XCTAssertNil(http.sentHeaders[infoIndex]["Authorization"])
        }
    }

    func testResumeOnlyHomePreservesSeparateNextUpAndCachesOnlyCapability() async throws {
        let http = http()
        let provider = provider(http)
        for allowed in [["visible"], []] {
            let items = try await provider.homeContinueWatching(
                limit: 10, inLibraries: allowed, separateNextUp: true
            )
            XCTAssertEqual(items.map(\.id), ["movie"])
            XCTAssertNil(items.first?.libraryID)
        }
        XCTAssertEqual(http.sentPaths.filter { $0 == "/System/Info/Public" }.count, 1)
        XCTAssertEqual(http.sentPaths.filter { $0.hasSuffix("/Items/Resume") }.count, 2)
        XCTAssertFalse(http.sentPaths.contains("/Shows/NextUp"))
        XCTAssertTrue(historyQueries(http).allSatisfy { !$0.contains { $0.name == "ParentId" } })
    }

    func testServerHomeSingleAndBatchHistoryStayAccountWideButLatestRemainsFiltered() async throws {
        let http = http()
        let provider = provider(http)
        let sections: [ServerHomeSection] = [
            .init(id: "web:1:resume", kind: .continueWatching),
            .init(id: "web:5:nextup", kind: .nextUp)
        ]
        let single = try await provider.serverHomeItems(
            section: sections[0], limit: 20, excludingLibraryIDs: ["movies", "shows"]
        )
        XCTAssertEqual(single.map(\.id), ["movie"])
        let batch = await provider.serverHomeItems(
            sections: sections, limit: 20, excludingLibraryIDs: ["movies", "shows"]
        )
        XCTAssertEqual(try XCTUnwrap(batch[sections[0].id]).get().map(\.id), ["movie"])
        XCTAssertEqual(try XCTUnwrap(batch[sections[1].id]).get().map(\.id), ["next"])
        for response in batch.values {
            XCTAssertTrue(try response.get().allSatisfy { $0.libraryID == nil })
        }
        XCTAssertFalse(http.sentPaths.contains { $0.hasSuffix("/Views") })
        XCTAssertTrue(historyQueries(http).allSatisfy { !$0.contains { $0.name == "ParentId" } })

        let latest = try await provider.serverHomeItems(
            section: .init(id: "web:6:latestmedia:movies", kind: .recentlyAdded, libraryID: "movies"),
            limit: 20, excludingLibraryIDs: ["movies"]
        )
        XCTAssertTrue(latest.isEmpty)
        XCTAssertFalse(http.sentPaths.contains { $0.hasSuffix("/Items/Latest") })
    }

    func testNormalServersRetainLibraryRestrictionsEvenWithAIOStreamsBranding() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = http(info: #"{"Id":"server","ServerName":"AIOStreams","Version":"12.0.0"}"#)
            let provider = provider(http, kind: kind)
            let items = try await provider.continueWatching(limit: 10, inLibraries: ["visible"])
            XCTAssertEqual(items.map(\.id), ["movie", "next"])
            XCTAssertTrue(items.allSatisfy { $0.libraryID == "visible" })
            XCTAssertTrue(historyQueries(http).allSatisfy {
                $0.first { $0.name == "ParentId" }?.value == "visible"
            })
            let before = historyQueries(http).count
            let hidden = try await provider.continueWatching(limit: 10, inLibraries: [])
            XCTAssertTrue(hidden.isEmpty)
            XCTAssertEqual(historyQueries(http).count, before)
        }
    }

    func testEmptyOrdinaryHistoryDoesNotRetryWithoutTheLibraryFilter() async throws {
        let http = StubHTTPClient()
        http.stub(pathSuffix: "/System/Info/Public", json: #"{"Id":"server"}"#)
        http.stub(pathSuffix: "/Items/Resume", json: #"{"Items":[],"TotalRecordCount":0}"#)
        http.stub(pathSuffix: "/Shows/NextUp", json: #"{"Items":[],"TotalRecordCount":0}"#)
        let items = try await provider(http).continueWatching(limit: 10, inLibraries: ["visible"])
        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(historyQueries(http).count, 2)
        XCTAssertTrue(historyQueries(http).allSatisfy {
            $0.first { $0.name == "ParentId" }?.value == "visible"
        })
    }

    func testIncompleteBridgeDeclarationsDoNotEnableAccountWideHistory() async throws {
        for extensionJSON in ["null", "{}", #"{"features":{}}"#, #"{"features":{"history":0}}"#] {
            let http = http(info: #"{"Id":"server","aiostreams":\#(extensionJSON)}"#)
            let items = try await provider(http).continueWatching(limit: 10, inLibraries: ["visible"])
            XCTAssertTrue(items.allSatisfy { $0.libraryID == "visible" })
        }
    }

    func testIdentityMismatchAndMalformedCapabilityNeverAuthorizeUnfilteredHistory() async throws {
        for (info, expected): (String, AppError) in [
            (#"{"Id":"other","aiostreams":{"features":{"history":1}}}"#, .conflict),
            (#"{"aiostreams":{"features":{"history":1}}}"#, .conflict),
            (#"{"Id":"server","aiostreams":{"features":{"history":"1"}}}"#, .decoding)
        ] {
            let http = http(info: info)
            do {
                _ = try await provider(http).continueWatching(limit: 10, inLibraries: ["visible"])
                XCTFail("Unverified bridge identity must not remove library restrictions.")
            } catch {
                XCTAssertEqual(error as? AppError, expected)
            }
            XCTAssertTrue(historyQueries(http).isEmpty)
        }
    }

    func testCapabilityErrorsAndCancellationPropagateAndAreNotCached() async throws {
        for failure: AppError in [.unauthorized, .invalidResponse, .cancelled] {
            let http = http()
            http.error = failure
            let provider = provider(http)
            do {
                _ = try await provider.continueWatching(limit: 10, inLibraries: ["visible"])
                XCTFail("Capability failure must not be interpreted as an account-wide feed.")
            } catch {
                XCTAssertEqual(error as? AppError, failure)
            }
            XCTAssertTrue(historyQueries(http).isEmpty)
            http.error = nil
            let recovered = try await provider.continueWatching(limit: 10, inLibraries: ["visible"])
            XCTAssertEqual(recovered.map(\.id), ["movie", "next"])
            XCTAssertTrue(recovered.allSatisfy { $0.libraryID == nil })
            XCTAssertEqual(http.sentPaths.filter { $0 == "/System/Info/Public" }.count, 2)
        }
    }

    func testUnscopedAndZeroLimitRequestsDoNotNeedCapabilityDiscovery() async throws {
        let http = http()
        let provider = provider(http)
        _ = try await provider.continueWatching(limit: 10, inLibraries: nil)
        _ = try await provider.homeContinueWatching(limit: 10, inLibraries: nil, separateNextUp: true)
        let count = http.sentPaths.count
        let noItems = try await provider.continueWatching(limit: 0, inLibraries: ["visible"])
        let noResume = try await provider.homeContinueWatching(limit: 0, inLibraries: [], separateNextUp: true)
        XCTAssertTrue(noItems.isEmpty && noResume.isEmpty)
        XCTAssertEqual(http.sentPaths.count, count)
        XCTAssertFalse(http.sentPaths.contains("/System/Info/Public"))
    }

    func testCapabilityDoesNotLeakBetweenProviderSessions() async throws {
        let bridge = http()
        let ordinary = http(info: #"{"Id":"server"}"#)
        let first = try await provider(bridge).continueWatching(limit: 10, inLibraries: ["visible"])
        let second = try await provider(ordinary, userID: "other-viewer")
            .continueWatching(limit: 10, inLibraries: ["visible"])
        XCTAssertTrue(first.allSatisfy { $0.libraryID == nil })
        XCTAssertTrue(second.allSatisfy { $0.libraryID == "visible" })
        XCTAssertTrue(ordinary.sentPaths.contains("/Users/other-viewer/Items/Resume"))
    }
}
