import XCTest
import CoreModels
import CoreNetworking
@testable import ProviderJellyfin

/// Native count offsets and count-only compatibility for Jellyfin and Emby.
final class JellyfinLetterIndexTests: XCTestCase {
    func testIgnoredAlphabetFiltersHideIndexAfterThreeScopedRequests() async throws {
        for kind in [ProviderKind.jellyfin, .emby] {
            for direction in [SortDirection.ascending, .descending] {
                let stub = StubHTTPClient()
                stub.stub(pathSuffix: "/Items", requiring: [.init(name: "Limit", value: "0")],
                          json: #"{"Items":[],"TotalRecordCount":10000}"#)
                stub.stub(pathSuffix: "/Items",
                          json: #"{"Items":[{"Id":"z","Name":"Zulu","Type":"Movie"},{"Id":"a","Name":"Alpha","Type":"Movie"}],"TotalRecordCount":10000}"#)
                let provider = JellyfinProvider(session: makeSession(kind: kind), http: stub)
                let pageRequest = PageRequest(
                    limit: 2, sort: .init(field: .name, direction: direction),
                    filters: .init(filter: .unwatched, genre: "Drama", year: 2025)
                )

                let entries = try await provider.libraryQueryLetterIndex(
                    in: "virtual", kind: .movie, page: pageRequest
                )

                XCTAssertTrue(entries.isEmpty)
                XCTAssertEqual(stub.sentPaths.count, 3)
                XCTAssertEqual(stub.sentQueryItems.compactMap {
                    $0.first(where: { $0.name == "NameLessThan" })?.value
                }, ["Z"], "Do not fan out the remaining letters when predicates are ignored")
                XCTAssertEqual(stub.sentQueryItems.filter {
                    $0.contains(.init(name: "NameStartsWith", value: "Z"))
                }.count, 1)
                for query in stub.sentQueryItems {
                    for item in [
                        URLQueryItem(name: "ParentId", value: "virtual"),
                        .init(name: "IncludeItemTypes", value: "Movie"),
                        .init(name: "Recursive", value: "true"),
                        .init(name: "IsPlayed", value: "false"),
                        .init(name: "Genres", value: "Drama"),
                        .init(name: "Years", value: "2025"),
                        .init(name: "Limit", value: "0")
                    ] {
                        XCTAssertTrue(query.contains(item))
                    }
                }
                let page = try await provider.items(in: "virtual", kind: .movie, page: pageRequest)
                XCTAssertEqual(page.items.map(\.id), ["z", "a"])
                XCTAssertEqual(page.totalCount, 10000)
            }
        }
    }

    func testIgnoredAlphabetFiltersAreRecheckedForOtherLibrariesAndRefresh() async throws {
        let stub = StubHTTPClient()
        stub.stubSequence(pathSuffix: "/Items", jsons: Array(
            repeating: #"{"Items":[],"TotalRecordCount":10000}"#, count: 3
        ))
        stub.stub(pathSuffix: "/Items", json: #"{"Items":[],"TotalRecordCount":0}"#)
        let provider = JellyfinProvider(session: makeSession(), http: stub)

        let unsupported = try await provider.letterIndex(in: "virtual", kind: .movie, sort: .default)
        XCTAssertTrue(unsupported.isEmpty)
        XCTAssertEqual(stub.sentPaths.count, 3)
        _ = try await provider.letterIndex(in: "native", kind: .movie, sort: .default)
        XCTAssertEqual(stub.sentPaths.count, 31)
        _ = try await provider.letterIndex(in: "virtual", kind: .movie, sort: .default)
        XCTAssertEqual(stub.sentPaths.count, 59)
    }

    func testNativeSingleBucketAndEmptyLibrariesRetainAlphabetSupport() async throws {
        for kind in [ProviderKind.jellyfin, .emby] {
            for direction in [SortDirection.ascending, .descending] {
                for (names, letter) in [
                    (["ALIEN", "ALPHA"], "A"), (["ZORRO", "ZULU"], "Z"),
                    (["123", "456"], "#"), (["映画"], "#"), ([], "")
                ] {
                    let provider = JellyfinProvider(
                        session: makeSession(kind: kind), http: AlphabetCountHTTP(names: names)
                    )
                    let entries = try await provider.letterIndex(
                        in: "native", kind: .movie, sort: .init(field: .name, direction: direction)
                    )
                    XCTAssertEqual(entries, names.isEmpty ? [] : [.init(letter: letter, startIndex: 0)])
                }
            }
        }
    }

    func testAlphabetPredicateProbeFailuresAreNotUnsupportedCapabilities() async {
        let cases: [(status: Int, json: String, error: AppError)] = [
            (401, "{}", .unauthorized),
            (500, "{}", .invalidResponse),
            (200, #"{"Items":[]}"#, .invalidResponse),
            (200, #"{"Items":[],"TotalRecordCount":-1}"#, .invalidResponse),
            (200, #"{"Items":[{"Id":"z"}],"TotalRecordCount":10000}"#, .invalidResponse)
        ]
        for fixture in cases {
            let stub = StubHTTPClient()
            stub.stub(pathSuffix: "/Items", requiring: [.init(name: "NameStartsWith", value: "Z")],
                      json: fixture.json, status: fixture.status)
            stub.stub(pathSuffix: "/Items", json: #"{"Items":[],"TotalRecordCount":10000}"#)
            let provider = JellyfinProvider(session: makeSession(), http: stub)
            do {
                _ = try await provider.letterIndex(in: "virtual", kind: .movie, sort: .default)
                XCTFail("A failed predicate request cannot establish an unsupported capability")
            } catch {
                XCTAssertEqual(error as? AppError, fixture.error)
            }
        }
    }

    func testLargeNativeCountsAreNotAnUnsupportedCapability() async throws {
        let stub = StubHTTPClient()
        stub.stub(pathSuffix: "/Items", requiring: [.init(name: "NameStartsWith", value: "Z")],
                  json: #"{"Items":[],"TotalRecordCount":0}"#)
        stub.stub(pathSuffix: "/Items", json: #"{"Items":[],"TotalRecordCount":2000000}"#)
        let provider = JellyfinProvider(session: makeSession(), http: stub)

        let entries = try await provider.letterIndex(in: "large", kind: .movie, sort: .default)

        XCTAssertEqual(entries, [.init(letter: "#", startIndex: 0)])
        XCTAssertEqual(stub.sentPaths.count, 28)
        XCTAssertTrue(stub.sentQueryItems.allSatisfy { $0.contains(.init(name: "Limit", value: "0")) })
    }

    func testCancelledAlphabetPredicateCannotReturnAnEmptySuccess() async {
        let provider = JellyfinProvider(session: makeSession(), http: CancelledAlphabetPredicateHTTP())
        do {
            _ = try await provider.letterIndex(in: "virtual", kind: .movie, sort: .default)
            XCTFail("Cancellation must not establish unsupported alphabet filters")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected cancellation, got \(error)")
        }
    }

    func testCountOnlyIncompatibleCatalogHidesIndexWithoutChangingBrowse() async throws {
        for kind in [ProviderKind.jellyfin, .emby] {
            for direction in [SortDirection.ascending, .descending] {
                let stub = StubHTTPClient()
                stub.stub(pathSuffix: "/Items", requiring: [.init(name: "Limit", value: "0")],
                          json: #"{"Items":[{"Id":"z","Name":"Zulu","Type":"Movie"}],"TotalRecordCount":101}"#)
                stub.stub(pathSuffix: "/Items",
                          json: #"{"Items":[{"Id":"z","Name":"Zulu","Type":"Movie"},{"Id":"a","Name":"Alpha","Type":"Movie"}],"TotalRecordCount":101}"#)
                let provider = JellyfinProvider(session: makeSession(kind: kind), http: stub)
                let sort = CoreModels.SortDescriptor(field: .name, direction: direction)

                let entries = try await provider.letterIndex(in: "virtual", kind: .movie, sort: sort)

                XCTAssertTrue(entries.isEmpty)
                XCTAssertEqual(stub.sentPaths.count, 1, "Probe count-only support before the 27 letter requests")
                XCTAssertFalse(stub.sentQueryItems.flatMap { $0 }.contains {
                    $0.name == "NameLessThan" || $0.name == "NameStartsWith"
                })
                let page = try await provider.items(
                    in: "virtual", kind: .movie, page: .init(startIndex: 0, limit: 2, sort: sort)
                )
                XCTAssertEqual(page.items.map(\.id), ["z", "a"])
                XCTAssertEqual(page.totalCount, 101)
            }
        }
    }

    func testUnsupportedCountProbeRetainsFilteredLibraryScope() async throws {
        for kind in [ProviderKind.jellyfin, .emby] {
            let stub = StubHTTPClient()
            stub.stub(pathSuffix: "/Items",
                      json: #"{"Items":[{"Id":"a","Type":"Series"}],"TotalRecordCount":101}"#)
            let provider = JellyfinProvider(session: makeSession(kind: kind), http: stub)
            let entries = try await provider.libraryQueryLetterIndex(
                in: "tv", kind: .series,
                page: .init(startIndex: 0, limit: 10, sort: .default,
                            filters: .init(filter: .unwatched, genre: "Drama", year: 2025))
            )
            XCTAssertTrue(entries.isEmpty)
            XCTAssertEqual(stub.sentPaths.count, 1)
            let query = try XCTUnwrap(stub.sentQueryItems.first)
            for item in [
                URLQueryItem(name: "ParentId", value: "tv"),
                .init(name: "IncludeItemTypes", value: "Series"),
                .init(name: "Recursive", value: "true"),
                .init(name: "IsPlayed", value: "false"),
                .init(name: "Genres", value: "Drama"),
                .init(name: "Years", value: "2025"),
                .init(name: "Limit", value: "0")
            ] {
                XCTAssertTrue(query.contains(item))
            }
        }
    }

    func testUnsupportedProbeDoesNotPersistAcrossLibrariesOrRefreshes() async throws {
        let stub = StubHTTPClient()
        stub.stubSequence(pathSuffix: "/Items", jsons: [
            #"{"Items":[{"Id":"a","Type":"Movie"}],"TotalRecordCount":101}"#
        ])
        stub.stub(pathSuffix: "/Items", json: #"{"Items":[],"TotalRecordCount":0}"#)
        let provider = JellyfinProvider(session: makeSession(), http: stub)
        let unsupported = try await provider.letterIndex(in: "virtual", kind: .movie, sort: .default)
        XCTAssertTrue(unsupported.isEmpty)
        XCTAssertEqual(stub.sentPaths.count, 1)

        _ = try await provider.letterIndex(in: "native", kind: .movie, sort: .default)
        XCTAssertEqual(stub.sentPaths.count, 29, "Another library must still build its native index")
        _ = try await provider.letterIndex(in: "virtual", kind: .movie, sort: .default)
        XCTAssertEqual(stub.sentPaths.count, 57, "A refreshed endpoint must be allowed to recover support")
    }

    func testInvalidCountResponsesAreNotClassifiedAsUnsupported() async {
        for json in [
            #"{"Items":[]}"#,
            #"{"Items":[],"TotalRecordCount":-1}"#,
            #"{"Items":[{"Id":"a"}],"TotalRecordCount":-1}"#,
            #"{"Items":[{"Id":"a"}],"TotalRecordCount":0}"#,
            #"{"Items":[{"Id":"a"}]}"#,
            #"{"Items":[],"TotalRecordCount":"invalid"}"#
        ] {
            let stub = StubHTTPClient()
            stub.stub(pathSuffix: "/Items", json: json)
            let provider = JellyfinProvider(session: makeSession(), http: stub)
            do {
                _ = try await provider.letterIndex(in: "movies", kind: .movie, sort: .default)
                XCTFail("Invalid count data must remain an error")
            } catch {
                XCTAssertTrue((error as? AppError) == .invalidResponse || (error as? AppError) == .decoding)
            }
        }
    }

    func testCountProbeTransportAuthorizationAndCancellationFailuresRemainErrors() async {
        for failure in [AppError.serverUnreachable, .unauthorized, .cancelled] {
            let stub = StubHTTPClient()
            stub.error = failure
            let provider = JellyfinProvider(session: makeSession(), http: stub)
            do {
                _ = try await provider.letterIndex(in: "movies", kind: .movie, sort: .default)
                XCTFail("A failed request does not establish unsupported counting")
            } catch {
                XCTAssertEqual(error as? AppError, failure)
            }
        }
    }

    func testContradictoryNativeCountsRemainRetryableErrors() async {
        let stub = StubHTTPClient()
        stub.stub(pathSuffix: "/Items", requiring: [.init(name: "NameStartsWith", value: "Z")],
                  json: #"{"Items":[],"TotalRecordCount":2}"#)
        stub.stub(pathSuffix: "/Items", json: #"{"Items":[],"TotalRecordCount":5}"#)
        let provider = JellyfinProvider(session: makeSession(), http: stub)
        for _ in 0..<2 {
            do {
                _ = try await provider.letterIndex(in: "movies", kind: .movie, sort: .default)
                XCTFail("A supported count endpoint with contradictory offsets must fail")
            } catch {
                XCTAssertEqual(error as? AppError, .invalidResponse)
            }
        }
        XCTAssertEqual(stub.sentPaths.count, 56)
    }

    func testCancelledUnsupportedProbeCannotReturnAnEmptySuccess() async {
        let stub = StubHTTPClient()
        stub.stub(pathSuffix: "/Items",
                  json: #"{"Items":[{"Id":"a"}],"TotalRecordCount":101}"#)
        let provider = JellyfinProvider(session: makeSession(), http: stub)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await provider.letterIndex(in: "movies", kind: .movie, sort: .default)
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must not establish an unsupported capability")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected cancellation, got \(error)")
        }
    }

    func testInconsistentLetterResponseAfterSupportedProbeStillFails() async {
        let stub = StubHTTPClient()
        stub.stub(pathSuffix: "/Items", requiring: [.init(name: "NameLessThan", value: "A")],
                  json: #"{"Items":[{"Id":"a"}],"TotalRecordCount":5}"#)
        stub.stub(pathSuffix: "/Items", json: #"{"Items":[],"TotalRecordCount":0}"#)
        let provider = JellyfinProvider(session: makeSession(), http: stub)
        do {
            _ = try await provider.letterIndex(in: "movies", kind: .movie, sort: .default)
            XCTFail("Inconsistent native responses must not silently disable the index")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidResponse)
        }
    }

    func testBothProvidersResolveConcreteAscendingAndDescendingOffsets() async throws {
        for kind in [ProviderKind.jellyfin, .emby] {
            let provider = JellyfinProvider(session: makeSession(kind: kind), http: AlphabetCountHTTP())
            let ascending = try await provider.letterIndex(in: "lib", kind: .movie, sort: .default)
            XCTAssertEqual(ascending, [.init(letter: "#", startIndex: 0), .init(letter: "A", startIndex: 1),
                                       .init(letter: "M", startIndex: 3), .init(letter: "Z", startIndex: 4)])
            let descending = try await provider.letterIndex(in: "lib", kind: .movie,
                                                            sort: .init(field: .name, direction: .descending))
            XCTAssertEqual(descending, [.init(letter: "#", startIndex: 0), .init(letter: "Z", startIndex: 1),
                                        .init(letter: "M", startIndex: 2), .init(letter: "A", startIndex: 3)])
        }
    }

    private func makeSession(kind: ProviderKind = .jellyfin) -> UserSession {
        UserSession(
            server: MediaServer(id: "s", name: "Home", baseURL: URL(string: "http://host:8096")!, provider: kind),
            userID: "u1", userName: "Alice", deviceID: "d1", accessToken: "TOKEN"
        )
    }

    func testEmbySeriesCountsMatchLibraryScope() async throws {
        let stub = StubHTTPClient()
        stub.stub(pathSuffix: "/Items", json: #"{"Items":[],"TotalRecordCount":0}"#)
        let provider = JellyfinProvider(session: makeSession(kind: .emby), http: stub)
        _ = try await provider.letterIndex(in: "tv", kind: .series,
                                          sort: .init(field: .name, direction: .descending))
        XCTAssertEqual(stub.sentQueryItems.count, 28)
        for items in stub.sentQueryItems {
            XCTAssertTrue(items.contains(.init(name: "ParentId", value: "tv")))
            XCTAssertTrue(items.contains(.init(name: "IncludeItemTypes", value: "Series")))
            XCTAssertTrue(items.contains(.init(name: "Recursive", value: "true")))
            XCTAssertTrue(items.contains(.init(name: "Limit", value: "0")))
        }
        XCTAssertTrue(stub.sentPaths.allSatisfy { $0.hasSuffix("/Users/u1/Items") })
    }

    func testMissingCountIsNotSilentlyTreatedAsEmptyIndex() async {
        let stub = StubHTTPClient()
        stub.stub(pathSuffix: "/Items", json: #"{"Items":[]}"#)
        let provider = JellyfinProvider(session: makeSession(kind: .emby), http: stub)
        do {
            _ = try await provider.letterIndex(in: "movies", kind: .movie, sort: .default)
            XCTFail("Missing counts must allow the user to retry")
        } catch { XCTAssertEqual(error as? AppError, .invalidResponse) }
    }

    func testNameSortIssuesNameLessThanCountPerLetter() async throws {
        let stub = StubHTTPClient()
        stub.stub(pathSuffix: "/Items", json: #"{"Items":[],"TotalRecordCount":0}"#)
        let provider = JellyfinProvider(session: makeSession(), http: stub)

        _ = try await provider.letterIndex(
            in: "lib1", kind: .movie,
            sort: CoreModels.SortDescriptor(field: .name, direction: .ascending)
        )

        // Every letter A…Z must be probed with a NameLessThan count query.
        let nameLessThanValues = stub.sentQueryItems
            .compactMap { items in items.first(where: { $0.name == "NameLessThan" })?.value }
        let expected = (UnicodeScalar("A").value...UnicodeScalar("Z").value)
            .compactMap { UnicodeScalar($0).map(String.init) }
        XCTAssertEqual(Set(nameLessThanValues), Set(expected))
        XCTAssertEqual(nameLessThanValues.count, 26)

        // Plus exactly one total-count query (no NameLessThan) for the upper bound.
        let totalQueries = stub.sentQueryItems.filter { items in
            !items.contains(where: { $0.name == "NameLessThan" || $0.name == "NameStartsWith" })
        }
        XCTAssertEqual(totalQueries.count, 1)
        XCTAssertEqual(stub.sentQueryItems.filter {
            $0.contains(.init(name: "NameStartsWith", value: "Z"))
        }.count, 1, "Separate Z from a trailing non-Latin bucket")

        // Count queries must scope to the library and request no rows.
        for items in stub.sentQueryItems {
            XCTAssertTrue(items.contains(URLQueryItem(name: "ParentId", value: "lib1")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "Limit", value: "0")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "EnableTotalRecordCount", value: "true")))
        }
    }

    func testNonNameSortIssuesNoRequestsAndReturnsEmpty() async throws {
        let stub = StubHTTPClient()
        stub.stub(pathSuffix: "/Items", json: #"{"Items":[],"TotalRecordCount":50}"#)
        let provider = JellyfinProvider(session: makeSession(), http: stub)

        let entries = try await provider.letterIndex(
            in: "lib1", kind: .movie,
            sort: CoreModels.SortDescriptor(field: .dateAdded, direction: .descending)
        )
        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(stub.sentPaths.isEmpty, "Non-name sorts must not issue any count queries")
    }
}

private actor AlphabetCountHTTP: HTTPClient {
    let names: [String]

    init(names: [String] = ["123", "ALIEN", "ALIEN 3", "MATRIX", "ZULU", "映画"]) {
        self.names = names
    }

    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        let query = Dictionary(uniqueKeysWithValues: endpoint.queryItems.map { ($0.name, $0.value ?? "") })
        let count: Int
        if let prefix = query["NameStartsWith"] { count = names.filter { $0.hasPrefix(prefix) }.count }
        else if let upperBound = query["NameLessThan"] { count = names.filter { $0 < upperBound }.count }
        else { count = names.count }
        return (Data("{\"Items\":[],\"TotalRecordCount\":\(count)}".utf8),
                HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor CancelledAlphabetPredicateHTTP: HTTPClient {
    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        if endpoint.queryItems.contains(.init(name: "NameStartsWith", value: "Z")) {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return (
            Data(#"{"Items":[],"TotalRecordCount":10000}"#.utf8),
            HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}
