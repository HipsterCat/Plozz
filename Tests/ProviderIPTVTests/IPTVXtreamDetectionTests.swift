import CoreModels
import CoreNetworking
import Foundation
@testable import ProviderIPTV
import XCTest

final class IPTVXtreamDetectionTests: XCTestCase {
    override func tearDown() {
        IPTVFixture.state.reset()
        super.tearDown()
    }

    func testServerAddressWithAdvancedBasicLoginConnectsAsXtreamAndPreservesOptions() async throws {
        let header = "Basic " + Data("fixture-user:fixture-password".utf8).base64EncodedString()
        let credential = try IPTVCredential(
            mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test/prefix/")),
            username: "fixture-user", password: "fixture-password",
            headers: ["Authorization": header, "X-Provider-Key": "fixture"],
            guideURL: XCTUnwrap(URL(string: "https://guide.test/first.xml")),
            additionalGuideURLs: [XCTUnwrap(URL(string: "https://guide.test/second.xml"))],
            guideHeaders: ["X-Guide-Key": "guide-fixture"], discoversPlaylistGuides: false
        )
        IPTVFixture.state.handler = { request in
            XCTAssertEqual(request.url?.host, "provider.test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), header)
            if request.url?.path == credential.address.path {
                return (200, ["Content-Type": "text/html"], Data("<html>Provider portal</html>".utf8))
            }
            return try Self.xtream(request)
        }
        let session = try await signIn(credential)
        let detected = try IPTVCredential.decode(session.accessToken)
        XCTAssertEqual(detected.mode, .xtream)
        XCTAssertEqual(detected.address.absoluteString, "https://provider.test/prefix")
        XCTAssertEqual(detected.username, credential.username)
        XCTAssertEqual(detected.password, credential.password)
        XCTAssertEqual(detected.headers, credential.headers)
        XCTAssertEqual(detected.explicitGuideURLs, credential.explicitGuideURLs)
        XCTAssertEqual(detected.explicitGuideHeaders, credential.explicitGuideHeaders)
        XCTAssertFalse(detected.automaticallyDiscoversGuides)
        XCTAssertNotEqual(detected.identity, credential.identity)
        XCTAssertEqual(session.userID, "fixture-user")
        XCTAssertEqual(IPTVFixture.state.requests.count, 8)
        XCTAssertEqual(IPTVFixture.state.requests.first?.url, credential.address)
    }

    func testRealBasicAndCredentialQueryPlaylistsAreNotConverted() async throws {
        for address in ["https://provider.test/", "https://provider.test/get.php?username=fixture-user&password=fixture-password"] {
            IPTVFixture.state.reset()
            let credential = try IPTVCredential(
                mode: .playlist, address: XCTUnwrap(URL(string: address)),
                headers: ["Authorization": "Basic " + Data("fixture-user:fixture-password".utf8).base64EncodedString()]
            )
            IPTVFixture.state.handler = { _ in
                (200, [:], Data("#EXTM3U\n#EXTINF:-1,News\nhttps://provider.test/live/10.ts\n".utf8))
            }
            let saved = try IPTVCredential.decode(try await signIn(credential).accessToken)
            XCTAssertEqual(saved, credential)
            XCTAssertEqual(IPTVFixture.state.requests.count, 1)
        }
    }

    func testAPIAndNonPlaylistGetLinksInferTheirQueryCredentials() async throws {
        for endpoint in ["player_api.php", "get.php"] {
            IPTVFixture.state.reset()
            let address = try XCTUnwrap(URL(string:
                "https://provider.test/prefix/\(endpoint)?username=fixture-user&password=fixture-password&type=m3u_plus"
            ))
            let credential = try IPTVCredential(mode: .playlist, address: address)
            IPTVFixture.state.handler = { request in
                if request.url?.path == "/prefix/get.php" {
                    return (200, ["Content-Type": "application/json"], Data(#"{"user_info":{"auth":1}}"#.utf8))
                }
                return try Self.xtream(request)
            }
            let saved = try IPTVCredential.decode(try await signIn(credential).accessToken)
            XCTAssertEqual(saved.mode, .xtream)
            XCTAssertEqual(saved.address.absoluteString, "https://provider.test/prefix")
            XCTAssertEqual(saved.username, "fixture-user")
            XCTAssertEqual(saved.password, "fixture-password")
            XCTAssertEqual(IPTVFixture.state.requests.count, endpoint == "get.php" ? 8 : 7)
        }
    }

    func testEncodedCredentialsSurviveDetectionAndPHPQueryDecoding() async throws {
        let credential = try IPTVCredential(
            mode: .playlist,
            address: XCTUnwrap(URL(string: "https://provider.test/player_api.php?username=user%2Bname&password=p%2Ba%26ss%3D%25"))
        )
        IPTVFixture.state.handler = { request in
            let raw = try XCTUnwrap(request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery
            })
            let fields = Dictionary(uniqueKeysWithValues: raw.split(separator: "&").map { field -> (String, String) in
                let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let value = String(pair.last!).replacingOccurrences(of: "+", with: " ").removingPercentEncoding!
                return (String(pair[0]), value)
            })
            XCTAssertEqual(fields["username"], "user+name")
            XCTAssertEqual(fields["password"], "p+a&ss=%")
            return (200, ["Content-Type": "application/json"], Data(
                (fields["action"] == nil ? #"{"user_info":{"auth":1,"status":"Active"}}"# : "[]").utf8
            ))
        }
        let saved = try IPTVCredential.decode(try await signIn(credential).accessToken)
        XCTAssertEqual(saved.mode, .xtream)
        XCTAssertEqual(saved.username, "user+name")
        XCTAssertEqual(saved.password, "p+a&ss=%")
    }

    func testEmptyMissingAndUnsupportedPlaylistEndpointsTryXtreamOnce() async throws {
        let credential = try IPTVCredential(
            mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test/prefix")),
            username: "fixture-user", password: "fixture-password"
        )
        for status in [200, 404, 405, 501] {
            IPTVFixture.state.reset()
            IPTVFixture.state.handler = { request in
                if request.url == credential.address { return (status, [:], Data()) }
                return try Self.xtream(request)
            }
            let saved = try IPTVCredential.decode(try await signIn(credential).accessToken)
            XCTAssertEqual(saved.mode, .xtream)
            XCTAssertEqual(IPTVFixture.state.requests.count, 8)
        }
    }

    func testDetectionDoesNotGuessMissingAmbiguousOrUnrelatedLogins() throws {
        for address in [
            "https://provider.test/", "https://provider.test/get.php?username=user",
            "https://provider.test/get.php?username=user&username=other&password=secret",
            "https://provider.test/get.php?username=user&password=secret&password=other",
            "https://provider.test/get.php?username=&password=secret",
            "https://provider.test/xmltv.php?username=user&password=secret",
            "https://provider.test/video.m3u8?username=user&password=secret",
            "https://provider.test/list.m3u?username=user&password=secret"
        ] {
            let credential = try IPTVCredential(mode: .playlist, address: XCTUnwrap(URL(string: address)))
            XCTAssertNil(try IPTVXtreamDetection.candidate(for: credential), address)
        }
        let conflicting = try IPTVCredential(
            mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test/get.php?username=user&password=secret")),
            headers: ["Authorization": "Basic " + Data("other:secret".utf8).base64EncodedString()]
        )
        XCTAssertNil(try IPTVXtreamDetection.candidate(for: conflicting))
        let bearer = try IPTVCredential(
            mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test")),
            username: "stale-user", password: "stale-password", headers: ["Authorization": "Bearer fixture-token"]
        )
        XCTAssertNil(try IPTVXtreamDetection.candidate(for: bearer))
    }

    func testAuthenticationRateLimitsNetworkFailuresAndCancellationDoNotRetryAsXtream() async throws {
        let credential = try IPTVCredential(
            mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test")),
            headers: ["Authorization": "Basic " + Data("fixture-user:fixture-password".utf8).base64EncodedString()]
        )
        for status in [401, 403, 429, 500, 503] {
            IPTVFixture.state.reset()
            IPTVFixture.state.handler = { _ in (status, [:], Data()) }
            do { _ = try await signIn(credential); XCTFail("A provider failure must remain a failure.") }
            catch {
                if status == 401 || status == 403 { XCTAssertEqual(error as? IPTVError, .authentication) }
                else if status == 429 {
                    guard case AppError.rateLimited = error else { return XCTFail("Expected the original rate limit.") }
                } else { XCTAssertEqual(error as? IPTVError, .httpStatus(status)) }
            }
            XCTAssertEqual(IPTVFixture.state.requests.count, 1)
        }
        for error: any Error in [URLError(.timedOut), CancellationError()] {
            IPTVFixture.state.reset()
            IPTVFixture.state.handler = { _ in throw error }
            do { _ = try await signIn(credential); XCTFail("A transport failure cannot trigger detection.") }
            catch { XCTAssertFalse(IPTVXtreamDetection.permitsFallback(after: error)) }
            XCTAssertEqual(IPTVFixture.state.requests.count, 1)
        }
    }

    func testRejectedDetectedLoginDoesNotImportCatalogsOrLoop() async throws {
        let credential = try IPTVCredential(
            mode: .playlist, address: XCTUnwrap(URL(string: "https://provider.test")),
            username: "fixture-user", password: "fixture-password"
        )
        IPTVFixture.state.handler = { request in
            let body = request.url?.path == "/player_api.php"
                ? #"{"user_info":{"auth":0}}"# : "<html>Provider portal</html>"
            return (200, [:], Data(body.utf8))
        }
        do { _ = try await signIn(credential); XCTFail("Rejected Xtream credentials cannot create an account.") }
        catch { XCTAssertEqual(error as? IPTVError, .authentication) }
        XCTAssertEqual(IPTVFixture.state.requests.count, 2)
    }

    private func signIn(_ credential: IPTVCredential) async throws -> UserSession {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        }
        return try await IPTVProvider.signIn(
            credential: credential, name: "Fixture", deviceID: "fixture",
            cacheDirectory: root, configuration: IPTVFixture.configuration()
        )
    }

    private static func xtream(_ request: URLRequest) throws -> IPTVFixture.Response {
        XCTAssertEqual(request.url?.path, "/prefix/player_api.php")
        let fields = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems)
        XCTAssertEqual(fields.first { $0.name == "username" }?.value, "fixture-user")
        XCTAssertEqual(fields.first { $0.name == "password" }?.value, "fixture-password")
        let action = fields.first { $0.name == "action" }?.value
        let body = action == nil ? #"{"user_info":{"auth":1,"status":"Active"}}"#
            : action == "get_live_streams" ? #"[{"stream_id":10,"name":"News"}]"# : "[]"
        return (200, ["Content-Type": "application/json"], Data(body.utf8))
    }
}
