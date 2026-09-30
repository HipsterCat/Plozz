import CoreModels
import CoreNetworking
import Foundation
@testable import ProviderPlex
import XCTest

final class PlexCommonSenseMediaTests: XCTestCase {
    private let metadataID = "0123456789abcdef01234567"

    private func provider(http: StubHTTPClient) -> PlexProvider {
        PlexProvider(session: UserSession(
            server: MediaServer(id: UUID().uuidString, name: "Fixture",
                                baseURL: URL(string: "https://server.example")!, provider: .plex),
            userID: "viewer", userName: "Viewer", deviceID: "fixture", accessToken: "SERVER-TOKEN"
        ), http: http)
    }

    private var item: MediaItem {
        MediaItem(id: "123", title: "Fixture", kind: .movie,
                  providerIDs: ["PlexGuid": "plex://movie/\(metadataID)"])
    }

    func testBasicGuidanceMapsForMoviesAndShowsWithoutReplacingCertificate() async throws {
        for type in ["movie", "show"] {
            let http = StubHTTPClient()
            http.stub(pathSuffix: "/library/metadata/123", json: """
            {"MediaContainer":{"Metadata":[{
              "ratingKey":"123","type":"\(type)","title":"Fixture","contentRating":"PG-13",
              "CommonSenseMedia":[{"oneLiner":"A fictional review summary.",
                "AgeRating":[{"type":"official","age":14,"rating":3}]}]
            }]}}
            """)
            let value = try await provider(http: http).item(id: "123")
            XCTAssertEqual(value.officialRating, "PG-13")
            XCTAssertEqual(value.familyGuidance?.recommendedAge, 14)
            XCTAssertEqual(value.familyGuidance?.qualityRating, 3)
            XCTAssertEqual(value.familyGuidance?.overview, "A fictional review summary.")
            XCTAssertFalse(http.sentPaths.contains { $0.hasSuffix("/commonsensemedia") })
        }
    }

    func testMissingGuidanceAndEpisodeMetadataDoNotInventARecommendation() async throws {
        for payload in [
            #"{"ratingKey":"123","type":"movie","title":"Fixture"}"#,
            #"{"ratingKey":"123","type":"episode","title":"Fixture","CommonSenseMedia":[{"AgeRating":[{"type":"official","age":14,"rating":3}]}]}"#
        ] {
            let http = StubHTTPClient()
            http.stub(pathSuffix: "/library/metadata/123", json: #"{"MediaContainer":{"Metadata":["# + payload + "]}}")
            let value = try await provider(http: http).item(id: "123")
            XCTAssertNil(value.familyGuidance)
        }
    }

    func testFullGuidanceUsesGlobalPlexIdentityAndPreservesZeroScores() async throws {
        let http = StubHTTPClient()
        http.stub(pathSuffix: "/\(metadataID)/commonsensemedia", json: """
        {"MediaContainer":{"CommonSenseMedia":[{
          "AgeRating":[{"type":"official","age":"14","rating":"3"},
                       {"type":"adult","age":13.5,"rating":4.2}],
          "ParentalAdvisoryTopic":[
            {"id":"violence","label":"Violence","rating":0,"tag":"No violence in this fixture."},
            {"id":"language","label":"Language","tag":"Score unavailable."},
            {"id":"message","label":"Positive messages","rating":"4","positive":"1"},
            {"id":"violence","label":"Repeated","rating":5}],
          "parentsNeedToKnow":"A fictional parents overview.",
          "anyGood":"A fictional quality overview.",
          "TalkingPoint":[{"tag":"A fictional discussion prompt."}]
        }]}}
        """)
        let result = try await provider(http: http).familyGuidance(for: item, accountToken: "HOME-ACCOUNT-TOKEN")
        guard case .available(let guidance) = result else { return XCTFail("Expected full guidance") }
        XCTAssertEqual(guidance.summary.recommendedAge, 14)
        XCTAssertEqual(guidance.audienceRatings.count, 2)
        XCTAssertEqual(guidance.topics.count, 3)
        XCTAssertEqual(guidance.topics[0].rating, 0)
        XCTAssertNil(guidance.topics[1].rating)
        XCTAssertTrue(guidance.topics[2].isPositive)
        XCTAssertTrue(guidance.hasDetails)
        XCTAssertEqual(http.sentBaseURLs.last?.host, "metadata.provider.plex.tv")
        XCTAssertEqual(http.sentPaths, ["/library/metadata/\(metadataID)/commonsensemedia"])
    }

    func testGuidanceUsesTheMetadataHostNotTheDiscoverWatchlistHost() async throws {
        let http = GuidanceHostHTTP()
        let client = PlexClient(
            baseURL: URL(string: "https://server.example")!,
            deviceProfile: PlexDeviceProfile(clientIdentifier: "fixture"),
            token: "SERVER-TOKEN", discoverToken: "CURRENT-HOME-CLOUD", http: http
        )
        let result = try await client.commonSenseMedia(metadataID: metadataID)
        guard case .available(let guidance) = result else {
            return XCTFail("The metadata endpoint should return the detailed guidance.")
        }
        XCTAssertEqual(guidance.parentsNeedToKnow, "A fictional detailed review.")
        let requests = await http.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.host, "metadata.provider.plex.tv")
        XCTAssertEqual(requests.first?.token, "CURRENT-HOME-CLOUD")
        XCTAssertEqual(requests.first?.redirectPolicy, .sameOrigin)
    }

    func testRetryUsesANewRequestAndNeverCachesAnAuthorizationFailure() async throws {
        let http = StubHTTPClient()
        http.stubSequence(pathSuffix: "/commonsensemedia", responses: [
            ("{}", 401),
            (#"{"MediaContainer":{"CommonSenseMedia":[{"parentsNeedToKnow":"A newly available fictional review."}]}}"#, 200)
        ])
        let value = provider(http: http)
        do {
            _ = try await value.familyGuidance(for: item, accountToken: "EXPIRED-HOME-TOKEN")
            XCTFail("The first unauthorized response must remain an explicit failure.")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
        }
        let result = try await value.familyGuidance(for: item, accountToken: "CURRENT-HOME-TOKEN")
        guard case .available(let guidance) = result else { return XCTFail("Retry must fetch the review.") }
        XCTAssertEqual(guidance.parentsNeedToKnow, "A newly available fictional review.")
        XCTAssertEqual(http.sentPaths.count, 2)
        XCTAssertTrue(http.sentBaseURLs.allSatisfy { $0.host == "metadata.provider.plex.tv" })
    }

    func testInvalidScoresStayUnknownRatherThanClampingToSafeValues() throws {
        let dto = try JSONDecoder().decode(PlexCommonSenseMedia.self, from: Data("""
        {"AgeRating":[{"type":"official","age":900,"rating":-1}],
         "ParentalAdvisoryTopic":[{"id":"violence","label":"Violence","rating":99}]}
        """.utf8))
        XCTAssertNil(dto.summary.recommendedAge)
        XCTAssertNil(dto.summary.qualityRating)
        XCTAssertNil(dto.guidance.topics.first?.rating)
    }

    private actor GuidanceHostHTTP: HTTPClient {
        struct Request: Sendable {
            let host: String?
            let token: String?
            let redirectPolicy: Endpoint.RedirectPolicy
        }
        private(set) var requests: [Request] = []

        func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
            try await sendRaw(endpoint, baseURL: baseURL)
        }

        func sendRaw(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
            requests.append(Request(
                host: baseURL.host, token: endpoint.headers["X-Plex-Token"],
                redirectPolicy: endpoint.redirectPolicy
            ))
            let expected = baseURL.host == "metadata.provider.plex.tv"
                && endpoint.headers["X-Plex-Token"] == "CURRENT-HOME-CLOUD"
            let body = expected
                ? #"{"MediaContainer":{"CommonSenseMedia":[{"parentsNeedToKnow":"A fictional detailed review."}]}}"#
                : "{}"
            return (
                Data(body.utf8),
                HTTPURLResponse(url: baseURL, statusCode: expected ? 200 : 401, httpVersion: nil, headerFields: nil)!
            )
        }
    }

    func testRestrictedMissingAndAuthenticationFailureRemainDistinct() async throws {
        for status in [401, 403, 404, 500] {
            let http = StubHTTPClient()
            http.stub(pathSuffix: "/commonsensemedia", json: "{}", status: status)
            do {
                let result = try await provider(http: http).familyGuidance(for: item, accountToken: nil)
                XCTAssertEqual(result, status == 403 ? .restricted : .unavailable)
                XCTAssertTrue([403, 404].contains(status))
            } catch let error as AppError {
                XCTAssertEqual(error, status == 401 ? .unauthorized : .invalidResponse)
                XCTAssertTrue([401, 500].contains(status))
            }
        }
    }

    func testMalformedGlobalIdentityCannotChangeTheCloudRequestPath() async throws {
        let http = StubHTTPClient()
        var invalid = item
        invalid.providerIDs["PlexGuid"] = "plex://movie/../../account"
        do {
            _ = try await provider(http: http).familyGuidance(for: invalid, accountToken: nil)
            XCTFail("Expected invalid identity to be rejected")
        } catch let error as AppError {
            XCTAssertEqual(error, .invalidResponse)
        }
        XCTAssertTrue(http.sentPaths.isEmpty)
    }
}
