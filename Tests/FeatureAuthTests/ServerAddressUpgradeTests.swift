import XCTest
import CoreModels
import CoreNetworking
import ProviderJellyfin
@testable import FeatureAuthCore

final class ServerAddressUpgradeTests: XCTestCase {
    private func account(provider: ProviderKind = .jellyfin) -> Account {
        Account(
            id: "account",
            server: .init(id: "server", name: "Home", baseURL: URL(string: "http://media.example/old")!, provider: provider),
            userID: "user", userName: "Viewer", deviceID: "device", addedAt: Date(timeIntervalSince1970: 100)
        )
    }

    func testSavedHTTPAccountsRepairWithoutChangingLoginOrSelection() async throws {
        for kind in [ProviderKind.jellyfin, .emby] {
            let original = account(provider: kind)
            let store = AccountStore(secureStore: InMemorySecureStore())
            try store.add(original, token: "fixture-token")
            store.setActiveAccountIDs([])
            let http = RedirectedMediaBrowserHTTP()
            let count = await ServerNameRefresher(accountStore: store, http: http).refresh()
            XCTAssertEqual(count, 1)
            let saved = try XCTUnwrap(store.loadAccounts().first)
            XCTAssertEqual(saved.server.baseURL.absoluteString, "https://media.example/secure")
            XCTAssertEqual(saved.id, original.id)
            XCTAssertEqual(saved.server.id, original.server.id)
            XCTAssertEqual(saved.server.provider, kind)
            XCTAssertEqual(saved.userID, original.userID)
            XCTAssertEqual(saved.credentialRevision, original.credentialRevision)
            XCTAssertEqual(saved.addedAt, original.addedAt)
            XCTAssertEqual(store.token(for: saved.id), "fixture-token")
            XCTAssertEqual(store.activeAccountIDs(), [])

            let libraries = try await JellyfinProvider(
                session: saved.session(token: "fixture-token"), http: http
            ).libraries()
            XCTAssertEqual(libraries.map(\.id), ["movies", "\(kind.rawValue):collections"])
            XCTAssertEqual(libraries.last?.hasCollections, false)
            let requests = await http.requests
            XCTAssertTrue(requests.filter { $0.1.path == "/System/Info/Public" }.allSatisfy { $0.1.headers.isEmpty })
            let libraryRequests = requests.filter {
                $0.1.path == "/Users/user/Views" || $0.1.path == "/Users/user/Items"
            }
            XCTAssertEqual(libraryRequests.count, 2)
            XCTAssertTrue(libraryRequests.allSatisfy { $0.0 == saved.server.baseURL })
            XCTAssertTrue(libraryRequests.allSatisfy { $0.1.redirectPolicy == .sameOrigin })
        }
    }

    func testRedirectedIdentityMismatchDoesNotChangeSavedAccount() async throws {
        let original = account()
        let store = AccountStore(secureStore: InMemorySecureStore())
        try store.add(original, token: "fixture-token")
        let count = await ServerNameRefresher(
            accountStore: store, http: RedirectedMediaBrowserHTTP(serverID: "different")
        ).refresh()
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.loadAccounts(), [original])
        XCTAssertEqual(store.token(for: original.id), "fixture-token")
    }

    func testUnchangedAndOfflineAccountsAreNotRewritten() async throws {
        for offline in [false, true] {
            var original = account()
            original.server.baseURL = URL(string: "https://media.example/secure")!
            let store = AccountStore(secureStore: InMemorySecureStore())
            try store.add(original, token: "fixture-token")
            let http = RedirectedMediaBrowserHTTP(beforePublicResponse: {
                if offline { throw AppError.serverUnreachable }
            })
            let count = await ServerNameRefresher(accountStore: store, http: http).refresh()
            XCTAssertEqual(count, 0)
            XCTAssertEqual(store.loadAccounts(), [original])
        }
    }

    func testMetadataCancellationDoesNotCompleteSignInOrRepairAnAccount() async throws {
        let original = account()
        let http = RedirectedMediaBrowserHTTP(beforePublicResponse: { throw AppError.cancelled })
        let store = AccountStore(secureStore: InMemorySecureStore())
        try store.add(original, token: "fixture-token")
        let count = await ServerNameRefresher(accountStore: store, http: http).refresh()
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.loadAccounts(), [original])
        do {
            _ = try await PasswordSignInService(server: original.server, deviceID: "device", http: http)
                .signIn(username: "viewer", password: "fixture")
            XCTFail("Cancelled public metadata must not complete sign-in.")
        } catch let error as AppError { XCTAssertEqual(error, .cancelled) }
    }

    func testRedirectedSignInMetadataMustMatchTheAuthenticatedServer() async throws {
        let http = RedirectedMediaBrowserHTTP(serverID: "different")
        do {
            _ = try await PasswordSignInService(server: account().server, deviceID: "device", http: http)
                .signIn(username: "viewer", password: "fixture")
            XCTFail("A token must not be attached to a different redirected server.")
        } catch let error as AppError { XCTAssertEqual(error, .invalidResponse) }
        do {
            _ = try await QuickConnectService(server: account().server, deviceID: "device", http: http)
                .awaitApproval(for: .init(secret: "fixture", userCode: "1234", isAuthenticated: false))
            XCTFail("Quick Connect must also retain authenticated server identity.")
        } catch let error as AppError { XCTAssertEqual(error, .invalidResponse) }
    }

    func testRefreshCannotRestoreRemovedAccountOrOverwriteNewCredentials() async throws {
        for remove in [true, false] {
            let original = account()
            let store = AccountStore(secureStore: InMemorySecureStore())
            try store.add(original, token: "old-token")
            let http = RedirectedMediaBrowserHTTP(beforePublicResponse: {
                if remove {
                    try store.remove(id: original.id)
                } else {
                    var changed = original
                    changed.credentialRevision = CredentialRevision()
                    try store.add(changed, token: "new-token")
                }
            })
            let count = await ServerNameRefresher(accountStore: store, http: http).refresh()
            XCTAssertEqual(count, 0)
            if remove {
                XCTAssertTrue(store.loadAccounts().isEmpty)
                XCTAssertNil(store.token(for: original.id))
            } else {
                XCTAssertEqual(store.loadAccounts().first?.server.baseURL, original.server.baseURL)
                XCTAssertEqual(store.token(for: original.id), "new-token")
            }
        }
    }

    func testPasswordAndQuickConnectSessionsRetainResolvedAddressAndAvatarOrigin() async throws {
        for kind in [ProviderKind.jellyfin, .emby] {
            let session = try await PasswordSignInService(
                server: account(provider: kind).server, deviceID: "device", http: RedirectedMediaBrowserHTTP()
            ).signIn(username: "viewer", password: "fixture")
            XCTAssertEqual(session.server.baseURL.absoluteString, "https://media.example/secure")
            XCTAssertEqual(session.server.provider, kind)
            XCTAssertEqual(session.avatarURL?.scheme, "https")
            XCTAssertEqual(session.avatarURL?.path, "/secure/Users/user/Images/Primary")
        }
        let session = try await QuickConnectService(
            server: account().server, deviceID: "device", http: RedirectedMediaBrowserHTTP()
        ).awaitApproval(for: .init(secret: "fixture", userCode: "1234", isAuthenticated: false))
        XCTAssertEqual(session.server.baseURL.absoluteString, "https://media.example/secure")
        XCTAssertEqual(session.avatarURL?.scheme, "https")
    }
}

private actor RedirectedMediaBrowserHTTP: HTTPClient {
    let serverID: String
    let beforePublicResponse: @Sendable () throws -> Void
    var requests: [(URL, Endpoint)] = []

    init(serverID: String = "server", beforePublicResponse: @escaping @Sendable () throws -> Void = {}) {
        self.serverID = serverID
        self.beforePublicResponse = beforePublicResponse
    }

    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append((baseURL, endpoint))
        let json: String
        var responseURL = baseURL.appendingPathComponent(endpoint.path)
        switch endpoint.path {
        case "/System/Info/Public":
            try beforePublicResponse()
            json = #"{"Id":"\#(serverID)","ServerName":"Home","Version":"12.0.0"}"#
            responseURL = URL(string: "https://media.example/secure/System/Info/Public")!
        case "/Users/AuthenticateByName", "/Users/AuthenticateWithQuickConnect":
            json = #"{"AccessToken":"fixture-token","ServerId":"server","User":{"Id":"user","Name":"Viewer"}}"#
        case "/QuickConnect/Connect":
            json = #"{"Secret":"fixture","Code":"1234","Authenticated":true}"#
        case "/Users/user/Views":
            guard baseURL.scheme == "https" else { throw AppError.invalidResponse }
            json = #"{"Items":[{"Id":"movies","Name":"Movies","CollectionType":"movies"}]}"#
        case "/Users/user/Items":
            json = #"{"Items":[],"TotalRecordCount":0}"#
        default:
            throw AppError.notFound
        }
        return (Data(json.utf8), HTTPURLResponse(url: responseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
