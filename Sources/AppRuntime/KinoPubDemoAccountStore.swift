import CoreModels
import FeatureAuthCore
import Foundation
import ProviderKinoPubDemo

/// An in-memory account store holding one fake kino.pub account.
///
/// Lives here rather than beside the provider because `AccountPersisting` is a
/// Feature-layer protocol, and a Provider module is not allowed to reach up
/// into Features — `tools/arch-guard.py` enforces that. Wiring an account is
/// composition-root work anyway, which is what this module is for.
///
/// The demo must look signed in without writing anything: no Keychain item, no
/// `UserDefaults` key, nothing that survives the process. Quitting the demo
/// leaves the device exactly as it was.
public final class KinoPubDemoAccountStore: AccountPersisting, @unchecked Sendable {
    public static let accountID = KinoPubDemo.accountID

    private let account: Account
    private let lock = NSLock()
    private var active: [String]

    public init() {
        let server = MediaServer(
            id: "kinopub-demo-server",
            name: "kino.pub",
            baseURL: URL(string: "https://api.service-kp.com")!,
            provider: .jellyfin
        )
        account = Account(
            id: Self.accountID,
            server: server,
            userID: "demo",
            userName: "Демо",
            deviceID: "kinopub-demo-device"
        )
        active = [Self.accountID]
    }

    public func deviceID() -> String { account.deviceID }
    public func loadAccounts() -> [Account] { [account] }

    public func activeAccountIDs() -> [String] {
        lock.withLock { active }
    }

    public func setActiveAccountIDs(_ ids: [String]) {
        lock.withLock { active = ids }
    }

    /// Any non-empty string works: the demo provider never reads it, but the
    /// accounts hub treats a `nil` token as "not signed in" and hides Home.
    public func token(for accountID: String) -> String? { "demo-token" }

    public func mediaShareCredential(for accountID: String) throws -> MediaShareCredentialEnvelope {
        throw AccountStoreError.invalidMediaShareAccount
    }

    public func mediaShareCredential(
        for accountID: String,
        revision: CredentialRevision
    ) throws -> MediaShareCredentialEnvelope {
        throw AccountStoreError.invalidMediaShareAccount
    }

    public func add(_ account: Account, token: String) throws {}
    public func addMediaShare(
        _ account: Account,
        credential: MediaShareCredentialEnvelope,
        generatedPrivateKey: String?
    ) throws {}
    public func remove(id: String) throws {}
    public func clearAll() throws {}
    public func recoverCredentialMutations() throws {}
}
