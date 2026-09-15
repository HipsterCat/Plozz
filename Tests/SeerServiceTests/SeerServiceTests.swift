import XCTest
import CoreModels
import CoreNetworking
@testable import SeerService

private let seerBaseURL = URL(string: "https://requests.example.com")!
private let seerServerIdentity = SeerServerIdentity(baseURL: seerBaseURL)!

// MARK: - Pure mapping tests

final class SeerMapperTests: XCTestCase {

    func testMovieResultMapsToMediaItem() {
        let result = SeerDiscoverResult(
            id: 550,
            mediaType: "movie",
            title: "Fight Club",
            originalTitle: "Fight Club",
            overview: "An insomniac…",
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            releaseDate: "1999-10-15",
            mediaInfo: SeerMediaInfo(status: 5)
        )

        let item = SeerMapper.mediaItem(from: result)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.id, "seer:movie:550")
        XCTAssertEqual(item?.title, "Fight Club")
        XCTAssertEqual(item?.kind, .movie)
        XCTAssertEqual(item?.productionYear, 1999)
        XCTAssertEqual(item?.providerIDs["Tmdb"], "550")
        XCTAssertEqual(item?.availability, .available)
        XCTAssertEqual(item?.posterURL?.absoluteString, "https://image.tmdb.org/t/p/w500/poster.jpg")
        XCTAssertEqual(item?.backdropURL?.absoluteString, "https://image.tmdb.org/t/p/w780/backdrop.jpg")
        XCTAssertEqual(item?.heroBackdropURL?.absoluteString, "https://image.tmdb.org/t/p/w1280/backdrop.jpg")
    }

    func testTVResultUsesNameAndFirstAirDate() {
        let result = SeerDiscoverResult(
            id: 1396,
            mediaType: "tv",
            name: "Breaking Bad",
            originalName: "Breaking Bad",
            firstAirDate: "2008-01-20",
            mediaInfo: SeerMediaInfo(status: 2)
        )

        let item = SeerMapper.mediaItem(from: result)
        XCTAssertEqual(item?.id, "seer:series:1396")
        XCTAssertEqual(item?.title, "Breaking Bad")
        XCTAssertEqual(item?.kind, .series)
        XCTAssertEqual(item?.productionYear, 2008)
        XCTAssertEqual(item?.availability, .pending)
    }

    func testPersonResultIsSkipped() {
        let result = SeerDiscoverResult(id: 1, mediaType: "person", name: "Some Actor")
        XCTAssertNil(SeerMapper.mediaItem(from: result))
    }

    func testMovieAndSeriesTMDBNamespacesProduceDistinctIDs() {
        let movie = SeerDiscoverResult(id: 42, mediaType: "movie", title: "Movie")
        let series = SeerDiscoverResult(id: 42, mediaType: "tv", name: "Series")

        XCTAssertEqual(SeerMapper.mediaItem(from: movie)?.id, "seer:movie:42")
        XCTAssertEqual(SeerMapper.mediaItem(from: series)?.id, "seer:series:42")
    }

    func testEmptyTitleIsSkipped() {
        let result = SeerDiscoverResult(id: 2, mediaType: "movie", title: "   ")
        XCTAssertNil(SeerMapper.mediaItem(from: result))
    }

    func testMissingMediaInfoMapsToUnknownAvailability() {
        // An untracked featured title (no mediaInfo) isn't owned and hasn't been
        // requested — the hero must offer Request, so availability defaults to
        // `.unknown` (requestable), never `nil` (which would read as a library item).
        let result = SeerDiscoverResult(id: 3, mediaType: "movie", title: "Untracked")
        XCTAssertEqual(SeerMapper.mediaItem(from: result)?.availability, .unknown)
    }

    func testAllStatusRawValuesMap() {
        let expected: [Int: MediaAvailabilityStatus] = [
            1: .unknown, 2: .pending, 3: .processing,
            4: .partiallyAvailable, 5: .available, 6: .deleted
        ]
        for (raw, status) in expected {
            let result = SeerDiscoverResult(id: raw, mediaType: "movie", title: "T", mediaInfo: SeerMediaInfo(status: raw))
            XCTAssertEqual(SeerMapper.mediaItem(from: result)?.availability, status, "raw \(raw)")
        }
    }

    func testImageURLNilForMissingPath() {
        XCTAssertNil(SeerMapper.imageURL(path: nil, size: "w500"))
        XCTAssertNil(SeerMapper.imageURL(path: "", size: "w500"))
    }

    func testImageURLNormalizesLeadingSlash() {
        XCTAssertEqual(
            SeerMapper.imageURL(path: "abc.jpg", size: "w342")?.absoluteString,
            "https://image.tmdb.org/t/p/w342/abc.jpg"
        )
    }

    func testYearParsing() {
        XCTAssertEqual(SeerMapper.year(from: "2021-06-01"), 2021)
        XCTAssertNil(SeerMapper.year(from: "bad"))
        XCTAssertNil(SeerMapper.year(from: nil))
    }

    func testRequestMediaTypeDerivation() {
        XCTAssertEqual(SeerMapper.requestMediaType(for: makeItem(kind: .movie)), "movie")
        XCTAssertEqual(SeerMapper.requestMediaType(for: makeItem(kind: .series)), "tv")
        XCTAssertNil(SeerMapper.requestMediaType(for: makeItem(kind: .episode)))
    }

    func testTMDBIDFromProviderIDsAndSyntheticID() {
        let fromProvider = makeItem(kind: .movie, id: "x", tmdb: "603")
        XCTAssertEqual(SeerMapper.tmdbID(for: fromProvider), 603)

        let fromSynthetic = MediaItem(id: "seer:604", title: "T", kind: .movie)
        XCTAssertEqual(SeerMapper.tmdbID(for: fromSynthetic), 604)
        let fromKindScopedSynthetic = MediaItem(id: "seer:series:605", title: "T", kind: .series)
        XCTAssertEqual(SeerMapper.tmdbID(for: fromKindScopedSynthetic), 605)

        let none = MediaItem(id: "jf:abc", title: "T", kind: .movie)
        XCTAssertNil(SeerMapper.tmdbID(for: none))
    }

    func testMediaItemsCapAndDropPeople() {
        let page = SeerDiscoverPage(page: 1, totalPages: 1, totalResults: 3, results: [
            SeerDiscoverResult(id: 1, mediaType: "movie", title: "A"),
            SeerDiscoverResult(id: 2, mediaType: "person", name: "P"),
            SeerDiscoverResult(id: 3, mediaType: "tv", name: "B"),
            SeerDiscoverResult(id: 4, mediaType: "movie", title: "C")
        ])
        let all = SeerMapper.mediaItems(from: page)
        XCTAssertEqual(all.map(\.id), ["seer:movie:1", "seer:series:3", "seer:movie:4"])
        let capped = SeerMapper.mediaItems(from: page, limit: 2)
        XCTAssertEqual(capped.map(\.id), ["seer:movie:1", "seer:series:3"])
    }

    func testRequestAvailabilityCombinesTrackedAndMissingSeasons() {
        let details = SeerMediaDetails(
            mediaInfo: SeerMediaInfo(
                status: 4,
                seasons: [
                    SeerMediaSeason(seasonNumber: 1, status: 5),
                    SeerMediaSeason(seasonNumber: 3, status: 2)
                ],
                requests: [
                    SeerMediaRequest(
                        status: 2,
                        seasons: [SeerRequestedSeason(seasonNumber: 2, status: 2)]
                    ),
                    SeerMediaRequest(
                        status: 4,
                        seasons: [SeerRequestedSeason(seasonNumber: 4, status: 2)]
                    )
                ]
            ),
            seasons: [
                SeerSeasonSummary(name: "Specials", seasonNumber: 0),
                SeerSeasonSummary(name: "The Beginning", seasonNumber: 1),
                SeerSeasonSummary(seasonNumber: 2),
                SeerSeasonSummary(seasonNumber: 3),
                SeerSeasonSummary(seasonNumber: 4)
            ]
        )

        let availability = SeerMapper.requestAvailability(from: details)

        XCTAssertEqual(availability.status, .partiallyAvailable)
        XCTAssertEqual(availability.seasons.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(availability.seasons.map(\.status), [.available, .processing, .pending, .pending])
        XCTAssertEqual(availability.seasons.map(\.requestFailed), [false, false, false, true])
        XCTAssertEqual(availability.seasons.map(\.requestStatus), [nil, .processing, nil, .failed])
        XCTAssertEqual(availability.seasons.map(\.title), ["The Beginning", "Season 2", "Season 3", "Season 4"])
        XCTAssertEqual(availability.requestableSeasonNumbers, [])
        XCTAssertEqual(availability.requestPickerSeasons.map(\.number), [2, 3, 4])
    }

    func testFailedParentDoesNotRegressAnExplicitlyCompletedSeason() {
        let details = SeerMediaDetails(
            mediaInfo: SeerMediaInfo(requests: [
                SeerMediaRequest(status: 4, seasons: [
                    SeerRequestedSeason(seasonNumber: 1, status: 5),
                    SeerRequestedSeason(seasonNumber: 2, status: 2),
                    SeerRequestedSeason(seasonNumber: 3, status: 4)
                ])
            ]),
            seasons: (1...3).map { SeerSeasonSummary(seasonNumber: $0) }
        )
        let availability = SeerMapper.requestAvailability(from: details)
        XCTAssertEqual(availability.seasons.map(\.requestStatus), [.completed, .failed, .failed])
        XCTAssertEqual(availability.seasons.map(\.requestFailed), [false, true, true])
        XCTAssertEqual(availability.requestableSeasonNumbers, [])
    }

    func testRequestAvailabilityDeduplicatesAndKeepsRequestedSeasonsMissingFromTMDBList() {
        let details = SeerMediaDetails(
            mediaInfo: SeerMediaInfo(
                seasons: [
                    SeerMediaSeason(seasonNumber: 1, status: 1),
                    SeerMediaSeason(seasonNumber: 1, status: 5),
                    SeerMediaSeason(seasonNumber: 2, status: 1)
                ],
                requests: [
                    SeerMediaRequest(
                        status: 2,
                        seasons: [
                            SeerRequestedSeason(seasonNumber: 2, status: 2),
                            SeerRequestedSeason(seasonNumber: 7, status: 2),
                            SeerRequestedSeason(seasonNumber: 7, status: 2)
                        ]
                    )
                ]
            ),
            seasons: [
                SeerSeasonSummary(seasonNumber: 1),
                SeerSeasonSummary(name: "First", seasonNumber: 1),
                SeerSeasonSummary(seasonNumber: 2)
            ]
        )

        let availability = SeerMapper.requestAvailability(from: details)

        XCTAssertEqual(availability.seasons.map(\.number), [1, 2, 7])
        XCTAssertEqual(availability.seasons.map(\.status), [.available, .processing, .processing])
        XCTAssertEqual(availability.seasons.map(\.requestStatus), [nil, .processing, .processing])
        XCTAssertEqual(availability.seasons.map(\.title), ["First", "Season 2", "Season 7"])
    }

    func testRequestAvailabilityIncludesEveryHouseholdRequestRecord() {
        let details = SeerMediaDetails(
            mediaInfo: SeerMediaInfo(
                requests: [
                    SeerMediaRequest(
                        status: 1,
                        seasons: [SeerRequestedSeason(seasonNumber: 2, status: 1)]
                    ),
                    SeerMediaRequest(
                        status: 2,
                        seasons: [SeerRequestedSeason(seasonNumber: 7, status: 2)]
                    )
                ]
            ),
            seasons: [
                SeerSeasonSummary(seasonNumber: 1),
                SeerSeasonSummary(seasonNumber: 2),
                SeerSeasonSummary(seasonNumber: 7)
            ]
        )

        let availability = SeerMapper.requestAvailability(from: details)

        XCTAssertEqual(availability.seasons.map(\.status), [.unknown, .pending, .processing])
        XCTAssertEqual(availability.requestableSeasonNumbers, [1])
    }

    func testRequestMetadataWinsOverStaleScannerWithoutMaskingFailures() {
        let details = SeerMediaDetails(
            mediaInfo: SeerMediaInfo(
                seasons: [
                    SeerMediaSeason(seasonNumber: 1, status: 1),
                    SeerMediaSeason(seasonNumber: 2, status: 2),
                    SeerMediaSeason(seasonNumber: 3, status: 3),
                    SeerMediaSeason(seasonNumber: 4, status: 5)
                ],
                requests: [
                    SeerMediaRequest(
                        status: 1,
                        seasons: [SeerRequestedSeason(seasonNumber: 1, status: 1)]
                    ),
                    SeerMediaRequest(
                        status: 4,
                        seasons: [
                            SeerRequestedSeason(seasonNumber: 2, status: 2),
                            SeerRequestedSeason(seasonNumber: 3, status: 2),
                            SeerRequestedSeason(seasonNumber: 4, status: 2)
                        ]
                    ),
                    SeerMediaRequest(
                        status: 2,
                        is4k: true,
                        seasons: [SeerRequestedSeason(seasonNumber: 5, status: 2)]
                    )
                ]
            ),
            seasons: (1...5).map { SeerSeasonSummary(seasonNumber: $0) }
        )

        let availability = SeerMapper.requestAvailability(from: details)

        XCTAssertEqual(availability.seasons.map(\.status), [
            .pending, .pending, .processing, .available, .unknown
        ])
        XCTAssertEqual(availability.seasons.map(\.requestStatus), [
            .pending, .failed, .failed, nil, nil
        ])
        XCTAssertEqual(availability.seasons.map(\.requestFailed), [
            false, true, true, false, false
        ])
        XCTAssertEqual(availability.requestableSeasonNumbers, [5])
    }

    func testPartialCoverageRetainsActiveWorkflowAndTerminalStatesBlockRequestAll() {
        let details = SeerMediaDetails(
            mediaInfo: SeerMediaInfo(
                seasons: [
                    SeerMediaSeason(seasonNumber: 1, status: 4)
                ],
                requests: [
                    SeerMediaRequest(
                        status: 2,
                        seasons: [SeerRequestedSeason(seasonNumber: 1, status: 2)]
                    ),
                    SeerMediaRequest(
                        status: 3,
                        seasons: [SeerRequestedSeason(seasonNumber: 2, status: 3)]
                    ),
                    SeerMediaRequest(
                        status: 5,
                        seasons: [SeerRequestedSeason(seasonNumber: 3, status: 5)]
                    )
                ]
            ),
            seasons: (1...4).map { SeerSeasonSummary(seasonNumber: $0) }
        )

        let availability = SeerMapper.requestAvailability(from: details)
        let partial = availability.seasons[0]

        XCTAssertEqual(partial.status, .partiallyAvailable)
        XCTAssertEqual(partial.requestStatus, .processing)
        XCTAssertTrue(partial.isInFlight)
        XCTAssertEqual(availability.seasons.map(\.requestStatus), [
            .processing, .declined, .completed, nil
        ])
        XCTAssertEqual(availability.requestableSeasonNumbers, [4])
    }

    private func makeItem(kind: MediaItemKind, id: String = "seer:1", tmdb: String? = nil) -> MediaItem {
        var ids: [String: String] = [:]
        if let tmdb { ids["Tmdb"] = tmdb }
        return MediaItem(id: id, title: "T", kind: kind, providerIDs: ids)
    }
}

// MARK: - Config tests

final class SeerConfigTests: XCTestCase {
    func testNormalizedBaseURLAddsSchemeAndStripsTrailingSlash() {
        // Scheme-less input defaults to **http** (self-hosted LAN servers are
        // virtually never TLS) plus Overseerr's default port 5055 — matching
        // `ServerURLNormalizer`'s Jellyfin behavior, just with a different
        // default port.
        XCTAssertEqual(SeerConfig.normalizedBaseURL(from: "requests.example.com")?.absoluteString, "http://requests.example.com:5055")
        XCTAssertEqual(SeerConfig.normalizedBaseURL(from: "192.168.68.71:5055")?.absoluteString, "http://192.168.68.71:5055")
        XCTAssertEqual(SeerConfig.normalizedBaseURL(from: "http://host:5055/")?.absoluteString, "http://host:5055")
        XCTAssertEqual(SeerConfig.normalizedBaseURL(from: "https://host/seerr/")?.absoluteString, "https://host/seerr")
    }

    func testNormalizedBaseURLRejectsEmpty() {
        XCTAssertNil(SeerConfig.normalizedBaseURL(from: "   "))
    }

    func testIsConfiguredRequiresBoth() {
        XCTAssertFalse(SeerConfig(baseURL: seerBaseURL).isConfigured)
        XCTAssertFalse(SeerConfig(apiKey: "k").isConfigured)
        XCTAssertTrue(SeerConfig(baseURL: seerBaseURL, apiKey: "k").isConfigured)
    }

    func testBlankAPIKeyIsSanitizedToNil() {
        XCTAssertNil(SeerConfig(baseURL: seerBaseURL, apiKey: "   ").apiKey)
    }
}

// MARK: - Service tests

@MainActor
final class SeerServiceTests: XCTestCase {

    private func makeConnectedService(_ http: SeerRecordingHTTPClient) -> SeerService {
        let store = InMemorySeerConnectionStore(
            connection: SeerConnection(baseURL: seerBaseURL, apiKey: "KEY")
        )
        return SeerService(connectionStore: store, http: http)
    }

    func testTrendingMapsAndCaps() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/discover/trending", json: """
        {"page":1,"totalPages":1,"totalResults":3,"results":[
          {"id":10,"mediaType":"movie","title":"M","posterPath":"/p.jpg","mediaInfo":{"status":5}},
          {"id":11,"mediaType":"person","name":"P"},
          {"id":12,"mediaType":"tv","name":"S"}
        ]}
        """)
        let service = makeConnectedService(http)
        let items = try await service.trending(limit: 5)
        XCTAssertEqual(items.map(\.id), ["seer:movie:10", "seer:series:12"])
        XCTAssertEqual(items.first?.availability, .available)
        // Auth header injected; browse runs as ADMIN (no X-API-User).
        let sent = http.lastSent(pathSuffix: "/discover/trending")
        XCTAssertEqual(sent?.headers["X-Api-Key"], "KEY")
        XCTAssertNil(sent?.headers["X-API-User"], "Browse calls run as admin")
    }

    func testTrendingEmptyWhenUnconfigured() async throws {
        let http = SeerRecordingHTTPClient()
        let service = SeerService(connectionStore: InMemorySeerConnectionStore(), http: http)
        let items = try await service.trending(limit: 5)
        XCTAssertTrue(items.isEmpty)
        XCTAssertTrue(http.sentPaths.isEmpty)
    }

    // MARK: - Users

    func testUsersFetchesAllPagesSortedByName() async throws {
        let http = SeerRecordingHTTPClient()
        // Two pages (take=100 each). First page full-ish, second short → stop.
        // The stub matches on path suffix only, so both /user calls return this
        // page; assert the merge + sort, and that pagination terminates.
        http.stub(pathSuffix: "/user", json: """
        {"pageInfo":{"pages":1,"page":1,"results":2},"results":[
          {"id":3,"displayName":"Zoe","email":"z@x.com"},
          {"id":1,"displayName":"Amy","plexUsername":"amy"}
        ]}
        """)
        let service = makeConnectedService(http)
        let users = try await service.users()
        XCTAssertEqual(users.map(\.name), ["Amy", "Zoe"], "Sorted by display name")
        XCTAssertEqual(users.map(\.id), [1, 3])
        XCTAssertTrue(users.allSatisfy { $0.serverIdentity == seerServerIdentity })
        // Admin identity for the user list.
        XCTAssertNil(http.lastSent(pathSuffix: "/user")?.headers["X-API-User"])
    }

    func testUsersRejectsPagedResultAfterConnectionRevisionChanges() async throws {
        let http = SeerRecordingHTTPClient()
        let firstPage = (1...100)
            .map { #"{"id":\#($0),"displayName":"User \#($0)"}"# }
            .joined(separator: ",")
        http.stub(
            pathSuffix: "/user",
            json: #"{"pageInfo":{"results":101},"results":[\#(firstPage)]}"#
        )
        http.enqueueStub(
            pathSuffix: "/user",
            json: #"{"pageInfo":{"results":101},"results":[{"id":101,"displayName":"Last"}]}"#
        )
        http.stub(pathSuffix: "/status", json: #"{"version":"2.0"}"#)
        http.suspend(pathSuffix: "/user", onRequestNumber: 2)
        let store = InMemorySeerConnectionStore(
            connection: SeerConnection(baseURL: seerBaseURL, apiKey: "KEY")
        )
        let service = SeerService(connectionStore: store, http: http)

        let fetch = Task { try await service.users() }
        await http.waitUntilSuspended(pathSuffix: "/user")
        try store.save(
            SeerConnection(baseURL: URL(string: "https://new.example.com")!, apiKey: "NEW")
        )
        await service.reloadConnection()
        http.resume(pathSuffix: "/user")

        do {
            _ = try await fetch.value
            XCTFail("Expected stale paged user fetch to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - availability(for:) — discovery detail refresh

    func testAvailabilityFetchesMovieStatusAndDownloadProgress() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/movie/550", json: """
        {"id":550,"mediaInfo":{"status":3,"downloadStatus":[{"size":100,"sizeLeft":40}]}}
        """)
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:550", title: "Fight Club", kind: .movie, providerIDs: ["Tmdb": "550"])

        let result = await service.availability(for: item)

        XCTAssertEqual(result?.0, .processing)
        XCTAssertEqual(result?.1 ?? 0, 0.6, accuracy: 0.0001, "(100-40)/100 fetched fraction")
        let sent = http.lastSent(pathSuffix: "/movie/550")
        XCTAssertEqual(sent?.headers["X-Api-Key"], "KEY", "Admin key is sent")
    }

    func testAvailabilityUsesTvEndpointForSeries() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/tv/1396", json: #"{"id":1396,"mediaInfo":{"status":2}}"#)
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:1396", title: "Breaking Bad", kind: .series, providerIDs: ["Tmdb": "1396"])

        let result = await service.availability(for: item)

        XCTAssertEqual(result?.0, .pending)
        XCTAssertNil(result?.1, "No download queue -> no progress")
        XCTAssertNotNil(http.lastSent(pathSuffix: "/tv/1396"), "Series uses the /tv/{id} endpoint")
    }

    func testRequestAvailabilityDecodesSeriesSeasonCoverage() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/tv/1396", json: """
        {
          "id": 1396,
          "seasons": [
            {"name":"Specials","seasonNumber":0},
            {"name":"Season 1","seasonNumber":1},
            {"name":"Season 2","seasonNumber":2},
            {"name":"Season 3","seasonNumber":3}
          ],
          "mediaInfo": {
            "status": 4,
            "seasons": [{"seasonNumber":1,"status":5}],
            "requests": [
              {
                "status": 2,
                "is4k": false,
                "seasons": [{"seasonNumber":2,"status":2}]
              }
            ]
          }
        }
        """)
        let service = makeConnectedService(http)
        let item = MediaItem(id: "library:1396", title: "Breaking Bad", kind: .series, providerIDs: ["Tmdb": "1396"])

        let result = await service.requestAvailability(for: item)

        XCTAssertEqual(result?.status, .partiallyAvailable)
        XCTAssertEqual(result?.seasons.map(\.number), [1, 2, 3])
        XCTAssertEqual(result?.seasons.map(\.status), [.available, .processing, .unknown])
        XCTAssertEqual(result?.requestableSeasonNumbers, [3])
    }

    func testRequestAvailabilityRejectsStaleCompletionAfterReconnect() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(
            pathSuffix: "/tv/1396",
            json: #"{"id":1396,"seasons":[{"seasonNumber":1}],"mediaInfo":{"status":2}}"#
        )
        http.stub(pathSuffix: "/status", json: #"{"version":"2.0"}"#)
        http.suspend(pathSuffix: "/tv/1396")
        let store = InMemorySeerConnectionStore(
            connection: SeerConnection(baseURL: seerBaseURL, apiKey: "KEY")
        )
        let service = SeerService(connectionStore: store, http: http)
        let item = MediaItem(
            id: "seer:1396",
            title: "Breaking Bad",
            kind: .series,
            providerIDs: ["Tmdb": "1396"]
        )

        let fetch = Task { await service.requestAvailability(for: item) }
        await http.waitUntilSuspended(pathSuffix: "/tv/1396")
        try store.save(
            SeerConnection(baseURL: URL(string: "https://new.example.com")!, apiKey: "NEW")
        )
        await service.reloadConnection()
        http.resume(pathSuffix: "/tv/1396")

        let result = await fetch.value
        XCTAssertNil(result)
    }

    // MARK: - Season episode roster

    func testSeasonEpisodeRosterUsesAuthenticatedLocalizedReverseProxyEndpoint() async {
        let baseURL = URL(string: "https://requests.example.com/seerr")!
        let http = SeerRecordingHTTPClient()
        http.stub(
            pathSuffix: "/tv/1396/season/2",
            json: """
            {
              "seasonNumber": 2,
              "episodes": [
                {
                  "id": 62085,
                  "name": "Seven Thirty-Seven",
                  "airDate": "2009-03-08",
                  "episodeNumber": 1,
                  "seasonNumber": 2,
                  "stillPath": "/episode.jpg"
                },
                {
                  "id": 62086,
                  "name": "Future Episode",
                  "airDate": "2099-12-31",
                  "episodeNumber": 2,
                  "seasonNumber": 2,
                  "stillPath": null
                },
                {
                  "id": 62087,
                  "episodeNumber": 3,
                  "seasonNumber": 2
                }
              ]
            }
            """
        )
        let service = SeerService(
            connectionStore: InMemorySeerConnectionStore(
                connection: SeerConnection(baseURL: baseURL, apiKey: "KEY")
            ),
            http: http
        )
        let item = MediaItem(
            id: "library:1396",
            title: "Breaking Bad",
            kind: .series,
            providerIDs: ["Tmdb": "1396"]
        )

        let result = await service.seasonEpisodeRoster(for: item, seasonNumber: 2)

        guard case let .loaded(roster) = result else {
            return XCTFail("Expected complete roster, got \(result)")
        }
        XCTAssertEqual(roster.seriesTMDbID, 1396)
        XCTAssertEqual(roster.seasonNumber, 2)
        XCTAssertEqual(roster.episodes.map(\.id), [62085, 62086, 62087])
        XCTAssertEqual(roster.episodes.map(\.episodeNumber), [1, 2, 3])
        XCTAssertEqual(roster.episodes.map(\.title), ["Seven Thirty-Seven", "Future Episode", nil])
        XCTAssertEqual(
            roster.episodes[0].airDate,
            MediaItem.calendarDayReleaseDate(from: "2009-03-08")
        )
        XCTAssertEqual(
            roster.episodes[1].airDate,
            MediaItem.calendarDayReleaseDate(from: "2099-12-31")
        )
        XCTAssertNil(roster.episodes[2].airDate)
        XCTAssertEqual(
            roster.episodes[0].stillURL?.absoluteString,
            "https://image.tmdb.org/t/p/w500/episode.jpg"
        )
        XCTAssertNil(roster.episodes[1].stillURL)

        let sent = http.lastSent(pathSuffix: "/tv/1396/season/2")
        XCTAssertEqual(sent?.baseURL, baseURL, "Reverse-proxy base path stays on the base URL")
        XCTAssertEqual(sent?.path, "/api/v1/tv/1396/season/2")
        XCTAssertEqual(sent?.queryItems.count, 1)
        XCTAssertEqual(sent?.queryItems.first?.name, "language")
        XCTAssertEqual(sent?.queryItems.first?.value, "en")
        XCTAssertEqual(sent?.headers["X-Api-Key"], "KEY")
        XCTAssertNil(sent?.headers["X-API-User"], "Metadata reads run as admin")
        XCTAssertNil(sent?.body, "GET season metadata has no request body")
    }

    func testSeasonEpisodeRosterAllowsExplicitEmptyEpisodeListAndSeasonZero() async {
        let http = SeerRecordingHTTPClient()
        http.stub(
            pathSuffix: "/tv/1396/season/0",
            json: #"{"seasonNumber":0,"episodes":[]}"#
        )
        let service = makeConnectedService(http)
        let item = MediaItem(
            id: "library:1396",
            title: "Breaking Bad",
            kind: .series,
            providerIDs: ["Tmdb": "1396"]
        )

        let result = await service.seasonEpisodeRoster(for: item, seasonNumber: 0)

        XCTAssertEqual(
            result,
            .loaded(
                SeasonEpisodeRoster(
                    seriesTMDbID: 1396,
                    seasonNumber: 0,
                    episodes: []
                )
            )
        )
    }

    func testSeasonEpisodeRosterTreatsBlankAirDatesAsUnknown() async {
        let http = SeerRecordingHTTPClient()
        http.stub(
            pathSuffix: "/tv/1396/season/1",
            json: """
            {"seasonNumber":1,"episodes":[
                {"id":10,"episodeNumber":1,"seasonNumber":1,"airDate":""},
                {"id":11,"episodeNumber":2,"seasonNumber":1,"airDate":"   "}
            ]}
            """
        )
        let service = makeConnectedService(http)
        let item = MediaItem(
            id: "series", title: "Series", kind: .series, providerIDs: ["Tmdb": "1396"]
        )
        let result = await service.seasonEpisodeRoster(for: item, seasonNumber: 1)
        guard case .loaded(let roster) = result else {
            return XCTFail("Blank optional dates must not discard the episode roster")
        }
        XCTAssertEqual(roster.episodes.count, 2)
        XCTAssertTrue(roster.episodes.allSatisfy { $0.airDate == nil })
    }

    func testSeasonEpisodeRosterFailsWhenEpisodeListIsAbsentOrMalformed() async {
        let http = SeerRecordingHTTPClient()
        http.enqueueStub(
            pathSuffix: "/tv/1396/season/1",
            json: #"{"seasonNumber":1}"#
        )
        http.enqueueStub(
            pathSuffix: "/tv/1396/season/1",
            json: """
            {
              "seasonNumber": 1,
              "episodes": [
                {"id":10,"episodeNumber":"one","seasonNumber":1}
              ]
            }
            """
        )
        let service = makeConnectedService(http)
        let item = MediaItem(
            id: "library:1396",
            title: "Breaking Bad",
            kind: .series,
            providerIDs: ["Tmdb": "1396"]
        )

        let absent = await service.seasonEpisodeRoster(for: item, seasonNumber: 1)
        let malformed = await service.seasonEpisodeRoster(for: item, seasonNumber: 1)

        XCTAssertEqual(absent, .failed)
        XCTAssertEqual(malformed, .failed)
    }

    func testSeasonEpisodeRosterFailsForInvalidOrConflictingEpisodeCoordinates() async {
        let http = SeerRecordingHTTPClient()
        http.enqueueStub(
            pathSuffix: "/tv/1396/season/1",
            json: """
            {
              "seasonNumber": 1,
              "episodes": [
                {"id":10,"episodeNumber":1,"seasonNumber":1},
                {"id":11,"episodeNumber":1,"seasonNumber":1}
              ]
            }
            """
        )
        http.enqueueStub(
            pathSuffix: "/tv/1396/season/1",
            json: """
            {
              "seasonNumber": 1,
              "episodes": [
                {"id":10,"episodeNumber":0,"seasonNumber":1}
              ]
            }
            """
        )
        http.enqueueStub(
            pathSuffix: "/tv/1396/season/1",
            json: """
            {
              "seasonNumber": 1,
              "episodes": [
                {"id":10,"episodeNumber":1,"seasonNumber":2}
              ]
            }
            """
        )
        http.enqueueStub(
            pathSuffix: "/tv/1396/season/1",
            json: """
            {
              "seasonNumber": 2,
              "episodes": [
                {"id":10,"episodeNumber":1,"seasonNumber":2}
              ]
            }
            """
        )
        let service = makeConnectedService(http)
        let item = MediaItem(
            id: "library:1396",
            title: "Breaking Bad",
            kind: .series,
            providerIDs: ["Tmdb": "1396"]
        )

        var results: [SeasonEpisodeRosterResult] = []
        for _ in 0..<4 {
            results.append(
                await service.seasonEpisodeRoster(for: item, seasonNumber: 1)
            )
        }
        XCTAssertEqual(results, [.failed, .failed, .failed, .failed])
    }

    func testSeasonEpisodeRosterUnavailableForDisconnectedInvalidOrUnsupportedInputs() async {
        let http = SeerRecordingHTTPClient()
        let disconnected = SeerService(
            connectionStore: InMemorySeerConnectionStore(),
            http: http
        )
        let connected = makeConnectedService(http)
        let series = MediaItem(
            id: "library:series",
            title: "Series",
            kind: .series,
            providerIDs: ["Tmdb": "1396"]
        )

        let disconnectedResult = await disconnected.seasonEpisodeRoster(
            for: series,
            seasonNumber: 1
        )
        let unsupportedKind = await connected.seasonEpisodeRoster(
            for: MediaItem(id: "movie", title: "Movie", kind: .movie, providerIDs: ["Tmdb": "550"]),
            seasonNumber: 1
        )
        let missingIdentity = await connected.seasonEpisodeRoster(
            for: MediaItem(id: "series", title: "Series", kind: .series),
            seasonNumber: 1
        )
        let invalidIdentity = await connected.seasonEpisodeRoster(
            for: MediaItem(id: "series", title: "Series", kind: .series, providerIDs: ["Tmdb": "0"]),
            seasonNumber: 1
        )
        let invalidSeason = await connected.seasonEpisodeRoster(
            for: series,
            seasonNumber: -1
        )

        XCTAssertEqual(disconnectedResult, .unavailable)
        XCTAssertEqual(unsupportedKind, .unavailable)
        XCTAssertEqual(missingIdentity, .unavailable)
        XCTAssertEqual(invalidIdentity, .unavailable)
        XCTAssertEqual(invalidSeason, .unavailable)
        XCTAssertTrue(http.sentPaths.isEmpty)
    }

    func testSeasonEpisodeRosterMapsNetworkAndDecodeFailuresToFailed() async {
        let http = SeerRecordingHTTPClient()
        http.error = .serverUnreachable
        let service = makeConnectedService(http)
        let item = MediaItem(
            id: "library:1396",
            title: "Breaking Bad",
            kind: .series,
            providerIDs: ["Tmdb": "1396"]
        )

        let result = await service.seasonEpisodeRoster(for: item, seasonNumber: 1)

        XCTAssertEqual(result, .failed)
    }

    func testSeasonEpisodeRosterRejectsLateCompletionAfterReconnect() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(
            pathSuffix: "/tv/1396/season/1",
            json: #"{"seasonNumber":1,"episodes":[{"id":10,"episodeNumber":1,"seasonNumber":1}]}"#
        )
        http.stub(pathSuffix: "/status", json: #"{"version":"2.0"}"#)
        http.suspend(pathSuffix: "/tv/1396/season/1")
        let store = InMemorySeerConnectionStore(
            connection: SeerConnection(baseURL: seerBaseURL, apiKey: "KEY")
        )
        let service = SeerService(connectionStore: store, http: http)
        let item = MediaItem(
            id: "library:1396",
            title: "Breaking Bad",
            kind: .series,
            providerIDs: ["Tmdb": "1396"]
        )

        let fetch = Task {
            await service.seasonEpisodeRoster(for: item, seasonNumber: 1)
        }
        await http.waitUntilSuspended(pathSuffix: "/tv/1396/season/1")
        try store.save(
            SeerConnection(baseURL: URL(string: "https://new.example.com")!, apiKey: "NEW")
        )
        await service.reloadConnection()
        http.resume(pathSuffix: "/tv/1396/season/1")

        let result = await fetch.value
        XCTAssertEqual(result, .unavailable)
    }

    func testSeasonEpisodeRosterRejectsLateCompletionAfterDisconnect() async {
        let http = SeerRecordingHTTPClient()
        http.stub(
            pathSuffix: "/tv/1396/season/1",
            json: #"{"seasonNumber":1,"episodes":[{"id":10,"episodeNumber":1,"seasonNumber":1}]}"#
        )
        http.suspend(pathSuffix: "/tv/1396/season/1")
        let service = makeConnectedService(http)
        let item = MediaItem(
            id: "library:1396",
            title: "Breaking Bad",
            kind: .series,
            providerIDs: ["Tmdb": "1396"]
        )

        let fetch = Task {
            await service.seasonEpisodeRoster(for: item, seasonNumber: 1)
        }
        await http.waitUntilSuspended(pathSuffix: "/tv/1396/season/1")
        service.disconnect()
        http.resume(pathSuffix: "/tv/1396/season/1")

        let result = await fetch.value
        XCTAssertEqual(result, .unavailable)
    }

    func testSeasonEpisodeRosterRejectsCompletionAfterCancellation() async {
        let http = SeerRecordingHTTPClient()
        http.stub(
            pathSuffix: "/tv/1396/season/1",
            json: #"{"seasonNumber":1,"episodes":[{"id":10,"episodeNumber":1,"seasonNumber":1}]}"#
        )
        http.suspend(pathSuffix: "/tv/1396/season/1")
        let service = makeConnectedService(http)
        let item = MediaItem(
            id: "library:1396",
            title: "Breaking Bad",
            kind: .series,
            providerIDs: ["Tmdb": "1396"]
        )

        let fetch = Task {
            await service.seasonEpisodeRoster(for: item, seasonNumber: 1)
        }
        await http.waitUntilSuspended(pathSuffix: "/tv/1396/season/1")
        fetch.cancel()
        http.resume(pathSuffix: "/tv/1396/season/1")

        let result = await fetch.value
        XCTAssertEqual(result, .unavailable)
    }

    // MARK: - Management URL

    func testMediaManagementURLUsesOfficialRoutesAndPreservesReverseProxyPath() {
        let baseURL = URL(string: "https://requests.example.com/seerr")!
        let service = SeerService(
            connectionStore: InMemorySeerConnectionStore(
                connection: SeerConnection(baseURL: baseURL, apiKey: "KEY")
            ),
            http: SeerRecordingHTTPClient()
        )

        XCTAssertEqual(
            service.mediaManagementURL(
                for: MediaItem(
                    id: "series",
                    title: "Series",
                    kind: .series,
                    providerIDs: ["Tmdb": "1396"]
                )
            )?.absoluteString,
            "https://requests.example.com/seerr/tv/1396"
        )
        XCTAssertEqual(
            service.mediaManagementURL(
                for: MediaItem(
                    id: "movie",
                    title: "Movie",
                    kind: .movie,
                    providerIDs: ["Tmdb": "550"]
                )
            )?.absoluteString,
            "https://requests.example.com/seerr/movie/550"
        )
    }

    func testMediaManagementURLStripsCredentialsQueryAndFragment() {
        let unsafeURL = URL(
            string: "https://viewer:password@requests.example.com/seerr/?api_key=SECRET#user-9"
        )!
        let service = SeerService(
            connectionStore: InMemorySeerConnectionStore(
                connection: SeerConnection(baseURL: unsafeURL, apiKey: "KEY")
            ),
            http: SeerRecordingHTTPClient()
        )
        let item = MediaItem(
            id: "series",
            title: "Series",
            kind: .series,
            providerIDs: ["Tmdb": "1396"]
        )

        XCTAssertEqual(
            service.mediaManagementURL(for: item)?.absoluteString,
            "https://requests.example.com/seerr/tv/1396"
        )
    }

    func testMediaManagementURLRejectsUnsupportedOrUnsafeInputs() {
        let service = makeConnectedService(SeerRecordingHTTPClient())
        let invalidSchemeService = SeerService(
            connectionStore: InMemorySeerConnectionStore(
                connection: SeerConnection(
                    baseURL: URL(string: "ftp://requests.example.com/seerr")!,
                    apiKey: "KEY"
                )
            ),
            http: SeerRecordingHTTPClient()
        )

        XCTAssertNil(
            service.mediaManagementURL(
                for: MediaItem(id: "episode", title: "Episode", kind: .episode, providerIDs: ["Tmdb": "10"])
            )
        )
        XCTAssertNil(
            service.mediaManagementURL(
                for: MediaItem(id: "series", title: "Series", kind: .series, providerIDs: ["Tmdb": "0"])
            )
        )
        XCTAssertNil(
            invalidSchemeService.mediaManagementURL(
                for: MediaItem(id: "series", title: "Series", kind: .series, providerIDs: ["Tmdb": "1396"])
            )
        )
    }

    func testAvailabilityIsUnknownForUntrackedTitle() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/movie/777", json: #"{"id":777}"#)
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:777", title: "Untracked", kind: .movie, providerIDs: ["Tmdb": "777"])

        let result = await service.availability(for: item)

        XCTAssertEqual(result?.0, .unknown)
        XCTAssertNil(result?.1)
    }

    func testAvailabilityNilWhenUnconfigured() async throws {
        let http = SeerRecordingHTTPClient()
        let service = SeerService(connectionStore: InMemorySeerConnectionStore(), http: http)
        let item = MediaItem(id: "seer:1", title: "X", kind: .movie, providerIDs: ["Tmdb": "1"])

        let result = await service.availability(for: item)

        XCTAssertNil(result)
        XCTAssertTrue(http.sentPaths.isEmpty, "No network when Seerr isn't configured")
    }

    // MARK: - Requests (admin path seeds defaults)

    func testMovieRequestAsAdminBuildsBodyWithRadarrDefaults() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/service/radarr", json: """
        [{"id":1,"name":"Main","is4k":false,"isDefault":true,"activeDirectory":"/movies","activeProfileId":4}]
        """)
        http.stub(pathSuffix: "/request", json: """
        {"id":42,"media":{"tmdbId":550,"status":2}}
        """, status: 201)

        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:550", title: "Fight Club", kind: .movie, providerIDs: ["Tmdb": "550"])
        let outcome = await service.request(item)

        XCTAssertEqual(outcome, .success(.pending))
        let sent = http.lastSent(pathSuffix: "/request")
        XCTAssertNil(sent?.headers["X-API-User"], "Admin request omits X-API-User")
        let body = sent?.json
        XCTAssertEqual(body?["mediaType"] as? String, "movie")
        XCTAssertEqual(body?["mediaId"] as? Int, 550)
        XCTAssertEqual(body?["serverId"] as? Int, 1)
        XCTAssertEqual(body?["profileId"] as? Int, 4)
        XCTAssertEqual(body?["rootFolder"] as? String, "/movies")
        XCTAssertNil(body?["seasons"])
    }

    func testRequestAsMappedUserSendsHeaderAndOmitsServerDefaults() async throws {
        let http = SeerRecordingHTTPClient()
        // Even if a radarr default exists, a mapped user must NOT seed it — let
        // Overseerr apply that user's own defaults.
        http.stub(pathSuffix: "/service/radarr", json: """
        [{"id":1,"isDefault":true,"activeDirectory":"/movies","activeProfileId":4}]
        """)
        http.stub(pathSuffix: "/request", json: #"{"id":42,"media":{"tmdbId":550,"status":2}}"#, status: 201)

        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:550", title: "Fight Club", kind: .movie, providerIDs: ["Tmdb": "550"])
        let outcome = await service.request(
            item,
            identity: .user(id: 9, server: seerServerIdentity)
        )

        XCTAssertEqual(outcome, .success(.pending))
        let sent = http.lastSent(pathSuffix: "/request")
        XCTAssertEqual(sent?.headers["X-API-User"], "9", "Requests as the mapped user")
        let body = sent?.json
        XCTAssertNil(body?["serverId"], "Mapped user omits server so Overseerr uses their default")
        XCTAssertNil(body?["profileId"])
        XCTAssertNil(body?["rootFolder"])
        // The admin radarr-default lookup should NOT even be attempted for a mapped user.
        XCTAssertTrue(http.sentPaths.filter { $0.hasSuffix("/service/radarr") }.isEmpty)
    }

    func testMappedUserRemainsValidAfterSameEndpointKeyRotation() async {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/status", json: #"{"version":"2.0"}"#)
        http.stub(pathSuffix: "/request", json: #"{"id":42,"media":{"tmdbId":550,"status":2}}"#, status: 201)
        let currentURL = URL(string: "https://REQUESTS.example.com:443/seerr/")!
        let boundIdentity = SeerServerIdentity(baseURL: URL(string: "https://requests.example.com/seerr")!)!
        let store = InMemorySeerConnectionStore(
            connection: SeerConnection(baseURL: currentURL, apiKey: "OLD")
        )
        let service = SeerService(connectionStore: store, http: http)
        let item = MediaItem(id: "seer:550", title: "Fight Club", kind: .movie, providerIDs: ["Tmdb": "550"])

        await service.connect(baseURL: currentURL, apiKey: "ROTATED")
        let outcome = await service.request(
            item,
            identity: .user(id: 9, server: boundIdentity)
        )

        XCTAssertEqual(outcome, .success(.pending))
        XCTAssertEqual(http.lastSent(pathSuffix: "/request")?.headers["X-API-User"], "9")
    }

    func testMappedUserFromDifferentEndpointFailsWithoutNetwork() async {
        let http = SeerRecordingHTTPClient()
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:550", title: "Fight Club", kind: .movie, providerIDs: ["Tmdb": "550"])
        let otherServer = SeerServerIdentity(baseURL: URL(string: "https://other.example.com")!)!

        let outcome = await service.request(
            item,
            identity: .user(id: 9, server: otherServer)
        )

        XCTAssertEqual(outcome, .failure(.mappingNeedsRelink))
        XCTAssertTrue(http.sentPaths.isEmpty)
    }

    func testProfileBindingSurvivesDisconnectRelaunchAndReturnToOriginalServer() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/status", json: #"{"version":"2.0"}"#)
        http.stub(pathSuffix: "/request", json: #"{"id":42,"media":{"status":2}}"#, status: 201)
        let store = InMemorySeerConnectionStore(
            connection: SeerConnection(baseURL: seerBaseURL, apiKey: "OLD")
        )
        let profile = Profile(name: "Dad").settingSeerrUser(
            id: 9, name: "Dad", serverIdentity: seerServerIdentity
        )
        let savedProfile = try JSONEncoder().encode(profile)
        let originalService = SeerService(connectionStore: store, http: http)
        originalService.disconnect()

        let service = SeerService(connectionStore: store, http: http)
        let restoredProfile = try JSONDecoder().decode(Profile.self, from: savedProfile)
        let item = MediaItem(id: "seer:550", title: "Fight Club", kind: .movie, providerIDs: ["Tmdb": "550"])
        let otherURL = URL(string: "https://other.example.com")!
        await service.connect(baseURL: otherURL, apiKey: "OTHER")
        let callsBeforeRequest = http.sentPaths.count
        let staleOutcome = await service.request(item, identity: restoredProfile.seerrRequestIdentity)
        XCTAssertEqual(staleOutcome, .failure(.mappingNeedsRelink))
        XCTAssertEqual(http.sentPaths.count, callsBeforeRequest, "No request or admin fallback on the other server")

        service.disconnect()
        await service.connect(baseURL: seerBaseURL, apiKey: "ROTATED")
        let restoredOutcome = await service.request(item, identity: restoredProfile.seerrRequestIdentity)
        XCTAssertEqual(restoredOutcome, .success(.pending))
        XCTAssertEqual(http.lastSent(pathSuffix: "/request")?.baseURL, seerBaseURL)
        XCTAssertEqual(http.lastSent(pathSuffix: "/request")?.headers["X-API-User"], "9")
        XCTAssertEqual(http.lastSent(pathSuffix: "/request")?.headers["X-Api-Key"], "ROTATED")
    }

    func testLegacyMappedUserFailsWithoutNetwork() async {
        let http = SeerRecordingHTTPClient()
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:550", title: "Fight Club", kind: .movie, providerIDs: ["Tmdb": "550"])

        let outcome = await service.request(
            item,
            identity: .user(id: 9, server: nil)
        )

        XCTAssertEqual(outcome, .failure(.mappingNeedsRelink))
        XCTAssertTrue(http.sentPaths.isEmpty)
    }

    func testKidsGateRefusesAdminButMismatchedUserStillNeedsRelink() async {
        let http = SeerRecordingHTTPClient()
        let service = makeConnectedService(http)
        service.refusesAdminRequests = { true }
        let item = MediaItem(id: "seer:550", title: "Fight Club", kind: .movie, providerIDs: ["Tmdb": "550"])

        let adminOutcome = await service.request(item, identity: .admin)
        let mappedOutcome = await service.request(
            item,
            identity: .user(
                id: 9,
                server: SeerServerIdentity(baseURL: URL(string: "https://other.example.com")!)
            )
        )

        XCTAssertEqual(adminOutcome, .failure(.unknown("Ask a grown-up to request this.")))
        XCTAssertEqual(mappedOutcome, .failure(.mappingNeedsRelink))
        XCTAssertTrue(http.sentPaths.isEmpty)
    }

    func testTVRequestAsAdminRequestsAllSeasonsWithSonarrDefaults() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/service/sonarr", json: """
        [{"id":2,"name":"TV","is4k":false,"isDefault":true,"activeDirectory":"/tv","activeProfileId":6,"activeLanguageProfileId":1}]
        """)
        http.stub(pathSuffix: "/request", json: #"{"id":43,"media":{"tmdbId":1396,"status":3}}"#, status: 201)

        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:1396", title: "Breaking Bad", kind: .series, providerIDs: ["Tmdb": "1396"])
        let outcome = await service.request(item)

        XCTAssertEqual(outcome, .success(.processing))
        let body = http.lastSent(pathSuffix: "/request")?.json
        XCTAssertEqual(body?["mediaType"] as? String, "tv")
        XCTAssertEqual(body?["seasons"] as? String, "all")
        XCTAssertEqual(body?["serverId"] as? Int, 2)
        XCTAssertEqual(body?["languageProfileId"] as? Int, 1)
    }

    func testTVRequestCanRequestExplicitSeasons() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/request", json: #"{"id":43,"media":{"tmdbId":1396,"status":2}}"#, status: 201)

        let service = makeConnectedService(http)
        let item = MediaItem(id: "library:1396", title: "Breaking Bad", kind: .series, providerIDs: ["Tmdb": "1396"])
        let outcome = await service.request(
            item,
            seasons: [4, 2, 4, 0],
            identity: .user(id: 9, server: seerServerIdentity)
        )

        XCTAssertEqual(outcome, .success(.pending))
        let body = http.lastSent(pathSuffix: "/request")?.json
        XCTAssertEqual(body?["seasons"] as? [Int], [2, 4])
        XCTAssertEqual(http.lastSent(pathSuffix: "/request")?.headers["X-API-User"], "9")
    }

    func testRequestWithoutTMDBIDFailsWithReason() async {
        let http = SeerRecordingHTTPClient()
        let service = makeConnectedService(http)
        let item = MediaItem(id: "jf:abc", title: "No id", kind: .movie)
        let outcome = await service.request(item)
        guard case .failure(.unknown) = outcome else {
            return XCTFail("expected .failure(.unknown), got \(outcome)")
        }
    }

    // MARK: - RequestOutcome failure mapping (status + message)

    func testRequestAlreadyRequestedMapsFrom409() async {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/request", json: #"{"message":"Request already exists"}"#, status: 409)
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:5", title: "T", kind: .movie, providerIDs: ["Tmdb": "5"])
        let outcome = await service.request(item, identity: .user(id: 2, server: seerServerIdentity))
        XCTAssertEqual(outcome, .failure(.alreadyRequested))
    }

    func testRequestQuotaMapsFrom403Message() async {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/request", json: #"{"message":"You have exceeded your request quota"}"#, status: 403)
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:5", title: "T", kind: .movie, providerIDs: ["Tmdb": "5"])
        let outcome = await service.request(item, identity: .user(id: 2, server: seerServerIdentity))
        XCTAssertEqual(outcome, .failure(.quotaExceeded))
    }

    func testRequestNoPermissionMapsFrom403() async {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/request", json: #"{"message":"You do not have permission"}"#, status: 403)
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:5", title: "T", kind: .movie, providerIDs: ["Tmdb": "5"])
        let outcome = await service.request(item, identity: .user(id: 2, server: seerServerIdentity))
        XCTAssertEqual(outcome, .failure(.noPermission))
    }

    func testRequestNoDefaultsMapsFromServerMessage() async {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/request", json: #"{"message":"No default server was found"}"#, status: 500)
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:5", title: "T", kind: .movie, providerIDs: ["Tmdb": "5"])
        let outcome = await service.request(item, identity: .user(id: 2, server: seerServerIdentity))
        XCTAssertEqual(outcome, .failure(.noDefaults))
    }

    func testRequestInvalidActingUserMapsFrom401() async {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/request", json: #"{"message":"Unauthorized"}"#, status: 401)
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:5", title: "T", kind: .movie, providerIDs: ["Tmdb": "5"])
        let outcome = await service.request(item, identity: .user(id: 999, server: seerServerIdentity))
        XCTAssertEqual(outcome, .failure(.invalidActingUser))
    }

    func testAdmin401IsNotInvalidActingUser() async {
        // On the admin path (no X-API-User) a 401 means a bad admin key, NOT an
        // invalid acting user — it must not be misclassified as invalidActingUser.
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/service/radarr", json: "[]")
        http.stub(pathSuffix: "/request", json: #"{"message":"Unauthorized"}"#, status: 401)
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:5", title: "T", kind: .movie, providerIDs: ["Tmdb": "5"])
        let outcome = await service.request(item)
        guard case let .failure(reason) = outcome else {
            return XCTFail("expected failure, got \(outcome)")
        }
        XCTAssertNotEqual(reason, .invalidActingUser)
        if case .unknown = reason {} else { XCTFail("admin 401 should map to .unknown, got \(reason)") }
    }

    func testRequestUnreachableMapsTransportFailure() async {
        let http = SeerRecordingHTTPClient()
        http.error = .serverUnreachable
        let service = makeConnectedService(http)
        let item = MediaItem(id: "seer:5", title: "T", kind: .movie, providerIDs: ["Tmdb": "5"])
        let outcome = await service.request(item, identity: .user(id: 2, server: seerServerIdentity))
        XCTAssertEqual(outcome, .failure(.unreachable))
    }

    func testRequestKeepsCapturedEndpointAcrossReconnect() async {
        let oldURL = URL(string: "https://old.example.com")!
        let newURL = URL(string: "https://new.example.com")!
        let http = SeerRecordingHTTPClient()
        http.stub(
            pathSuffix: "/service/radarr",
            json: #"[{"id":1,"isDefault":true,"activeDirectory":"/movies","activeProfileId":4}]"#
        )
        http.enqueueStub(
            pathSuffix: "/service/radarr",
            json: #"[{"id":2,"isDefault":true,"activeDirectory":"/new","activeProfileId":5}]"#
        )
        http.stub(pathSuffix: "/request", json: #"{"id":42,"media":{"status":2}}"#, status: 201)
        http.stub(pathSuffix: "/status", json: #"{"version":"2.0"}"#)
        http.suspend(pathSuffix: "/service/radarr")
        let store = InMemorySeerConnectionStore(
            connection: SeerConnection(baseURL: oldURL, apiKey: "OLD")
        )
        let service = SeerService(connectionStore: store, http: http)
        let item = MediaItem(id: "seer:550", title: "Fight Club", kind: .movie, providerIDs: ["Tmdb": "550"])

        let request = Task { await service.request(item) }
        await http.waitUntilSuspended(pathSuffix: "/service/radarr")
        await service.connect(baseURL: newURL, apiKey: "NEW")
        http.resume(pathSuffix: "/service/radarr")
        let outcome = await request.value
        let oldRequest = http.lastSent(pathSuffix: "/request")
        let newOutcome = await service.request(item)
        let newRequest = http.lastSent(pathSuffix: "/request")

        XCTAssertEqual(outcome, .success(.pending))
        XCTAssertEqual(oldRequest?.baseURL, oldURL)
        XCTAssertEqual(newOutcome, .success(.pending))
        XCTAssertEqual(newRequest?.baseURL, newURL)
        XCTAssertEqual(newRequest?.json?["serverId"] as? Int, 2)
        XCTAssertEqual(http.sentPaths.filter { $0.hasSuffix("/service/radarr") }.count, 2)
        XCTAssertEqual(service.serverIdentity, SeerServerIdentity(baseURL: newURL))
    }

    // MARK: - Connection lifecycle

    func testConnectSuccessPersistsAndReportsConnected() async {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/status", json: #"{"version":"1.33.2"}"#)
        let store = InMemorySeerConnectionStore()
        let service = SeerService(connectionStore: store, http: http)
        let initialRevision = service.connectionRevision

        await service.connect(baseURL: seerBaseURL, apiKey: "KEY")

        let version = "1.33.2"
        XCTAssertEqual(service.phase, .connected(summary: "Version \(version)"))
        XCTAssertTrue(service.isConfigured)
        XCTAssertEqual(store.load()?.apiKey, "KEY")
        XCTAssertNotEqual(service.connectionRevision, initialRevision)
        XCTAssertEqual(service.serverIdentity, seerServerIdentity)
    }

    func testConnectFailureDoesNotPersist() async {
        let http = SeerRecordingHTTPClient()
        http.error = .serverUnreachable
        let store = InMemorySeerConnectionStore()
        let service = SeerService(connectionStore: store, http: http)

        await service.connect(baseURL: seerBaseURL, apiKey: "KEY")

        if case .failed = service.phase {} else { XCTFail("expected failed phase, got \(service.phase)") }
        XCTAssertNil(store.load())
        XCTAssertFalse(service.isConfigured)
    }

    func testConnectRejectsEndpointWithoutSafeServerIdentity() async {
        let invalidURLs = [
            URL(string: "ftp://requests.example.com")!,
            URL(string: "https://user:password@requests.example.com")!,
            URL(string: "https://requests.example.com?token=secret")!
        ]

        for invalidURL in invalidURLs {
            let http = SeerRecordingHTTPClient()
            let store = InMemorySeerConnectionStore()
            let service = SeerService(connectionStore: store, http: http)
            let revision = service.connectionRevision

            await service.connect(baseURL: invalidURL, apiKey: "KEY")

            XCTAssertEqual(
                service.phase,
                .failed("Enter a valid HTTP or HTTPS server address without credentials or a query.")
            )
            XCTAssertFalse(service.isConfigured)
            XCTAssertNil(store.load())
            XCTAssertEqual(service.connectionRevision, revision)
            XCTAssertTrue(http.sentPaths.isEmpty)
        }
    }

    func testDisconnectClears() async {
        let http = SeerRecordingHTTPClient()
        let store = InMemorySeerConnectionStore(
            connection: SeerConnection(baseURL: seerBaseURL, apiKey: "KEY")
        )
        let service = SeerService(connectionStore: store, http: http)
        XCTAssertTrue(service.isConfigured)
        let initialRevision = service.connectionRevision

        service.disconnect()

        XCTAssertEqual(service.phase, .unconfigured)
        XCTAssertFalse(service.isConfigured)
        XCTAssertNil(store.load())
        XCTAssertNotEqual(service.connectionRevision, initialRevision)
    }

    func testRefreshStatusUnconfigured() async {
        let http = SeerRecordingHTTPClient()
        let service = SeerService(connectionStore: InMemorySeerConnectionStore(), http: http)
        await service.refreshStatus()
        XCTAssertEqual(service.phase, .unconfigured)
    }

    func testExistingConnectionWithoutSafeIdentityFailsClosed() async throws {
        let invalidURL = URL(string: "https://requests.example.com?tenant=other")!
        let http = SeerRecordingHTTPClient()
        let store = InMemorySeerConnectionStore(
            connection: SeerConnection(baseURL: invalidURL, apiKey: "KEY")
        )
        let service = SeerService(connectionStore: store, http: http)
        let item = MediaItem(id: "seer:5", title: "T", kind: .movie, providerIDs: ["Tmdb": "5"])

        XCTAssertFalse(service.isConfigured)
        XCTAssertNil(service.serverIdentity)
        let users = try await service.users()
        XCTAssertTrue(users.isEmpty)
        let outcome = await service.request(item)
        XCTAssertEqual(
            outcome,
            .failure(.unknown("The saved Seerr server address is invalid. Update it in Settings."))
        )
        await service.refreshStatus()

        XCTAssertEqual(
            service.phase,
            .failed("Enter a valid HTTP or HTTPS server address without credentials or a query.")
        )
        XCTAssertTrue(http.sentPaths.isEmpty)
    }

    func testRefreshStatusDoesNotChangeConnectionRevision() async {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/status", json: #"{"version":"1.0"}"#)
        let service = makeConnectedService(http)
        let revision = service.connectionRevision

        await service.refreshStatus()

        XCTAssertEqual(service.connectionRevision, revision)
    }

    func testConnectPersistenceFailureRetainsOriginalConnection() async {
        let originalURL = URL(string: "https://original.example.com")!
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/status", json: #"{"version":"2.0"}"#)
        let store = ControllableSeerConnectionStore(
            connection: SeerConnection(baseURL: originalURL, apiKey: "ORIGINAL"),
            failSave: true
        )
        let service = SeerService(connectionStore: store, http: http)
        let revision = service.connectionRevision

        await service.connect(baseURL: seerBaseURL, apiKey: "NEW")

        if case .failed = service.phase {} else {
            XCTFail("Expected failed phase, got \(service.phase)")
        }
        XCTAssertEqual(service.serverIdentity, SeerServerIdentity(baseURL: originalURL))
        XCTAssertEqual(service.connectionRevision, revision)
        XCTAssertEqual(store.load()?.apiKey, "ORIGINAL")
    }

    func testDisconnectFailureRetainsOriginalConnection() {
        let http = SeerRecordingHTTPClient()
        let store = ControllableSeerConnectionStore(
            connection: SeerConnection(baseURL: seerBaseURL, apiKey: "KEY"),
            failClear: true
        )
        let service = SeerService(connectionStore: store, http: http)
        let revision = service.connectionRevision

        service.disconnect()

        if case .failed = service.phase {} else {
            XCTFail("Expected failed phase, got \(service.phase)")
        }
        XCTAssertTrue(service.isConfigured)
        XCTAssertEqual(service.connectionRevision, revision)
        XCTAssertEqual(store.load()?.apiKey, "KEY")
    }

    func testDisconnectInvalidatesInFlightConnect() async {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/status", json: #"{"version":"1.0"}"#)
        http.suspend(pathSuffix: "/status")
        let store = InMemorySeerConnectionStore()
        let service = SeerService(connectionStore: store, http: http)

        let connect = Task {
            await service.connect(baseURL: seerBaseURL, apiKey: "KEY")
        }
        await http.waitUntilSuspended(pathSuffix: "/status")
        service.disconnect()
        let disconnectedRevision = service.connectionRevision
        http.resume(pathSuffix: "/status")
        await connect.value

        XCTAssertEqual(service.phase, .unconfigured)
        XCTAssertFalse(service.isConfigured)
        XCTAssertNil(store.load())
        XCTAssertEqual(service.connectionRevision, disconnectedRevision)
    }

    func testNewerConnectWinsOverOlderConnectCompletion() async {
        let firstURL = URL(string: "https://first.example.com")!
        let secondURL = URL(string: "https://second.example.com")!
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/status", json: #"{"version":"1.0"}"#)
        http.suspend(pathSuffix: "/status", onRequestNumber: 1)
        let store = InMemorySeerConnectionStore()
        let service = SeerService(connectionStore: store, http: http)

        let firstConnect = Task {
            await service.connect(baseURL: firstURL, apiKey: "FIRST")
        }
        await http.waitUntilSuspended(pathSuffix: "/status")
        await service.connect(baseURL: secondURL, apiKey: "SECOND")
        let winningRevision = service.connectionRevision
        http.resume(pathSuffix: "/status")
        await firstConnect.value

        XCTAssertEqual(service.serverIdentity, SeerServerIdentity(baseURL: secondURL))
        XCTAssertEqual(store.load()?.apiKey, "SECOND")
        XCTAssertEqual(service.connectionRevision, winningRevision)
    }

    func testReloadWinsOverOlderConnectCompletion() async throws {
        let firstURL = URL(string: "https://first.example.com")!
        let reloadedURL = URL(string: "https://reloaded.example.com")!
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/status", json: #"{"version":"1.0"}"#)
        http.suspend(pathSuffix: "/status", onRequestNumber: 1)
        let store = InMemorySeerConnectionStore()
        let service = SeerService(connectionStore: store, http: http)

        let connect = Task {
            await service.connect(baseURL: firstURL, apiKey: "FIRST")
        }
        await http.waitUntilSuspended(pathSuffix: "/status")
        try store.save(SeerConnection(baseURL: reloadedURL, apiKey: "RELOADED"))
        await service.reloadConnection()
        let reloadedRevision = service.connectionRevision
        http.resume(pathSuffix: "/status")
        await connect.value

        XCTAssertEqual(service.serverIdentity, SeerServerIdentity(baseURL: reloadedURL))
        XCTAssertEqual(store.load()?.apiKey, "RELOADED")
        XCTAssertEqual(service.connectionRevision, reloadedRevision)
    }

    func testReloadInvalidatesCachedAdminServerDefaults() async throws {
        let http = SeerRecordingHTTPClient()
        http.stub(
            pathSuffix: "/service/radarr",
            json: #"[{"id":1,"isDefault":true,"activeDirectory":"/old","activeProfileId":4}]"#
        )
        http.enqueueStub(
            pathSuffix: "/service/radarr",
            json: #"[{"id":2,"isDefault":true,"activeDirectory":"/new","activeProfileId":5}]"#
        )
        http.stub(pathSuffix: "/request", json: #"{"id":42,"media":{"status":2}}"#, status: 201)
        http.stub(pathSuffix: "/status", json: #"{"version":"1.0"}"#)
        let store = InMemorySeerConnectionStore(
            connection: SeerConnection(baseURL: seerBaseURL, apiKey: "OLD")
        )
        let service = SeerService(connectionStore: store, http: http)
        let item = MediaItem(id: "seer:550", title: "Fight Club", kind: .movie, providerIDs: ["Tmdb": "550"])

        _ = await service.request(item)
        let firstBody = http.lastSent(pathSuffix: "/request")?.json
        let firstRevision = service.connectionRevision
        try store.save(SeerConnection(baseURL: seerBaseURL, apiKey: "ROTATED"))
        await service.reloadConnection()
        _ = await service.request(item)
        let secondBody = http.lastSent(pathSuffix: "/request")?.json

        XCTAssertEqual(firstBody?["serverId"] as? Int, 1)
        XCTAssertEqual(secondBody?["serverId"] as? Int, 2)
        XCTAssertEqual(http.sentPaths.filter { $0.hasSuffix("/service/radarr") }.count, 2)
        XCTAssertNotEqual(service.connectionRevision, firstRevision)
    }

    // MARK: - Legacy connection migration

    func testMigrationPromotesFirstConfiguredConnection() async {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/status", json: #"{"version":"1.0"}"#)
        // Legacy: default profile (nil ns) unconfigured; a secondary profile "kid"
        // has a connection. First CONFIGURED wins — never empty-over-configured.
        let legacy = InMemorySeerCredentialStore()
        legacy.setNamespace("kid")
        try? legacy.save(SeerCredentials(baseURL: seerBaseURL, apiKey: "LEGACY", userId: nil))

        let household = InMemorySeerConnectionStore()
        let service = SeerService(connectionStore: household, legacyCredentialStore: legacy, http: http)

        let result = await service.migrateLegacyConnectionIfNeeded(namespaces: [nil, "kid"])

        XCTAssertTrue(result.didPromote)
        XCTAssertEqual(household.load()?.apiKey, "LEGACY")
        XCTAssertTrue(service.isConfigured, "Household connection adopted after migration")
        // Legacy item consumed.
        legacy.setNamespace("kid")
        XCTAssertNil(legacy.load(), "Legacy per-profile connection cleared after promotion")
    }

    func testMigrationFlagsConflictingConnections() async {
        let http = SeerRecordingHTTPClient()
        http.stub(pathSuffix: "/status", json: #"{"version":"1.0"}"#)
        let legacy = InMemorySeerCredentialStore()
        legacy.setNamespace(nil)
        try? legacy.save(SeerCredentials(baseURL: URL(string: "https://a.example.com")!, apiKey: "A"))
        legacy.setNamespace("kid")
        try? legacy.save(SeerCredentials(baseURL: URL(string: "https://b.example.com")!, apiKey: "B"))

        let household = InMemorySeerConnectionStore()
        let service = SeerService(connectionStore: household, legacyCredentialStore: legacy, http: http)

        let result = await service.migrateLegacyConnectionIfNeeded(namespaces: [nil, "kid"])

        XCTAssertTrue(result.didPromote)
        XCTAssertEqual(household.load()?.apiKey, "A", "Default (first) connection wins")
        XCTAssertTrue(result.hadConflictingConnections, "A second, different server is flagged")
    }

    func testMigrationNoOpWhenHouseholdAlreadyConfigured() async {
        let http = SeerRecordingHTTPClient()
        let legacy = InMemorySeerCredentialStore()
        legacy.setNamespace(nil)
        try? legacy.save(SeerCredentials(baseURL: URL(string: "https://legacy.example.com")!, apiKey: "LEGACY"))

        let household = InMemorySeerConnectionStore(
            connection: SeerConnection(baseURL: seerBaseURL, apiKey: "HOUSEHOLD")
        )
        let service = SeerService(connectionStore: household, legacyCredentialStore: legacy, http: http)

        let result = await service.migrateLegacyConnectionIfNeeded(namespaces: [nil])

        XCTAssertFalse(result.didPromote, "Never clobber an already-configured household slot")
        XCTAssertEqual(household.load()?.apiKey, "HOUSEHOLD")
    }

    func testMigrationKeepsLegacyIntactWhenHouseholdSaveFails() async {
        // Loss-safe guarantee: if the household Keychain write fails, the legacy
        // per-profile connection MUST survive so the next launch can retry — never
        // delete it and report a promotion that didn't persist.
        let http = SeerRecordingHTTPClient()
        let legacy = InMemorySeerCredentialStore()
        legacy.setNamespace("kid")
        try? legacy.save(SeerCredentials(baseURL: seerBaseURL, apiKey: "LEGACY", userId: nil))

        let household = FailingSeerConnectionStore()
        let service = SeerService(connectionStore: household, legacyCredentialStore: legacy, http: http)

        let result = await service.migrateLegacyConnectionIfNeeded(namespaces: [nil, "kid"])

        XCTAssertFalse(result.didPromote, "A failed household save must not report a promotion")
        XCTAssertNil(result.connection)
        XCTAssertNil(household.load(), "Nothing persisted to the household slot")
        legacy.setNamespace("kid")
        XCTAssertEqual(legacy.load()?.apiKey, "LEGACY", "Legacy connection preserved for a retry")
    }
}

/// A connection store whose `save` always throws, to exercise the migration's
/// loss-safe path (legacy must not be cleared when the household write fails).
private final class FailingSeerConnectionStore: SeerConnectionStoring, @unchecked Sendable {
    func load() -> SeerConnection? { nil }
    func save(_ connection: SeerConnection) throws { throw SeerConnectionStoreError.encodingFailed }
    func clear() throws {}
}

private final class ControllableSeerConnectionStore: SeerConnectionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var connection: SeerConnection?
    private let failSave: Bool
    private let failClear: Bool

    init(
        connection: SeerConnection? = nil,
        failSave: Bool = false,
        failClear: Bool = false
    ) {
        self.connection = connection
        self.failSave = failSave
        self.failClear = failClear
    }

    func load() -> SeerConnection? {
        lock.lock()
        defer { lock.unlock() }
        return connection
    }

    func save(_ connection: SeerConnection) throws {
        guard !failSave else { throw SeerConnectionStoreError.encodingFailed }
        lock.lock()
        defer { lock.unlock() }
        self.connection = connection
    }

    func clear() throws {
        guard !failClear else { throw SeerConnectionStoreError.encodingFailed }
        lock.lock()
        defer { lock.unlock() }
        connection = nil
    }
}
