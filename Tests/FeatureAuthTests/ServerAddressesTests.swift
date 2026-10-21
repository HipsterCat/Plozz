import Foundation
import XCTest
import CoreModels
import CoreNetworking
import ProviderSilo
@testable import FeatureAuthCore

@MainActor
final class ServerAddressesTests: XCTestCase {
    private func account(_ provider: ProviderKind = .jellyfin) -> Account {
        Account(
            id: "account", server: MediaServer(id: "server", name: "Home",
                baseURL: URL(string: "https://original.test/base")!, provider: provider),
            userID: "user:profile", userName: "Viewer", deviceID: "device"
        )
    }

    func testAddRemovePreserveCredentialIdentityAndInactiveSelection() async throws {
        for provider in [ProviderKind.jellyfin, .emby, .plex] {
            let saved = account(provider)
            let store = AccountStore(secureStore: InMemorySecureStore())
            try store.add(saved, token: "existing-credential")
            store.setActiveAccountIDs([])
            let http = AddressVerificationHTTP(provider: provider)
            var changes = 0
            let model = ServerAddressesModel(account: saved, store: store, http: http,
                isAuthorized: { true }, onChanged: { changes += 1 })
            model.address = "http://192.168.1.50:8096/alternate"
            await model.add()
            XCTAssertNil(model.errorMessage)
            let updated = try XCTUnwrap(store.loadAccounts().first)
            XCTAssertEqual(updated.id, saved.id)
            XCTAssertEqual(updated.server.id, saved.server.id)
            XCTAssertEqual(updated.server.baseURL, saved.server.baseURL)
            XCTAssertEqual(updated.credentialRevision, saved.credentialRevision)
            XCTAssertEqual(updated.userID, saved.userID)
            XCTAssertEqual(store.token(for: saved.id), "existing-credential")
            XCTAssertEqual(store.activeAccountIDs(), [])
            XCTAssertEqual(updated.server.alternateConnectionURLs?.count, 1)
            let requests = await http.requests
            XCTAssertTrue(requests.allSatisfy { $0.headers["Authorization"] == nil && $0.headers["X-Plex-Token"] == nil })
            XCTAssertTrue(requests.allSatisfy { $0.redirectPolicy == .sameOrigin })
            model.remove(try XCTUnwrap(model.alternatives.first))
            XCTAssertNil(store.loadAccounts().first?.server.alternateConnectionURLs)
            XCTAssertEqual(changes, 2)
        }
    }

    func testWrongServerAndRevokedManagementCannotSave() async throws {
        for allowed in [true, false] {
            let saved = account()
            let store = AccountStore(secureStore: InMemorySecureStore())
            try store.add(saved, token: "original")
            let model = ServerAddressesModel(account: saved, store: store,
                http: AddressVerificationHTTP(provider: .jellyfin, serverID: "different"),
                isAuthorized: { allowed }, onChanged: { XCTFail("Must not save") })
            model.address = "https://alternate.test"
            await model.add()
            XCTAssertEqual(store.loadAccounts(), [saved])
            if allowed { XCTAssertNotNil(model.errorMessage) }
        }
    }

    func testRemovedOrConcurrentlyChangedAccountCannotBeOverwritten() throws {
        let saved = account()
        let store = AccountStore(secureStore: InMemorySecureStore())
        try store.add(saved, token: "original")
        let first = URL(string: "https://first.test")!
        try store.updateServerAddresses(expected: saved, alternatives: [first])
        XCTAssertThrowsError(try store.updateServerAddresses(expected: saved, alternatives: []))
        XCTAssertEqual(store.loadAccounts().first?.server.alternateConnectionURLs, [first])
        try store.remove(id: saved.id)
        XCTAssertThrowsError(try store.updateServerAddresses(expected: saved, alternatives: [first]))
        XCTAssertTrue(store.loadAccounts().isEmpty)
    }

    func testAddressValidationRejectsCredentialsQueriesFragmentsAndNonHTTP() throws {
        for raw in [
            "https://user:password@server.test", "https://server.test?token=test",
            "https://server.test#fragment", "ftp://server.test", "file:///tmp/server",
            "https://server.test:0", "https://server.test/../elsewhere"
        ] {
            XCTAssertThrowsError(try ServerAddressesModel.normalizedAddress(raw, provider: .jellyfin), raw)
        }
        XCTAssertEqual(try ServerAddressesModel.normalizedAddress("192.168.1.50", provider: .silo).absoluteString,
                       "http://192.168.1.50:8090")
    }

    func testOldMetadataDecodesAndApprovedAliasesStayOutOfSync() throws {
        let original = account()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original.server)) as? [String: Any])
        object.removeValue(forKey: "alternateConnectionURLs")
        let restored = try JSONDecoder().decode(MediaServer.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.alternateConnectionURLs)
        var updated = original
        updated.server.alternateConnectionURLs = [URL(string: "http://192.168.1.50:8096")!]
        XCTAssertEqual(SyncedAccountDescriptor(account: updated), SyncedAccountDescriptor(account: original))
    }

    func testCancelledRevokedOrRemovedAccountCannotSaveAfterVerificationReturns() async throws {
        for change in ["cancel", "permission", "remove"] {
            let saved = account()
            let store = AccountStore(secureStore: InMemorySecureStore())
            try store.add(saved, token: "original")
            let http = AddressVerificationHTTP(provider: .jellyfin, hold: true)
            var authorized = true
            let model = ServerAddressesModel(account: saved, store: store, http: http,
                isAuthorized: { authorized }, onChanged: { XCTFail("Stale operation saved") })
            model.address = "https://alternate.test"
            let task = Task { await model.add() }
            await http.waitUntilRequested()
            if change == "cancel" { model.cancel(); task.cancel() }
            if change == "permission" { authorized = false }
            if change == "remove" { try store.remove(id: saved.id) }
            await http.release()
            await task.value
            XCTAssertTrue(model.alternatives.isEmpty)
            XCTAssertNil(store.loadAccounts().first?.server.alternateConnectionURLs)
        }
    }

    func testSiloMismatchCancellationOrCleanupFailureNeverApprovesAddress() async throws {
        for mismatch in ["installation", "user", "device", "url", "cancel", "cleanup"] {
            let saved = account(.silo)
            let store = AccountStore(secureStore: InMemorySecureStore())
            try store.add(saved, token: "original-login")
            let http = AddressVerificationHTTP(provider: .silo, fails: mismatch == "cleanup")
            let model = ServerAddressesModel(account: saved, store: store, http: http,
                isAuthorized: { true }, onChanged: { XCTFail("Invalid pairing saved") })
            model.address = "https://alternate.test"
            await model.add()
            var verified = try verificationSession(server: XCTUnwrap(model.pairingServer), saved: saved)
            switch mismatch {
            case "installation": verified.server.id = "different"
            case "user": verified.userID = "different"
            case "device": verified.deviceID = "different"
            case "url": verified.server.baseURL = URL(string: "https://different.test")!
            case "cancel": model.cancel()
            default: break
            }
            await model.completePairing(verified)
            XCTAssertTrue(model.alternatives.isEmpty)
            XCTAssertEqual(store.loadAccounts(), [saved])
            XCTAssertEqual(store.token(for: saved.id), "original-login")
            let requests = await http.requests
            XCTAssertEqual(requests.map(\.path), ["/api/v2/auth/logout"])
            XCTAssertEqual(requests.first?.headers["Authorization"], "Bearer verification-access")
        }
    }

    func testSiloDoesNotSendSavedCredentialBeforePairingAndKeepsOriginalLogin() async throws {
        let saved = account(.silo)
        let store = AccountStore(secureStore: InMemorySecureStore())
        try store.add(saved, token: "original-login")
        let http = AddressVerificationHTTP(provider: .silo)
        let model = ServerAddressesModel(account: saved, store: store, http: http,
            isAuthorized: { true }, onChanged: {})
        model.address = "https://alternate.test"
        await model.add()
        let beforePairing = await http.requests
        XCTAssertTrue(beforePairing.isEmpty)
        XCTAssertEqual(store.loadAccounts(), [saved])
        let server = try XCTUnwrap(model.pairingServer)
        let verified = try verificationSession(server: server, saved: saved)
        await model.completePairing(verified)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.alternatives, [server.baseURL])
        XCTAssertEqual(store.token(for: saved.id), "original-login")
        XCTAssertEqual(store.loadAccounts().first?.credentialRevision, saved.credentialRevision)
        let requests = await http.requests
        XCTAssertEqual(requests.map(\.path), ["/api/v2/auth/logout"])
        XCTAssertEqual(requests.first?.headers["Authorization"], "Bearer verification-access")
    }

    private func verificationSession(server: MediaServer, saved: Account) throws -> UserSession {
        let tokens = try JSONDecoder().decode(SiloTokenPair.self, from: Data(
            #"{"access_token":"verification-access","refresh_token":"verification-refresh","expires_in":3600,"user":{"id":"user","username":"Viewer"}}"#.utf8))
        let profile = try JSONDecoder().decode(SiloProfile.self, from: Data(
            #"{"id":"profile","name":"Viewer","has_pin":false,"is_child":false}"#.utf8))
        let raw = try SiloCredential(tokens: tokens, profile: profile, profileToken: nil).encoded()
        return UserSession(server: server, userID: saved.userID, userName: saved.userName,
                           deviceID: saved.deviceID, accessToken: raw)
    }
}

private actor AddressVerificationHTTP: HTTPClient {
    let provider: ProviderKind
    let serverID: String
    let hold: Bool
    let fails: Bool
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    var requests: [Endpoint] = []
    init(provider: ProviderKind, serverID: String = "server", hold: Bool = false, fails: Bool = false) {
        self.provider = provider
        self.serverID = serverID
        self.hold = hold
        self.fails = fails
    }
    func waitUntilRequested() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { pending?.resume(); pending = nil }
    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append(endpoint)
        if hold {
            await withCheckedContinuation {
                pending = $0
                observer?.resume()
                observer = nil
            }
        }
        if fails { throw AppError.serverUnreachable }
        let object: [String: Any] = provider == .plex
            ? ["MediaContainer": ["machineIdentifier": serverID]] : ["Id": serverID]
        return (try JSONSerialization.data(withJSONObject: object),
                HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
