import CoreModels
import CoreNetworking
import Foundation
import XCTest
@testable import ProviderSilo

extension SiloProviderTests {
    func testApprovedAlternateRoutesAPIAndAuthenticatesOnlyIssuedServerMedia() async throws {
        let raw = try credential().encoded()
        let original = context(raw)
        let local = URL(string: "http://192.168.1.50:8090/local")!
        var session = original.session
        session.server.alternateConnectionURLs = [local]
        let context = ProviderResolutionContext(session: session, accountID: original.accountID,
                                                credentialRevision: original.credentialRevision)
        let http = SiloAddressHTTP(responses: playbackResponses())
        let provider = try SiloProvider(context: context, credentials: SiloCredentialStub(raw),
                                        http: http, addressProbe: http)
        _ = try await provider.playbackInfo(for: "movie:1", mediaSourceID: "42", forceTranscode: false)
        let requests = await http.requests
        XCTAssertTrue(requests.allSatisfy { $0.0 == local })
        XCTAssertTrue(requests.allSatisfy { $0.1.redirectPolicy == .sameOrigin })
        let issued = URL(string: "http://192.168.1.50:8090/local/api/v2/stream/session1?st=a%2Fb")!
        let authorized = try await provider.client.authorizedMediaURL(issued, sessionID: "session1")
        XCTAssertEqual(authorized.host, local.host)
        XCTAssertTrue(authorized.absoluteString.contains("st=a%2Fb"))
        XCTAssertTrue(authorized.absoluteString.contains("token=access-secret"))
        let foreign = URL(string: "https://node.test/api/v2/stream/session1?st=a%2Fb")!
        let unchanged = try await provider.client.authorizedMediaURL(foreign, sessionID: "session1")
        XCTAssertEqual(unchanged, foreign)
    }

    func testFailedAddressResolutionDoesNotConsumeRotatingRefresh() async throws {
        var login = try credential()
        login.expiresAt = .distantPast
        let raw = try login.encoded()
        let original = context(raw)
        var session = original.session
        session.server.alternateConnectionURLs = [URL(string: "http://192.168.1.50:8090")!]
        let context = ProviderResolutionContext(session: session, accountID: original.accountID,
                                                credentialRevision: original.credentialRevision)
        let store = SiloCredentialStub(raw)
        let http = SiloAddressHTTP(responses: [:], offline: true)
        let provider = try SiloProvider(context: context, credentials: store, http: http, addressProbe: http)
        do { _ = try await provider.libraries(); XCTFail("All addresses are offline") }
        catch { XCTAssertEqual(error as? AppError, .serverUnreachable) }
        XCTAssertEqual(try store.credential(accountID: context.accountID, revision: context.credentialRevision), raw)
        let requests = await http.requests
        XCTAssertFalse(requests.contains { $0.1.path == "/api/v2/auth/refresh" })
        XCTAssertTrue(requests.allSatisfy { $0.1.headers["Authorization"] == nil })
    }
}

private actor SiloAddressHTTP: HTTPClient {
    let wrapped: SiloHTTPStub
    let offline: Bool
    var requests: [(URL, Endpoint)] = []
    init(responses: [String: String], offline: Bool = false) {
        wrapped = SiloHTTPStub(responses)
        self.offline = offline
    }
    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append((baseURL, endpoint))
        if offline { throw AppError.serverUnreachable }
        if endpoint.path == "/api/v2/system/info" {
            return (Data(#"{"api_major":2}"#.utf8),
                    HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return try await wrapped.send(endpoint, baseURL: baseURL)
    }
}
