import Foundation
import CoreModels
import FeatureAuthCore

/// One trusted startup session, never a cache for switching users.
public struct AutomaticSignInStore {
    struct Session: Codable {
        struct ProfileAccess: Codable, Equatable {
            let id: String
            let lock: ProfileLock?
            let lockRevision: ProfileLockRevision?

            init(_ profile: Profile) {
                id = profile.id
                lock = profile.lock
                lockRevision = profile.effectiveLockRevision
            }
        }

        struct AccountAccess: Codable, Equatable {
            let id: String
            let credentialRevision: CredentialRevision
            let homeUserID: String?
            let requiresPIN: Bool?

            init(_ account: Account, profile: Profile) {
                id = account.id
                credentialRevision = account.credentialRevision
                let binding = account.server.provider == .plex
                    ? profile.homeUserBinding(forPlexAccount: account.id) : nil
                homeUserID = binding?.homeUserID
                requiresPIN = binding?.requiresPIN
            }
        }

        struct PlexCredential: Codable {
            let serverToken: String
            let discoverToken: String
        }

        let profile: ProfileAccess
        let accounts: [AccountAccess]
        let plexCredentials: [String: PlexCredential]
    }

    private let defaults: UserDefaults
    private let secureStore: any SecureStoring
    private static let enabledKey = "plozz.device.automaticallySignIn"
    private static let sessionKey = "startupSession"

    public init(defaults: UserDefaults, secureStore: any SecureStoring) {
        self.defaults = defaults
        self.secureStore = secureStore
    }

    public static func makeDefault() -> Self {
        #if canImport(Security)
        Self(
            defaults: .standard,
            secureStore: KeychainStore(
                service: "com.plozz.app.automaticSignIn",
                userIndependent: false,
                synchronizable: false
            )
        )
        #else
        Self(defaults: .standard, secureStore: InMemorySecureStore())
        #endif
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    func load() throws -> Session? {
        guard isEnabled,
              let raw = try secureStore.readString(for: Self.sessionKey) else { return nil }
        return try JSONDecoder().decode(Session.self, from: Data(raw.utf8))
    }

    func save(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)
        try secureStore.setString(String(decoding: data, as: UTF8.self), for: Self.sessionKey)
    }

    func enable(with session: Session) throws {
        try save(session)
        defaults.set(true, forKey: Self.enabledKey)
    }

    func invalidate() throws {
        try secureStore.removeValue(for: Self.sessionKey)
    }

    func disable() throws {
        // Fail closed even if Keychain deletion is temporarily unavailable.
        blockRestoration()
        try invalidate()
    }

    func blockRestoration() {
        defaults.set(false, forKey: Self.enabledKey)
    }
}
