import CoreModels
import CoreNetworking
import Foundation
import XCTest
@testable import ProviderJellyfin

final class MediaBrowserVideoPlaylistScopeTests: XCTestCase {
    func testNativeCollectionListingDoesNotChangeVideoPlaylistScopingOrAuthoredOrder() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = PlaylistScopeHTTP()
            let provider = JellyfinProvider(session: UserSession(
                server: MediaServer(id: "server", name: "Fixture", baseURL: URL(string: "https://fixture.invalid")!, provider: kind),
                userID: "user", userName: "Viewer", deviceID: "device", accessToken: "fixture"
            ), http: http)
            let movies = try await provider.videoPlaylists(in: "movies", page: PageRequest(limit: 1))
            XCTAssertEqual(movies.items.map(\.id), ["mixed"])
            XCTAssertEqual(movies.totalCount, 1)
            let count = await http.requests
            _ = try await provider.videoPlaylists(in: "movies", page: PageRequest(startIndex: 1, limit: 1))
            let cachedCount = await http.requests
            XCTAssertEqual(count, cachedCount)
            let shows = try await provider.videoPlaylists(in: "shows", page: PageRequest())
            XCTAssertEqual(shows.items.map(\.id), ["mixed", "shows-only"])
            let members = try await provider.videoPlaylistMembers(of: "mixed", page: PageRequest(startIndex: 1, limit: 2))
            XCTAssertEqual(members.items.map(\.id), ["movie", "episode"])
            XCTAssertEqual(members.totalCount, 3)
        }
    }
}

private actor PlaylistScopeHTTP: HTTPClient {
    private(set) var requests = 0
    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests += 1
        let query = Dictionary(uniqueKeysWithValues: endpoint.queryItems.map { ($0.name, $0.value ?? "") })
        let rows: [[String: String]]
        switch endpoint.path {
        case "/Playlists/mixed/Items":
            rows = [["Id": "episode", "Type": "Episode"], ["Id": "movie", "Type": "Movie"], ["Id": "episode", "Type": "Episode"]]
        case "/Playlists/shows-only/Items":
            rows = [["Id": "episode", "Type": "Episode"]]
        default:
            if query["IncludeItemTypes"] == "Playlist" {
                rows = [
                    ["Id": "mixed", "Name": "Mixed", "Type": "Playlist", "MediaType": "Video"],
                    ["Id": "shows-only", "Name": "Shows only", "Type": "Playlist", "MediaType": "Video"],
                    ["Id": "music", "Name": "Music", "Type": "Playlist", "MediaType": "Audio"]
                ]
            } else {
                guard query["EnableImages"] == "false", query["EnableUserData"] == "false" else { throw AppError.invalidResponse }
                rows = [["Id": query["ParentId"] == "movies" ? "movie" : "episode", "Type": "Movie"]]
            }
        }
        let start = Int(query["StartIndex"] ?? "") ?? 0
        let limit = Int(query["Limit"] ?? "") ?? 200
        return (
            try JSONSerialization.data(withJSONObject: ["Items": Array(rows.dropFirst(start).prefix(limit)), "TotalRecordCount": rows.count]),
            HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}
