import XCTest
import CoreModels
@testable import FeatureAuthCore

@MainActor
final class AccountReauthenticationTests: XCTestCase {
    func testEveryManagedProviderPreservesAccountIdentityAndSelections() throws {
        for provider in ProviderKind.allCases where provider.supportsAccountReauthentication {
            let store = AccountStore(secureStore: InMemorySecureStore())
            let account = fixture(provider)
            try store.add(account, token: "OLD")
            store.setActiveAccountIDs([])
            var completed = false
            let model = AccountReauthenticationModel(
                account: account, deviceID: "device", store: store,
                isAuthorized: { true }, onComplete: { completed = true }
            )
            try model.complete(account.session(token: "NEW"))
            let saved = try XCTUnwrap(store.loadAccounts().first)
            XCTAssertTrue(completed, "\(provider)")
            XCTAssertEqual(saved.id, account.id)
            XCTAssertEqual(saved.addedAt, account.addedAt)
            XCTAssertEqual(saved.server.alternateConnectionURLs, account.server.alternateConnectionURLs)
            XCTAssertEqual(saved.userID, account.userID)
            XCTAssertEqual(store.loadAccounts().count, 1)
            XCTAssertTrue(store.activeAccountIDs().isEmpty)
            XCTAssertEqual(store.token(for: account.id), "NEW")
            XCTAssertNotEqual(saved.credentialRevision, account.credentialRevision)
        }
    }

    func testWrongUserNeverAddsAnAccountOrReplacesTheOriginal() throws {
        for provider in ProviderKind.allCases where provider.supportsAccountReauthentication {
            let store = AccountStore(secureStore: InMemorySecureStore())
            let account = fixture(provider)
            try store.add(account, token: "OLD")
            let model = AccountReauthenticationModel(
                account: account, deviceID: "device", store: store,
                isAuthorized: { true }, onComplete: { XCTFail("Wrong account cannot complete recovery.") }
            )
            var session = account.session(token: "WRONG")
            session.userID = "different-user"
            XCTAssertThrowsError(try model.complete(session))
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(store.loadAccounts(), [account])
            XCTAssertEqual(store.token(for: account.id), "OLD")
            model.retry()
            XCTAssertNil(model.errorMessage)
        }
    }

    func testCancellationAndProfileAuthorizationChangeRejectCompletion() throws {
        for cancel in [false, true] {
            let store = AccountStore(secureStore: InMemorySecureStore())
            let account = fixture(.jellyfin)
            try store.add(account, token: "OLD")
            var authorized = true
            let model = AccountReauthenticationModel(
                account: account, deviceID: "device", store: store,
                isAuthorized: { authorized }, onComplete: { XCTFail("Stale recovery cannot complete.") }
            )
            if cancel { model.cancel() } else { authorized = false }
            XCTAssertThrowsError(try model.complete(account.session(token: "NEW")))
            XCTAssertEqual(store.token(for: account.id), "OLD")
            XCTAssertNotNil(model.errorMessage)
        }
    }

    func testConcurrentAccountRemovalCannotBeUndoneByRecovery() throws {
        let store = AccountStore(secureStore: InMemorySecureStore())
        let account = fixture(.emby)
        try store.add(account, token: "OLD")
        let model = AccountReauthenticationModel(
            account: account, deviceID: "device", store: store,
            isAuthorized: { true }, onComplete: { XCTFail("Removed account must stay removed.") }
        )
        try store.remove(id: account.id)
        XCTAssertThrowsError(try model.complete(account.session(token: "NEW")))
        XCTAssertTrue(store.loadAccounts().isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    func testSaveFailureRemainsRetryableWithoutCompletingOrRemovingAccount() throws {
        let store = AccountStore(secureStore: RejectedRecoveryCredentialStore())
        let account = fixture(.jellyfin)
        try store.add(account, token: "OLD")
        var completed = false
        let model = AccountReauthenticationModel(
            account: account, deviceID: "device", store: store,
            isAuthorized: { true }, onComplete: { completed = true }
        )
        XCTAssertThrowsError(try model.complete(account.session(token: "REJECT")))
        XCTAssertFalse(completed)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(store.loadAccounts(), [account])
        XCTAssertEqual(store.token(for: account.id), "OLD")
        model.retry()
        try model.complete(account.session(token: "NEW"))
        XCTAssertTrue(completed)
        XCTAssertEqual(store.token(for: account.id), "NEW")
    }

    func testPasswordSignInDoesNotReportSuccessWhenSavingFails() async throws {
        let http = StubHTTPClient()
        http.stubFixed(pathSuffix: "/Users/AuthenticateByName", json: """
        {"AccessToken":"TOK","ServerId":"server","User":{"Id":"user","Name":"User"}}
        """)
        var saved = false
        let model = PasswordSignInViewModel(
            service: PasswordSignInService(server: fixture(.jellyfin).server, deviceID: "device", http: http),
            onAuthenticated: { _ in
                saved = true
                throw AccountStoreError.encodingFailed
            }
        )
        defer { model.cancel() }
        model.username = "User"
        model.password = "password"
        model.submit()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.phase == .submitting, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(saved)
        guard case .error = model.phase else { return XCTFail("Persistence failure must remain in sign-in.") }
        XCTAssertTrue(model.canSubmit)
    }

    func testQuickConnectDoesNotReportSuccessWhenSavingFails() async throws {
        let http = StubHTTPClient()
        http.stubFixed(pathSuffix: "/QuickConnect/Enabled", json: "true")
        http.stubFixed(pathSuffix: "/QuickConnect/Initiate", json: #"{"Authenticated":false,"Secret":"SEC","Code":"654321"}"#)
        http.stubFixed(pathSuffix: "/QuickConnect/Connect", json: #"{"Authenticated":true,"Secret":"SEC","Code":"654321"}"#)
        http.stubFixed(pathSuffix: "/Users/AuthenticateWithQuickConnect", json: """
        {"AccessToken":"TOK","ServerId":"server","User":{"Id":"user","Name":"User"}}
        """)
        var saved = false
        let model = QuickConnectViewModel(
            service: QuickConnectService(
                server: fixture(.jellyfin).server, deviceID: "device", http: http,
                config: .init(pollInterval: 0.01, timeout: 120), sleep: { _ in }
            ),
            onAuthenticated: { _ in
                saved = true
                throw AccountStoreError.encodingFailed
            }
        )
        defer { model.cancel() }
        model.start()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !saved, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(saved)
        guard case .error = model.phase else { return XCTFail("Persistence failure must remain in sign-in.") }
    }

    private func fixture(_ provider: ProviderKind) -> Account {
        Account(
            id: "legacy", server: MediaServer(
                id: "server", name: "Fixture", baseURL: URL(string: "https://server.example")!,
                provider: provider, alternateConnectionURLs: [URL(string: "https://alternate.example")!]
            ), userID: "user", userName: "User", deviceID: "device",
            addedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private final class RejectedRecoveryCredentialStore: SecureStore, @unchecked Sendable {
        private let base = InMemorySecureStore()

        func setString(_ value: String, for key: String) throws {
            if value == "REJECT" { throw AccountStoreError.encodingFailed }
            try base.setString(value, for: key)
        }

        func insertStringIfAbsent(_ value: String, for key: String) throws -> Bool {
            try base.insertStringIfAbsent(value, for: key)
        }

        func string(for key: String) -> String? { base.string(for: key) }
        func readString(for key: String) throws -> String? { try base.readString(for: key) }
        func removeValue(for key: String) throws { try base.removeValue(for: key) }
    }
}
