import CoreModels
import CoreSecureStore
import FeatureAuthCore
import Foundation
import XCTest
@testable import AppRuntime

@MainActor
final class HomeLiveTVPersistenceTests: XCTestCase {
    func testPortableApplyForAnotherProfilePreservesDisplayedSnapshotPendingRouteAndDiskCache() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HomeLiveTVSnapshotStore(profileID: "active", directory: directory)
        let model = HomeLiveTVModel(profileID: "active", store: store)
        let channel = HomeLiveTVChannel(
            route: .init(
                profileID: "active", channelID: "news", sourceID: "source",
                sourceAuthorizationID: "approval", serverAuthorizationID: "servers"
            ), name: "News", sourceName: "Source", number: 1
        )
        let snapshot = HomeLiveTVSnapshot(recentChannels: [channel], channels: [channel])
        model.publish(snapshot)
        XCTAssertTrue(model.request(channel.route, in: snapshot))
        let request = model.pendingRequest
        XCTAssertFalse(HomeLiveTVRuntime.applyPortableStateChange(
            Notification(name: .plozzLiveTVPortableStateDidApply, object: "another"), to: model
        ))
        XCTAssertEqual(model.snapshot, snapshot)
        XCTAssertEqual(model.pendingRequest, request)
        XCTAssertEqual(store.load(), snapshot)
        XCTAssertTrue(HomeLiveTVRuntime.applyPortableStateChange(
            Notification(name: .plozzLiveTVPortableStateDidApply, object: "active"), to: model
        ))
        XCTAssertTrue(model.snapshot.isEmpty)
        XCTAssertNil(model.pendingRequest)
        XCTAssertTrue(store.load().isEmpty)
    }

    private func account(kind: ProviderKind = .plex) -> Account {
        Account(
            id: "account",
            server: MediaServer(
                id: "server", name: "Server", baseURL: URL(string: "https://example.test")!, provider: kind
            ),
            userID: "owner", userName: "Owner", deviceID: "device"
        )
    }

    func testDurableCredentialScopeSurvivesRelaunchButNotCredentialOrServerChanges() throws {
        let account = account()
        let reloaded = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(account))
        func scope(_ value: Account, profile: String = "profile", hasCredential: Bool = true) -> String? {
            HomeLiveTVRuntime.durableAuthorizationID(
                profileID: profile, accounts: [value], hasCredential: { _ in hasCredential }
            )
        }
        let original = try XCTUnwrap(scope(account))
        XCTAssertEqual(scope(reloaded), original)
        XCTAssertEqual(original.count, 64)
        XCTAssertNotEqual(scope(account, profile: "other"), original)
        XCTAssertNil(scope(account, hasCredential: false))
        var rotated = reloaded
        rotated.credentialRevision = CredentialRevision()
        XCTAssertNotEqual(scope(rotated), original)
        var user = reloaded
        user.userID = "different-server-user"
        XCTAssertNotEqual(scope(user), original)
        var server = reloaded
        server.server.baseURL = URL(string: "https://other.example.test")!
        XCTAssertNotEqual(scope(server), original)
    }

    func testRuntimeScopeSurvivesEphemeralOverridesButRechecksCredentialsAndBaseRevision() throws {
        let suite = "HomeLiveTVCredentialScope-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secure = InMemorySecureStore()
        let accountStore = AccountStore(secureStore: secure)
        let account = account()
        try accountStore.add(account, token: "fixture-credential")
        accountStore.setActiveAccountIDs([account.id])
        let profiles = ProfilesModel(
            store: ProfileStore(defaults: defaults, secureStore: secure), defaultActiveAccountIDs: [account.id]
        )
        func runtime() -> AccountsProvidersModel {
            let accounts = AccountsProvidersModel(
                accountStore: accountStore, registry: ProviderRegistry(), profilesModel: profiles
            )
            let ephemeralRevision = CredentialRevision()
            accounts.credentialRevision = { _ in ephemeralRevision }
            accounts.tokenResolver = { accountStore.token(for: $0) }
            accounts.reloadAccounts()
            return accounts
        }
        let first = runtime()
        let relaunched = runtime()
        XCTAssertNotEqual(first.liveTVAuthorizationID, relaunched.liveTVAuthorizationID)
        func scope(_ accounts: AccountsProvidersModel) -> String? {
            HomeLiveTVRuntime.authorizationID(profileID: profiles.activeProfileID, accounts: accounts)
        }
        let original = try XCTUnwrap(scope(first))
        XCTAssertEqual(scope(relaunched), original)
        relaunched.tokenResolver = { _ in nil }
        XCTAssertNil(scope(relaunched), "A cached digest cannot preserve missing credential access.")
        relaunched.tokenResolver = { accountStore.token(for: $0) }
        XCTAssertEqual(scope(relaunched), original)
        var rotated = account
        rotated.credentialRevision = CredentialRevision()
        try accountStore.add(rotated, token: "replacement-fixture-credential")
        relaunched.reloadAccounts()
        let rotatedScope = try XCTUnwrap(scope(relaunched))
        XCTAssertNotEqual(rotatedScope, original, "Base rotation must invalidate even a retained Plex override.")
    }

    func testRelaunchedSnapshotIsFilteredBeforeDisplayAndCannotTuneAcrossScopeChanges() throws {
        let suite = "HomeLiveTVPersistence-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let base = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let directory = base.appendingPathComponent(suite, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = account()
        let profile = Profile(
            id: UUID().uuidString, name: "Profile", plexHomeUserID: "child", plexHomeUserAccountID: account.id
        )
        let configuration = LiveTVSourcesConfiguration(servers: [
            .init(id: "source", name: "Server", accountID: account.id)
        ])
        let approvals = LiveTVSourceApprovalStore(defaults: defaults, profileID: profile.id)
        func authorization(_ profile: Profile) throws -> LiveTVSourceAuthorization {
            try approvals.authorization(
                context: .init(profile: profile, parentalPIN: nil, activeAccountIDs: [account.id]),
                configuration: configuration
            )
        }
        let auth = try authorization(profile)
        let scope = try XCTUnwrap(HomeLiveTVRuntime.durableAuthorizationID(
            profileID: profile.id, accounts: [account], hasCredential: { _ in true }
        ))
        let card = HomeLiveTVChannel(
            route: .init(
                profileID: profile.id, channelID: "channel", sourceID: "source", accountID: account.id,
                sourceAuthorizationID: auth.identity, serverAuthorizationID: scope
            ), name: "Channel", sourceName: "Server", number: 1
        )
        let model = HomeLiveTVModel(
            profileID: profile.id, store: HomeLiveTVSnapshotStore(profileID: profile.id, directory: directory)
        )
        model.publish(.init(recentChannels: [card], channels: [card]))
        let relaunched = HomeLiveTVModel(
            profileID: profile.id, store: HomeLiveTVSnapshotStore(profileID: profile.id, directory: directory)
        )
        func visible(scope: String, authorization: LiveTVSourceAuthorization) -> HomeLiveTVSnapshot {
            HomeLiveTVRuntime.visibleSnapshot(
                cached: relaunched.snapshot, profileID: profile.id, serverAuthorizationID: scope,
                configuration: configuration, authorization: authorization,
                preferences: .init(recentChannelIDs: ["channel"])
            )
        }
        XCTAssertEqual(visible(scope: scope, authorization: auth).recentChannels, [card])
        XCTAssertNil(LiveTVCatalogStorage.existingCache(profileID: profile.id))
        XCTAssertNil(relaunched.pendingRequest, "Cache hydration must not tune.")

        var changedUser = profile
        changedUser.plexHomeUserID = "other-child"
        let hiddenForUser = visible(scope: scope, authorization: try authorization(changedUser))
        XCTAssertTrue(hiddenForUser.isEmpty)
        XCTAssertFalse(relaunched.request(card.route, in: hiddenForUser))
        var rotated = account
        rotated.credentialRevision = CredentialRevision()
        let rotatedScope = try XCTUnwrap(HomeLiveTVRuntime.durableAuthorizationID(
            profileID: profile.id, accounts: [rotated], hasCredential: { _ in true }
        ))
        let hiddenForCredential = visible(scope: rotatedScope, authorization: auth)
        XCTAssertTrue(hiddenForCredential.isEmpty)
        XCTAssertFalse(relaunched.request(card.route, in: hiddenForCredential))
        XCTAssertNil(relaunched.pendingRequest)
    }
}
