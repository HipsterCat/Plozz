import Foundation
import XCTest
import CoreModels
import CoreNetworking
@testable import ProviderJellyfin

final class JellyfinAlternateAddressTests: XCTestCase {
    func testSameOriginAliasUsesMostSpecificProxyPrefix() throws {
        let base = URL(string: "https://server.test")!
        let proxy = URL(string: "https://server.test/proxy")!
        let server = MediaServer(id: "server", name: "Home", baseURL: base, provider: .jellyfin,
                                 alternateConnectionURLs: [proxy])
        let provider = JellyfinProvider(session: UserSession(server: server, userID: "user", userName: "Viewer",
                                                             deviceID: "device", accessToken: "credential"))
        let resource = try provider.credentialFreeResource(
            fromServerPath: "https://server.test/proxy/Videos/movie%20name/master.m3u8")
        XCTAssertEqual(resource.path, "Videos/movie%20name/master.m3u8")
        let image = URL(string: "https://server.test/proxy/Items/movie/Images/Primary")!
        XCTAssertTrue(provider.ownsPersistedImageURL(image))
        XCTAssertEqual(provider.reauthenticatedImageURL(image, maxWidth: nil)?.path, "/Items/movie/Images/Primary")
    }

    func testBrowsingArtworkAndPlaybackOriginUseSelectedRouteForBothProviders() async throws {
        for kind in [ProviderKind.jellyfin, .emby] {
            let original = URL(string: "https://remote.test/proxy")!
            let local = URL(string: "http://192.168.1.50:8096")!
            let server = MediaServer(id: "server", name: "Home", baseURL: original, provider: kind,
                                     alternateConnectionURLs: [local])
            let session = UserSession(server: server, userID: "user", userName: "Viewer",
                                      deviceID: "device", accessToken: "credential")
            let http = JellyfinAddressHTTP()
            let provider = JellyfinProvider(session: session, http: http, addressProbe: http)
            XCTAssertEqual(provider.connectionLocality, .unknown)
            _ = try await provider.libraries()
            XCTAssertEqual(provider.authenticatedHTTPOrigin, local)
            XCTAssertEqual(provider.connectionLocality, .local)
            XCTAssertEqual(provider.imageURL(itemID: "movie", kind: .primary, maxWidth: nil)?.host, local.host)
            let oldImage = URL(string: "https://remote.test/proxy/Items/movie/Images/Primary")!
            XCTAssertTrue(provider.ownsPersistedImageURL(oldImage))
            XCTAssertEqual(provider.reauthenticatedImageURL(oldImage, maxWidth: nil)?.path, "/Items/movie/Images/Primary")
            let resource = try provider.credentialFreeResource(fromServerPath: "https://remote.test/proxy/Videos/movie/master.m3u8")
            XCTAssertEqual(resource.pathBase, .configuredBaseURL)
            XCTAssertEqual(resource.path, "Videos/movie/master.m3u8")
            let encoded = try provider.credentialFreeResource(
                fromServerPath: "https://remote.test/proxy/Videos/movie%20name/master.m3u8?ApiKey=old&quality=10")
            XCTAssertEqual(encoded.path, "Videos/movie%20name/master.m3u8")
            XCTAssertEqual(encoded.queryItems.map(\.name), ["quality"])
            let requests = await http.requests
            XCTAssertTrue(requests.filter { $0.1.path != "/System/Info/Public" }.allSatisfy { $0.0 == local })
        }
    }
}

private actor JellyfinAddressHTTP: HTTPClient {
    var requests: [(URL, Endpoint)] = []
    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append((baseURL, endpoint))
        let json = endpoint.path == "/System/Info/Public" ? #"{"Id":"server"}"# : #"{"Items":[],"TotalRecordCount":0}"#
        return (Data(json.utf8), HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
