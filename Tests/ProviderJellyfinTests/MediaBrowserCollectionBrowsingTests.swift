import CoreModels
import XCTest
@testable import ProviderJellyfin

final class MediaBrowserCollectionBrowsingTests: XCTestCase {
    private func provider(_ kind: ProviderKind, _ http: StubHTTPClient) -> JellyfinProvider {
        JellyfinProvider(
            session: UserSession(
                server: MediaServer(
                    id: "collections-server", name: "Server",
                    baseURL: URL(string: "https://media.example")!, provider: kind
                ),
                userID: "user", userName: "Viewer", deviceID: "device", accessToken: "test-token"
            ),
            accountID: "account", http: http
        )
    }

    func testJellyfinAndEmbyKeepNativeCollectionsLibraryAndBoxSetList() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = StubHTTPClient()
            http.stub(pathSuffix: "/Users/user/Views", json: """
            {"Items":[{"Id":"boxsets","Name":"Collections","CollectionType":"boxsets"}]}
            """)
            http.stub(pathSuffix: "/Users/user/Items", json: """
            {"Items":[{"Id":"set","Name":"Collection","Type":"BoxSet"}],"TotalRecordCount":61}
            """)
            let provider = provider(kind, http)
            let libraries = try await provider.libraries()
            XCTAssertEqual(libraries.map(\.id), ["boxsets"])
            XCTAssertEqual(libraries.map(\.kind), [.collection])
            XCTAssertFalse(libraries[0].isServerCollectionDirectory)
            XCTAssertEqual(libraries[0].hasCollections, true)
            XCTAssertEqual(http.sentPaths, ["/Users/user/Views", "/Users/user/Items"])
            let existenceQuery = try XCTUnwrap(http.queryItems(forPathSuffix: "/Users/user/Items"))
            XCTAssertTrue(existenceQuery.contains(URLQueryItem(name: "Limit", value: "1")))
            XCTAssertTrue(existenceQuery.contains(URLQueryItem(name: "ParentId", value: "boxsets")))
            let page = try await provider.items(
                in: "boxsets", kind: .collection, page: PageRequest(startIndex: 60, limit: 1)
            )
            XCTAssertEqual(page.items.map(\.kind), [.collection])
            XCTAssertEqual(page.totalCount, 61)
            let query = try XCTUnwrap(http.queryItems(forPathSuffix: "/Users/user/Items"))
            XCTAssertTrue(query.contains(URLQueryItem(name: "ParentId", value: "boxsets")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "StartIndex", value: "60")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "Limit", value: "1")))
        }
    }

    func testJellyfinAndEmbyPageMixedMembersInServerOrder() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = StubHTTPClient()
            http.stub(pathSuffix: "/Users/user/Items", json: """
            {"Items":[
              {"Id":"z","Name":"Z","Type":"Movie"},
              {"Id":"a","Name":"A","Type":"Series"},
              {"Id":"nested","Name":"Nested","Type":"BoxSet"}
            ],"TotalRecordCount":63}
            """)
            let result = try await provider(kind, http).collectionMembers(
                of: "set", page: PageRequest(startIndex: 60, limit: 3)
            )
            XCTAssertEqual(result.items.map(\.id), ["z", "a", "nested"])
            XCTAssertEqual(result.items.map(\.kind), [.movie, .series, .collection])
            XCTAssertEqual(result.totalCount, 63)
            let query = try XCTUnwrap(http.queryItems(forPathSuffix: "/Users/user/Items"))
            XCTAssertTrue(query.contains(URLQueryItem(name: "ParentId", value: "set")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "Recursive", value: "false")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "StartIndex", value: "60")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "Limit", value: "3")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "EnableUserData", value: "true")))
            XCTAssertTrue(try XCTUnwrap(query.first { $0.name == "Fields" }?.value)
                .split(separator: ",").contains("UserData"))
            XCTAssertFalse(query.contains { ["SortBy", "SortOrder", "IncludeItemTypes"].contains($0.name) })
        }
    }

    func testJellyfinAndEmbyDistinguishFailureFromEmptyCollection() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = StubHTTPClient()
            http.stub(pathSuffix: "/Users/user/Items", json: #"{"Items":[],"TotalRecordCount":0}"#)
            let provider = provider(kind, http)
            let result = try await provider.collectionMembers(of: "set", page: PageRequest())
            XCTAssertEqual(result.totalCount, 0)
            XCTAssertTrue(result.items.isEmpty)
            http.error = .unauthorized
            do {
                _ = try await provider.collectionMembers(of: "set", page: PageRequest())
                XCTFail("Expected membership error")
            } catch {
                XCTAssertEqual(error as? AppError, .unauthorized)
            }
        }
    }

    func testCollectionMembersPreserveUserEpisodeCountsWithoutAdditionalRequests() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = StubHTTPClient()
            http.stub(pathSuffix: "/Users/user/Items", json: """
            {"Items":[
              {"Id":"seen","Name":"Seen","Type":"Series","UserData":{"Played":true,"UnplayedItemCount":0}},
              {"Id":"zero","Name":"Zero","Type":"Series","UserData":{"UnplayedItemCount":0}},
              {"Id":"partial","Name":"Partial","Type":"Series","ChildCount":2,"UserData":{"UnplayedItemCount":18}},
              {"Id":"movie","Name":"Movie","Type":"Movie","UserData":{"Played":true,"PlaybackPositionTicks":200000000}}
            ],"TotalRecordCount":4}
            """)
            let result = try await provider(kind, http).collectionMembers(of: "set", page: PageRequest())
            XCTAssertEqual(result.items.map(\.unwatchedEpisodeCount), [0, 0, 18, nil])
            XCTAssertTrue(result.items[0].isPlayed)
            XCTAssertFalse(result.items[2].isPlayed)
            XCTAssertFalse(result.items[3].isPlayed, "A resumed rewatch must keep its in-progress state.")
            XCTAssertEqual(result.items[3].resumePosition, 20)
            XCTAssertEqual(http.sentPaths, ["/Users/user/Items"], "The request must use the session's server user.")
        }
    }
}
