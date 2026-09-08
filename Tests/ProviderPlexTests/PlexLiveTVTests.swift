import Foundation
import XCTest
import CoreModels
import CoreNetworking
@testable import ProviderPlex

final class PlexLiveTVTests: XCTestCase {
    private let epg = "tv.plex.providers.epg.cloud:12"
    private var providers: String {
        """
        {"MediaContainer":{"MediaProvider":[
          {"identifier":"\(epg)","providerIdentifier":"tv.plex.providers.epg.cloud",
           "protocols":"livetv","Feature":[{"type":"grid","key":"/\(epg)/grid"}]}
        ]}}
        """
    }
    private var channels: String {
        """
        {"MediaContainer":{"size":"2","Channel":[
          {"id":101,"gridKey":"native-grid-101","vcn":"7.1","title":"News","thumb":"https://images.invalid/news.png"},
          {"id":"102","gridKey":"native-grid-102","vcn":9,"title":"News","thumb":"/library/channel.png?X-Plex-Token=bad"}
        ]}}
        """
    }

    private func provider(_ http: PlexLiveTVFixtureHTTP) -> PlexProvider {
        PlexProvider(
            session: UserSession(
                server: MediaServer(
                    id: "plex-live-fixture-\(UUID().uuidString)",
                    name: "Fixture PMS",
                    baseURL: URL(string: "https://plex.invalid:32400")!,
                    provider: .plex
                ),
                userID: "fixture-home-user", userName: "Fixture user",
                deviceID: "fixture-device", accessToken: "fixture-home-token"
            ),
            accountID: "fixture-account", http: http, interactiveHTTP: http, probe: http
        )
    }

    func testAbsentProvidersAndDVRProduceHonestUnconfiguredState() async throws {
        for casing in ["DVR", "Dvr"] {
            let http = PlexLiveTVFixtureHTTP([
                "/media/providers": [.init(json: #"{"MediaContainer":{"MediaProvider":[]}}"#)],
                "/livetv/dvrs": [.init(json: #"{"MediaContainer":{"\#(casing)":[]}}"#)]
            ])
            let result = try await provider(http).liveTVAvailability()
            XCTAssertEqual(result.status, .notConfigured)
            XCTAssertFalse(result.hasChannels)
            XCTAssertFalse(result.supportsPlayback)
            let requests = await http.requests
            XCTAssertTrue(requests.allSatisfy { $0.method == .get })
        }
    }

    func testConfiguredDVRWithoutUsableEPGIsNotCalledReady() async throws {
        let http = PlexLiveTVFixtureHTTP([
            "/media/providers": [.init(json: #"{"MediaContainer":{"MediaProvider":[]}}"#)],
            "/livetv/dvrs": [.init(json: #"{"MediaContainer":{"Dvr":[{"key":12,"uuid":"fixture-dvr","lineup":"fixture-lineup"}]}}"#)]
        ])
        let result = try await provider(http).liveTVAvailability()
        XCTAssertEqual(result.status, .unsupportedAPI)
        XCTAssertFalse(result.supportsPlayback)
    }

    func testRealChannelsAndGuideCapabilityDoNotPromisePlexTuning() async throws {
        let http = PlexLiveTVFixtureHTTP([
            "/media/providers": [.init(json: providers)],
            "/\(epg)/lineups/dvr/channels": [.init(json: channels)]
        ])
        let result = try await provider(http).liveTVAvailability()
        XCTAssertEqual(result.status, .unsupportedPlaybackMode)
        XCTAssertEqual(result.channelCount, 2)
        XCTAssertTrue(result.hasChannels)
        XCTAssertTrue(result.supportsGuide)
        XCTAssertFalse(result.supportsPlayback)
        let requests = await http.requests
        XCTAssertFalse(requests.contains { $0.path == "/livetv/dvrs" },
                       "A Home user's readable channels must not depend on administrative DVR inspection")
        XCTAssertTrue(requests.allSatisfy { $0.headers["X-Plex-Token"] == "fixture-home-token" })
        XCTAssertTrue(requests.allSatisfy { $0.redirectPolicy == .sameOrigin })
        XCTAssertTrue(requests.allSatisfy { $0.headers["Cache-Control"] == "no-store" })
        XCTAssertTrue(requests.allSatisfy { !$0.queryItems.contains { $0.name == "X-Plex-Token" } })
    }

    func testChannelsPreserveScalarVariantsDistinctNativeIDsAndSecretFreeArtwork() async throws {
        let http = PlexLiveTVFixtureHTTP([
            "/media/providers": [.init(json: providers)],
            "/\(epg)/lineups/dvr/channels": [.init(json: channels)]
        ])
        let result = try await provider(http).liveTVChannels()
        XCTAssertEqual(result.map(\.id), ["\(epg)|101", "\(epg)|102"])
        XCTAssertEqual(result.map(\.name), ["News", "News"])
        XCTAssertEqual(result.map(\.number), ["7.1", "9"])
        XCTAssertEqual(result[0].imageURL?.host, "images.invalid")
        XCTAssertNil(result[1].imageURL)
    }

    func testDifferentEPGProvidersNamespaceOtherwiseIdenticalChannels() async throws {
        let second = "tv.plex.providers.epg.xmltv:47"
        let http = PlexLiveTVFixtureHTTP([
            "/media/providers": [.init(json: """
            {"MediaContainer":{"MediaProvider":[
              {"identifier":"\(epg)","protocols":"livetv","Feature":[{"type":"grid","key":"/\(epg)/grid"}]},
              {"identifier":"\(second)","protocols":"livetv","Feature":[{"type":"grid","key":"/\(second)/grid"}]}
            ]}}
            """)],
            "/\(epg)/lineups/dvr/channels": [.init(json: channels)],
            "/\(second)/lineups/dvr/channels": [.init(json: channels)]
        ])
        let result = try await provider(http).liveTVChannels()
        XCTAssertEqual(Set(result.map(\.id)).count, 4)
        XCTAssertTrue(result.contains { $0.id == "\(second)|101" })
        let requests = await http.requests
        XCTAssertFalse(requests.contains { $0.path.contains("cloud:1/") })
    }

    func testNativeGuideFlattensAndDeduplicatesOnlyAuthoritativeMatchingAirings() async throws {
        let start: TimeInterval = 1_789_034_400
        let guide = """
        {"MediaContainer":{"size":1,"Metadata":[
          {"ratingKey":"programme-1","title":"Episode title","grandparentTitle":"Show title",
           "summary":"Native server guide","Genre":[{"tag":"News"}],
           "Media":[
             {"beginsAt":"\(start - 900)","endsAt":\(start + 900),"channelIdentifier":101,"protocol":"livetv"},
             {"beginsAt":\(start),"endsAt":\(start + 1800),"channelIdentifier":102,"protocol":"livetv"},
             {"beginsAt":\(start),"endsAt":\(start - 100),"channelIdentifier":101,"protocol":"livetv"},
             {"beginsAt":"invalid","endsAt":\(start + 900),"channelIdentifier":101,"protocol":"livetv"}
           ]}
        ]}}
        """
        let http = PlexLiveTVFixtureHTTP([
            "/media/providers": [.init(json: providers)],
            "/\(epg)/lineups/dvr/channels": [.init(json: channels)],
            "/\(epg)/grid": [.init(json: guide)]
        ])
        let result = try await provider(http).liveTVGuide(
            channelIDs: ["\(epg)|101"],
            from: Date(timeIntervalSince1970: start),
            to: Date(timeIntervalSince1970: start + 3_600)
        )
        XCTAssertEqual(result.count, 1)
        let airing = try XCTUnwrap(result.first)
        XCTAssertEqual(airing.channelID, "\(epg)|101")
        XCTAssertEqual(airing.title, "Show title")
        XCTAssertEqual(airing.subtitle, "Episode title")
        XCTAssertEqual(airing.categories, ["News"])
        XCTAssertEqual(airing.startDate.timeIntervalSince1970, start - 900)
        let requests = await http.requests
        let grids = requests.filter { $0.path.hasSuffix("/grid") }
        XCTAssertTrue(grids.count >= 3, "Include adjacent lineup dates without fabricating timezone metadata")
        XCTAssertTrue(grids.allSatisfy { $0.query("channelGridKey") == "native-grid-101" })
        XCTAssertTrue(grids.allSatisfy { $0.query("date")?.count == 10 })
        XCTAssertTrue(requests.allSatisfy { $0.method == .get })
    }

    func testUnsafeEPGIdentifierCannotBecomeAuthenticatedRequestPath() async throws {
        let http = PlexLiveTVFixtureHTTP([
            "/media/providers": [.init(json: """
            {"MediaContainer":{"MediaProvider":[
              {"identifier":"tv.plex.providers.epg.cloud:12/../../admin","protocols":"livetv"},
              {"identifier":"https://external.invalid/tv.plex.providers.epg.cloud:12","protocols":"livetv"}
            ]}}
            """)],
            "/livetv/dvrs": [.init(json: #"{"MediaContainer":{"DVR":[]}}"#)]
        ])
        let result = try await provider(http).liveTVAvailability()
        XCTAssertFalse(result.supportsPlayback)
        let requests = await http.requests
        XCTAssertEqual(requests.map(\.path), ["/media/providers", "/livetv/dvrs"])
    }

    func testExternalGridFeatureDoesNotReceiveServerCredentials() async throws {
        let http = PlexLiveTVFixtureHTTP([
            "/media/providers": [.init(json: """
            {"MediaContainer":{"MediaProvider":[
              {"identifier":"\(epg)","protocols":"livetv","Feature":[
                {"type":"grid","key":"https://external.invalid/grid"}]}
            ]}}
            """)],
            "/\(epg)/lineups/dvr/channels": [.init(json: channels)]
        ])
        let result = try await provider(http).liveTVAvailability()
        XCTAssertTrue(result.hasChannels)
        XCTAssertFalse(result.supportsGuide)
        let guide = try await provider(http).liveTVGuide(
            channelIDs: ["\(epg)|101"], from: Date(), to: Date().addingTimeInterval(3_600)
        )
        XCTAssertTrue(guide.isEmpty)
        let requests = await http.requests
        XCTAssertFalse(requests.contains { $0.path.contains("external") })
    }

    func testUnsupportedPlaybackDoesNotTuneCreateConsumerOrAdminTerminate() async throws {
        let http = PlexLiveTVFixtureHTTP([:])
        do {
            _ = try await provider(http).openLiveTVChannel(id: "\(epg)|101")
            XCTFail("Plex tuner lifecycle is not supported")
        } catch {
            XCTAssertEqual(error as? ServerLiveTVError, .unsupportedPlaybackMode)
        }
        let requests = await http.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testPermissionDeniedIsDifferentFromExpiredCredentials() async throws {
        let denied = PlexLiveTVFixtureHTTP(["/media/providers": [.init(status: 403)]])
        let deniedResult = try await provider(denied).liveTVAvailability()
        XCTAssertEqual(deniedResult.status, .permissionDenied)
        let expired = PlexLiveTVFixtureHTTP(["/media/providers": [.init(status: 401)]])
        do {
            _ = try await provider(expired).liveTVAvailability()
            XCTFail("Authentication error must remain actionable")
        } catch {
            XCTAssertEqual(error as? AppError, .unauthorized)
        }
    }

    func testGuideRejectsUnboundedWindowsBeforeMakingRequests() async throws {
        let http = PlexLiveTVFixtureHTTP([:])
        do {
            _ = try await provider(http).liveTVGuide(
                channelIDs: ["\(epg)|101"], from: Date(), to: Date().addingTimeInterval(172_801)
            )
            XCTFail("Guide requests must be bounded")
        } catch {
            XCTAssertEqual(error as? ServerLiveTVError, .invalidGuideWindow)
        }
        let requests = await http.requests
        XCTAssertTrue(requests.isEmpty)
    }
}

private actor PlexLiveTVFixtureHTTP: HTTPClient {
    struct Reply: Sendable {
        var status = 200
        var json = "{}"
    }
    private var replies: [String: [Reply]]
    private(set) var requests: [Endpoint] = []

    init(_ replies: [String: [Reply]]) {
        self.replies = replies
    }

    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        let result = try await sendRaw(endpoint, baseURL: baseURL)
        guard (200..<300).contains(result.1.statusCode) else { throw AppError.invalidResponse }
        return result
    }

    func sendRaw(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append(endpoint)
        guard var matches = replies[endpoint.path], let reply = matches.first else {
            XCTFail("Unstubbed fixture endpoint: \(endpoint.path)")
            throw AppError.invalidResponse
        }
        if matches.count > 1 {
            matches.removeFirst()
            replies[endpoint.path] = matches
        }
        return (
            Data(reply.json.utf8),
            HTTPURLResponse(url: baseURL, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        )
    }
}

private extension Endpoint {
    func query(_ name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }
}
