import CoreModels
import CoreNetworking
import Foundation
import XCTest
@testable import ProviderSilo

extension SiloProviderTests {
    func testSearchUsesNativeCatalogWithProfileAndLibraryScope() async throws {
        let raw = try credential(profileToken: "profile-proof").encoded()
        let http = SiloSearchHTTP(catalogs: [
            "1": [#"{"content_id":"movie-tmdb-1","type":"movie","title":"Dune","year":2021}"#],
            "2": [
                #"{"content_id":"series-tvdb-2","type":"series","title":"Dune: Prophecy"}"#,
                #"{"content_id":"episode-tvdb-2-1-1","type":"episode","title":"Dune episode"}"#
            ]
        ])
        let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)

        let items = try await provider.search(query: "Dune & prophecy", limit: 40)

        XCTAssertEqual(items.map(\.kind), [.movie, .series, .episode])
        XCTAssertEqual(items.map(\.libraryID), ["1", "2", "2"])
        XCTAssertEqual(items.map(\.sourceAccountID), ["account1", "account1", "account1"])
        XCTAssertEqual(items.first?.providerIDs["Tmdb"], "1")
        XCTAssertEqual(items.last?.seriesID, "series-tvdb-2")
        let requests = await http.requests
        XCTAssertEqual(requests.map(\.path), ["/api/v2/user/libraries", "/api/v2/catalog", "/api/v2/catalog"])
        XCTAssertTrue(requests.allSatisfy { $0.method == .get })
        XCTAssertTrue(requests.allSatisfy { $0.headers["X-Profile-Id"] == "profile1" })
        XCTAssertTrue(requests.allSatisfy { $0.headers["X-Profile-Token"] == "profile-proof" })
        XCTAssertTrue(requests.allSatisfy { $0.headers["Authorization"] != nil })
        XCTAssertTrue(requests.dropFirst().allSatisfy {
            $0.queryItems.contains(.init(name: "q", value: "Dune & prophecy"))
        })
    }

    func testSearchExcludesDisabledLibrariesAndDeduplicatesWithinLimit() async throws {
        let raw = try credential().encoded()
        let shared = #"{"content_id":"movie-tmdb-1","type":"movie","title":"Dune"}"#
        let second = #"{"content_id":"movie-tmdb-2","type":"movie","title":"Dune Part Two"}"#
        let http = SiloSearchHTTP(catalogs: [
            "1": [shared],
            "2": [shared, second],
            "3": [#"{"content_id":"movie-tmdb-3","type":"movie","title":"Hidden"}"#]
        ])
        let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)

        let items = try await provider.search(query: "Dune", limit: 3, excludingLibraries: ["3"])

        XCTAssertEqual(items.map(\.id), ["movie-tmdb-1", "movie-tmdb-2"])
        XCTAssertEqual(items.map(\.libraryID), ["1", "2"])
        let requests = await http.requests.filter { $0.path == "/api/v2/catalog" }
        XCTAssertEqual(requests.map { $0.value(for: "library_id") }, ["1", "2"])
        XCTAssertEqual(requests.map { $0.value(for: "limit") }, ["3", "2"])
    }

    func testSearchKeepsCursorPageSizeWhenServerReturnsAShortPage() async throws {
        let raw = try credential().encoded()
        let http = SiloSearchHTTP(catalogs: ["1": searchCards(count: 6)], pageCapacity: 2)
        let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)

        let items = try await provider.search(query: "Movie", limit: 3)

        XCTAssertEqual(items.map(\.id), ["movie-tmdb-1", "movie-tmdb-2", "movie-tmdb-3"])
        let requests = await http.requests.filter { $0.path == "/api/v2/catalog" }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.value(for: "limit") }, ["3", "3"])
        XCTAssertNil(requests.first?.value(for: "cursor"))
        XCTAssertNotNil(requests.last?.value(for: "cursor"))
    }

    func testSearchKeepsCursorPageSizeBeyondNativeMaximumAndTrimsFinalPage() async throws {
        let raw = try credential().encoded()
        let http = SiloSearchHTTP(catalogs: ["1": searchCards(count: 450)])
        let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)

        let items = try await provider.search(query: "Movie", limit: 201)

        XCTAssertEqual(items.count, 201)
        XCTAssertEqual(items.first?.id, "movie-tmdb-1")
        XCTAssertEqual(items.last?.id, "movie-tmdb-201")
        let requests = await http.requests.filter { $0.path == "/api/v2/catalog" }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.value(for: "limit") }, ["200", "200"])
    }

    func testSearchStopsAtLimitWithoutRequestingAnotherLibrary() async throws {
        let raw = try credential().encoded()
        let http = SiloSearchHTTP(catalogs: ["1": searchCards(count: 5), "2": searchCards(count: 5)])
        let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)

        let items = try await provider.search(query: "Movie", limit: 2)

        XCTAssertEqual(items.count, 2)
        let requests = await http.requests.filter { $0.path == "/api/v2/catalog" }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.value(for: "library_id"), "1")
    }

    func testSearchWithAllLibrariesDisabledDoesNotQueryCatalog() async throws {
        let raw = try credential().encoded()
        let http = SiloSearchHTTP(catalogs: ["1": searchCards(count: 1)])
        let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)

        let items = try await provider.search(query: "Movie", limit: 40, excludingLibraries: ["1"])

        XCTAssertTrue(items.isEmpty)
        let requests = await http.requests
        XCTAssertEqual(requests.map(\.path), ["/api/v2/user/libraries"])
    }

    func testSearchEmptyResultsAndNonpositiveLimits() async throws {
        let raw = try credential().encoded()
        let http = SiloSearchHTTP(catalogs: ["1": []])
        let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)

        for limit in [0, -1] {
            let items = try await provider.search(query: "Movie", limit: limit)
            XCTAssertTrue(items.isEmpty)
        }
        let initialRequests = await http.requests
        XCTAssertTrue(initialRequests.isEmpty)
        let items = try await provider.search(query: "Missing", limit: 40)
        XCTAssertTrue(items.isEmpty)
        let requests = await http.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testSearchPreservesCatalogFailureInsteadOfReturningNoMatches() async throws {
        for (status, expected) in [(403, AppError.unauthorized), (503, AppError.invalidResponse)] {
            let raw = try credential().encoded()
            let http = SiloSearchHTTP(catalogs: ["1": []], catalogStatus: status)
            let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)

            do {
                _ = try await provider.search(query: "Movie", limit: 40)
                XCTFail("HTTP \(status) must remain a failed search")
            } catch {
                XCTAssertEqual(error as? AppError, expected)
            }
        }
    }

    func testSearchRejectsMissingOrRepeatedContinuationCursors() async throws {
        for page in [#"{"has_more":true}"#, #"{"has_more":true,"next_cursor":"repeated"}"#] {
            let raw = try credential().encoded()
            let http = SiloHTTPStub([
                "/api/v2/user/libraries": #"{"items":[{"id":"1","name":"Movies","type":"movie"}]}"#,
                "/api/v2/catalog": """
                {"items":[{"content_id":"movie-tmdb-1","type":"movie","title":"Movie"}],
                 "total":100,"total_exact":true,"window_cursor":"window","page":\(page)}
                """
            ])
            let provider = try SiloProvider(context: context(raw), credentials: SiloCredentialStub(raw), http: http)
            do {
                _ = try await provider.search(query: "Movie", limit: 40)
                XCTFail("Invalid continuation must not loop or silently truncate")
            } catch {
                XCTAssertEqual(error as? AppError, .invalidResponse)
            }
            let requests = await http.requests
            XCTAssertLessThanOrEqual(requests.count, 3)
        }
    }

    private func searchCards(count: Int) -> [String] {
        (1...count).map {
            #"{"content_id":"movie-tmdb-\#($0)","type":"movie","title":"Movie \#($0)"}"#
        }
    }
}

private extension Endpoint {
    func value(for name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }
}

private actor SiloSearchHTTP: HTTPClient {
    private(set) var requests: [Endpoint] = []
    let catalogs: [String: [String]]
    let pageCapacity: Int
    let catalogStatus: Int

    init(catalogs: [String: [String]], pageCapacity: Int = 200, catalogStatus: Int = 200) {
        self.catalogs = catalogs
        self.pageCapacity = pageCapacity
        self.catalogStatus = catalogStatus
    }

    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append(endpoint)
        if endpoint.path == "/api/v2/user/libraries" {
            let libraries = catalogs.keys.sorted().map {
                #"{"id":"\#($0)","name":"Library \#($0)","type":"video"}"#
            }
            return try response(#"{"items":[\#(libraries.joined(separator: ","))]}"#, baseURL: baseURL)
        }
        guard endpoint.path == "/api/v2/catalog",
              let libraryID = endpoint.value(for: "library_id"),
              let cards = catalogs[libraryID],
              let limit = endpoint.value(for: "limit").flatMap(Int.init),
              (1...200).contains(limit) else { throw AppError.invalidResponse }
        if catalogStatus != 200 {
            return try response("{}", status: catalogStatus, baseURL: baseURL)
        }
        var offset = 0
        if let cursor = endpoint.value(for: "cursor") {
            let fields = cursor.split(separator: ":")
            // Native Silo cursor scope binds limit along with the query/library.
            guard fields.count == 3, fields[0] == libraryID,
                  Int(fields[2]) == limit, let start = Int(fields[1]) else {
                return try response("{}", status: 409, baseURL: baseURL)
            }
            offset = start
        }
        let page = Array(cards.dropFirst(offset).prefix(min(limit, pageCapacity)))
        let next = offset + page.count
        let hasMore = next < cards.count
        let continuation = hasMore ? #","next_cursor":"\#(libraryID):\#(next):\#(limit)""# : ""
        return try response("""
            {"items":[\(page.joined(separator: ","))],"total":\(cards.count),"total_exact":true,
             "window_cursor":"window","page":{"has_more":\(hasMore)\(continuation)}}
            """, baseURL: baseURL)
    }

    private func response(_ body: String, status: Int = 200, baseURL: URL) throws -> (Data, HTTPURLResponse) {
        (Data(body.utf8), try XCTUnwrap(HTTPURLResponse(
            url: baseURL, statusCode: status, httpVersion: nil, headerFields: nil
        )))
    }
}
