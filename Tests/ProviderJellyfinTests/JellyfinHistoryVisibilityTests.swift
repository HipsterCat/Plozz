import CoreModels
import CoreNetworking
import XCTest
@testable import ProviderJellyfin

final class JellyfinHistoryVisibilityTests: XCTestCase {
    private let resume = """
    {"Items":[{"Id":"movie","Type":"Movie",
      "UserData":{"PlaybackPositionTicks":1200000000,"LastPlayedDate":"2026-10-20T12:00:00Z"}}],
      "TotalRecordCount":1}
    """
    private let nextUp = """
    {"Items":[{"Id":"next","Type":"Episode","SeriesId":"series",
      "UserData":{"LastPlayedDate":"2026-10-19T12:00:00Z"}}],"TotalRecordCount":1}
    """
    private let sections: [ServerHomeSection] = [
        .init(id: "web:1:resume", kind: .continueWatching),
        .init(id: "web:5:nextup", kind: .nextUp)
    ]

    private func provider(_ http: StubHTTPClient, kind: ProviderKind) -> JellyfinProvider {
        JellyfinProvider(
            session: UserSession(
                server: MediaServer(
                    id: "server", name: "Home", baseURL: URL(string: "https://media.test/base")!,
                    provider: kind
                ),
                userID: "viewer", userName: "Viewer", deviceID: "test-device", accessToken: "TEST_TOKEN"
            ),
            http: http
        )
    }

    private func http(emptyHistory: Bool = false) -> StubHTTPClient {
        let http = StubHTTPClient()
        let empty = #"{"Items":[],"TotalRecordCount":0}"#
        http.stub(pathSuffix: "/Items/Resume", json: emptyHistory ? empty : resume)
        http.stub(pathSuffix: "/Shows/NextUp", json: emptyHistory ? empty : nextUp)
        http.stub(pathSuffix: "/Views", json: """
        {"Items":[{"Id":"visible","CollectionType":"movies"},{"Id":"hidden","CollectionType":"tvshows"}]}
        """)
        return http
    }

    private func historyQueries(_ http: StubHTTPClient) -> [[URLQueryItem]] {
        zip(http.sentPaths, http.sentQueryItems).compactMap { path, query in
            path.hasSuffix("/Items/Resume") || path.hasSuffix("/Shows/NextUp") ? query : nil
        }
    }

    func testCombinedHistoryUsesOnlyEnabledLibrariesAndPreservesServerUser() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = http()
            let provider = provider(http, kind: kind)
            let items = try await provider.continueWatching(
                limit: .max, inLibraries: ["visible", provider.collectionDirectoryID]
            )
            XCTAssertEqual(items.map(\.id), ["movie", "next"])
            XCTAssertEqual(items.first?.resumePosition, 120)
            XCTAssertTrue(items.allSatisfy { $0.libraryID == "visible" })
            XCTAssertTrue(items.allSatisfy {
                !$0.taggingSource("account").isVisibleOnHome(isLibraryVisible: { _ in false })
            })
            XCTAssertEqual(historyQueries(http).count, 2)
            XCTAssertTrue(historyQueries(http).allSatisfy {
                $0.first { $0.name == "ParentId" }?.value == "visible"
            })
            XCTAssertEqual(Set(http.sentPaths), ["/Users/viewer/Items/Resume", "/Shows/NextUp"])
            XCTAssertEqual(http.queryItems(forPathSuffix: "/Shows/NextUp")?
                .first { $0.name == "UserId" }?.value, "viewer")
        }
    }

    func testEmptyAndCollectionsOnlyScopesMakeNoRequests() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = http()
            let provider = provider(http, kind: kind)
            for scope in [[], [provider.collectionDirectoryID]] {
                let combined = try await provider.continueWatching(limit: 10, inLibraries: scope)
                XCTAssertTrue(combined.isEmpty)
                for separateNextUp in [false, true] {
                    let home = try await provider.homeContinueWatching(
                        limit: 10, inLibraries: scope, separateNextUp: separateNextUp
                    )
                    XCTAssertTrue(home.isEmpty)
                }
            }
            XCTAssertTrue(http.sentPaths.isEmpty)
        }
    }

    func testResumeOnlyHomeReloadsLibraryScopeWithoutFetchingNextUp() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = http()
            let provider = provider(http, kind: kind)
            for libraryID in ["visible", "new-visible"] {
                let items = try await provider.homeContinueWatching(
                    limit: 10, inLibraries: [libraryID], separateNextUp: true
                )
                XCTAssertEqual(items.map(\.id), ["movie"])
                XCTAssertEqual(items.first?.libraryID, libraryID)
            }
            let disabled = try await provider.homeContinueWatching(
                limit: 10, inLibraries: [], separateNextUp: true
            )
            XCTAssertTrue(disabled.isEmpty)
            XCTAssertEqual(http.sentPaths, Array(repeating: "/Users/viewer/Items/Resume", count: 2))
            XCTAssertEqual(historyQueries(http).map {
                $0.first { $0.name == "ParentId" }?.value
            }, ["visible", "new-visible"])
        }
    }

    func testServerHomeSingleAndBatchHistoryHonorExcludedLibraries() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = http()
            let provider = provider(http, kind: kind)
            let single = try await provider.serverHomeItems(
                section: sections[0], limit: 20, excludingLibraryIDs: ["hidden"]
            )
            XCTAssertEqual(single.map(\.id), ["movie"])
            XCTAssertEqual(single.first?.libraryID, "visible")
            let batch = await provider.serverHomeItems(
                sections: sections, limit: 20, excludingLibraryIDs: ["hidden"]
            )
            XCTAssertEqual(try XCTUnwrap(batch[sections[0].id]).get().map(\.id), ["movie"])
            XCTAssertEqual(try XCTUnwrap(batch[sections[1].id]).get().map(\.id), ["next"])
            for response in batch.values {
                XCTAssertTrue(try response.get().allSatisfy { $0.libraryID == "visible" })
            }
            XCTAssertEqual(http.sentPaths.filter { $0.hasSuffix("/Views") }.count, 2)
            XCTAssertEqual(historyQueries(http).count, 3)
            XCTAssertTrue(historyQueries(http).allSatisfy {
                $0.first { $0.name == "ParentId" }?.value == "visible"
            })
            XCTAssertFalse(http.sentPaths.contains("/System/Info/Public"))
        }
    }

    func testServerHomeMakesNoHistoryRequestsWhenEveryLibraryIsDisabled() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = http()
            let provider = provider(http, kind: kind)
            let single = try await provider.serverHomeItems(
                section: sections[0], limit: 20, excludingLibraryIDs: ["visible", "hidden"]
            )
            XCTAssertTrue(single.isEmpty)
            let batch = await provider.serverHomeItems(
                sections: sections, limit: 20, excludingLibraryIDs: ["visible", "hidden"]
            )
            for section in sections {
                XCTAssertTrue(try XCTUnwrap(batch[section.id]).get().isEmpty)
            }
            XCTAssertEqual(http.sentPaths, Array(repeating: "/Users/viewer/Views", count: 2))
        }
    }

    func testEmptyHistoryDoesNotRetryWithoutTheLibraryFilter() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = http(emptyHistory: true)
            let provider = provider(http, kind: kind)
            let combined = try await provider.continueWatching(limit: 10, inLibraries: ["visible"])
            let resume = try await provider.homeContinueWatching(
                limit: 10, inLibraries: ["visible"], separateNextUp: true
            )
            XCTAssertTrue(combined.isEmpty && resume.isEmpty)
            XCTAssertEqual(http.sentPaths.count, 3)
            XCTAssertEqual(historyQueries(http).count, 3)
            XCTAssertTrue(historyQueries(http).allSatisfy {
                $0.first { $0.name == "ParentId" }?.value == "visible"
            })
        }
    }

    func testOneFailedHistoryFeedCannotBecomeSuccessfulEmptyHistory() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            for failedPath in ["/Items/Resume", "/Shows/NextUp"] {
                for scope: [String]? in [nil, ["visible"], ["visible", "second"]] {
                    let http = StubHTTPClient()
                    for path in ["/Items/Resume", "/Shows/NextUp"] {
                        http.stub(
                            pathSuffix: path,
                            json: path == failedPath ? #"{"Items":"invalid"}"# : #"{"Items":[],"TotalRecordCount":0}"#
                        )
                    }
                    let provider = provider(http, kind: kind)
                    let captured = await HTTPResponseDiagnostics.capture {
                        try await provider.continueWatching(limit: 20, inLibraries: scope)
                    }
                    switch captured.result {
                    case .success:
                        XCTFail("An empty companion feed cannot hide a failed history request.")
                    case let .failure(error):
                        XCTAssertEqual(error as? AppError, .decoding)
                    }
                    XCTAssertFalse(captured.responses.isEmpty)
                    XCTAssertTrue(captured.responses.allSatisfy {
                        $0.route == (failedPath == "/Items/Resume" ? .resumeItems : .nextUp)
                    })
                    XCTAssertEqual(historyQueries(http).count, (scope?.count ?? 1) * 2)
                }
            }
        }
    }

    func testPartialHistoryFailurePreservesUsefulItemsInEitherFeed() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            for failedPath in ["/Items/Resume", "/Shows/NextUp"] {
                let http = StubHTTPClient()
                http.stub(
                    pathSuffix: "/Items/Resume",
                    json: failedPath == "/Items/Resume" ? #"{"Items":"invalid"}"# : resume
                )
                http.stub(
                    pathSuffix: "/Shows/NextUp",
                    json: failedPath == "/Shows/NextUp" ? #"{"Items":"invalid"}"# : nextUp
                )
                let provider = provider(http, kind: kind)
                for scope: [String]? in [nil, ["visible"]] {
                    let items = try await provider.continueWatching(limit: 20, inLibraries: scope)
                    XCTAssertEqual(items.map(\.id), failedPath == "/Items/Resume" ? ["next"] : ["movie"])
                }
            }
        }
    }

    func testSeriesResumeDoesNotHideAnEmptyPartialFailure() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = StubHTTPClient()
            http.stub(pathSuffix: "/Items/Resume", json: #"{"Items":"invalid"}"#)
            http.stub(pathSuffix: "/Shows/NextUp", json: #"{"Items":[],"TotalRecordCount":0}"#)
            do {
                _ = try await provider(http, kind: kind).resumeEpisode(inSeries: "series")
                XCTFail("Unavailable resume history must not look like an unwatched series.")
            } catch {
                XCTAssertEqual(error as? AppError, .decoding)
            }
        }
    }

    func testHistoryErrorsAndCancellationPropagateWithoutWideningScope() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            for failure: AppError in [.unauthorized, .invalidResponse, .cancelled] {
                let http = http()
                http.error = failure
                let provider = provider(http, kind: kind)
                do {
                    _ = try await provider.continueWatching(limit: 10, inLibraries: ["visible"])
                    XCTFail("Failed history requests must not become successful empty feeds.")
                } catch {
                    XCTAssertEqual(error as? AppError, failure)
                }
                http.error = nil
                let recovered = try await provider.continueWatching(limit: 10, inLibraries: ["visible"])
                XCTAssertEqual(recovered.map(\.id), ["movie", "next"])
                XCTAssertTrue(recovered.allSatisfy { $0.libraryID == "visible" })
                XCTAssertTrue(historyQueries(http).allSatisfy {
                    $0.first { $0.name == "ParentId" }?.value == "visible"
                })
                XCTAssertFalse(http.sentPaths.contains("/System/Info/Public"))
            }
        }
    }

    func testUnscopedHistoryAndZeroLimitsDoNotNeedDiscovery() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = http()
            let provider = provider(http, kind: kind)
            let combined = try await provider.continueWatching(limit: 10, inLibraries: nil)
            let resume = try await provider.homeContinueWatching(
                limit: 10, inLibraries: nil, separateNextUp: true
            )
            XCTAssertEqual(combined.map(\.id), ["movie", "next"])
            XCTAssertEqual(resume.map(\.id), ["movie"])
            XCTAssertTrue((combined + resume).allSatisfy { $0.libraryID == nil })
            let noItems = try await provider.continueWatching(limit: 0, inLibraries: ["visible"])
            let noResume = try await provider.homeContinueWatching(
                limit: 0, inLibraries: [], separateNextUp: true
            )
            XCTAssertTrue(noItems.isEmpty && noResume.isEmpty)
            XCTAssertEqual(http.sentPaths.count, 3)
            XCTAssertEqual(historyQueries(http).count, 3)
            XCTAssertTrue(historyQueries(http).allSatisfy { !$0.contains { $0.name == "ParentId" } })
        }
    }
}
