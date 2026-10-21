import XCTest
import Synchronization
import CoreModels
import FeatureAuth
@testable import AppShell

/// Unit tests for ``AccountsProvidersModel`` — the accounts + providers hub split
/// out of ``AppState``. Cover the hub's own behavior over in-memory stores:
/// `reloadAccounts` loads accounts and recomputes the active set, the
/// `onActiveAccountsChanged` hook fires with the resolved set, provider resolution
/// gates on the injected token seam, and the profile/device delegations hold.
/// The full active-set resolution matrix (explicit choice vs. fallback) stays
/// covered end-to-end by ServerToggleTests through AppState.
@MainActor
final class AccountsProvidersModelTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "AccountsProvidersModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func account(id: String, host: String, provider: ProviderKind = .jellyfin) -> Account {
        Account(
            id: id,
            server: MediaServer(
                id: "srv-\(id)",
                name: host,
                baseURL: URL(string: provider == .mediaShare ? "smb://\(host)/media" : "https://\(host)")!,
                provider: provider
            ),
            userID: "user-\(id)",
            userName: "User \(id)",
            deviceID: "device"
        )
    }

    private func makeModel(accountIDs: [(String, String)]) throws -> (AccountsProvidersModel, AccountStore, ProfilesModel) {
        let secrets = InMemorySecureStore()
        let store = AccountStore(
            secureStore: secrets, mediaCredentialVault: MediaCredentialVault(secureStore: secrets),
            credentialJournal: try CredentialMutationJournal(
                store: DurableLocalStateStore(secureStore: InMemorySecureStore())
            )
        )
        for (id, host) in accountIDs {
            try store.add(account(id: id, host: host), token: "token-\(id)")
        }
        let profiles = ProfilesModel(store: ProfileStore(defaults: makeDefaults()))
        let model = AccountsProvidersModel(
            accountStore: store,
            registry: ProviderRegistry(),
            profilesModel: profiles
        )
        return (model, store, profiles)
    }

    func testReloadAccountsLoadsAccountsAndFiresHook() throws {
        let (model, _, _) = try makeModel(accountIDs: [("a", "a.example.com"), ("b", "b.example.com")])

        var hookResolved: Set<String>?
        var hookAccountsCount: Int?
        model.onActiveAccountsChanged = { resolved, accounts in
            hookResolved = resolved
            hookAccountsCount = accounts.count
        }

        XCTAssertTrue(model.accounts.isEmpty)
        model.reloadAccounts()

        XCTAssertEqual(Set(model.accounts.map(\.id)), ["a", "b"])
        // The hook fires exactly with the recomputed active set + full account list.
        XCTAssertEqual(hookResolved, model.activeAccountIDs)
        XCTAssertEqual(hookAccountsCount, 2)
        // The resolved active set is a subset of the known accounts.
        XCTAssertTrue(model.activeAccountIDs.isSubset(of: ["a", "b"]))
    }

    func testAddressOnlyReloadUpdatesRetainedProviderWithoutEvictingOtherSignIns() throws {
        let (model, store, _) = try makeModel(accountIDs: [("a", "a.test"), ("b", "b.test")])
        model.registry.register(.jellyfin) { LiveTVAccountsTestProvider(session: $0.session) }
        model.tokenResolver = { _ in "fixture-token" }
        model.reloadAccounts()
        let first = try XCTUnwrap(model.provider(forAccountID: "a") as? LiveTVAccountsTestProvider)
        let unrelated = try XCTUnwrap(model.provider(forAccountID: "b") as? LiveTVAccountsTestProvider)
        let account = try XCTUnwrap(model.accounts.first { $0.id == "a" })
        let alias = URL(string: "http://192.168.1.50:8096")!
        try store.updateServerAddresses(expected: account, alternatives: [alias])
        model.reloadAccounts(updatingServerAddressesFor: account.id)
        XCTAssertTrue(try XCTUnwrap(model.provider(forAccountID: "a") as? LiveTVAccountsTestProvider) === first)
        XCTAssertTrue(try XCTUnwrap(model.provider(forAccountID: "b") as? LiveTVAccountsTestProvider) === unrelated)
        XCTAssertEqual(first.alternatives, [alias])
        XCTAssertTrue(unrelated.alternatives.isEmpty)
        XCTAssertEqual(model.accounts.first { $0.id == "a" }?.credentialRevision, account.credentialRevision)
        let updated = try XCTUnwrap(model.accounts.first { $0.id == "a" })
        try store.updateServerAddresses(expected: updated, alternatives: [])
        model.reloadAccounts(updatingServerAddressesFor: account.id)
        XCTAssertTrue(first.alternatives.isEmpty)
        XCTAssertTrue(try XCTUnwrap(model.provider(forAccountID: "a") as? LiveTVAccountsTestProvider) === first)
    }

    func testUnknownSyncedIdentityOnlyGatesWhenAnActivePlexAccountArrives() throws {
        for provider in [ProviderKind.plex, .iptv, .jellyfin, .emby, .silo, .mediaShare] {
            let (model, store, profiles) = try makeModel(accountIDs: [])
            let profileID = profiles.activeProfileID
            profiles.applySyncedMembership(
                ["arriving"], forProfile: profileID, knownNonPlexAccountIDs: []
            )
            model.tokenResolver = { _ in
                XCTFail("Admission must not resolve credentials or construct providers.")
                return nil
            }
            model.reloadAccounts()
            XCTAssertFalse(model.activeProfileAwaitsIdentity)

            try store.add(
                account(id: "arriving", host: "server.example", provider: provider),
                token: "fixture"
            )
            model.reloadAccounts()
            XCTAssertEqual(model.activeAccountIDs, ["arriving"])
            XCTAssertEqual(model.activeProfileAwaitsIdentity, provider == .plex)
            XCTAssertEqual(profiles.activeProfile.pendingIdentityAccountIDs, ["arriving"])

            profiles.setActiveAccountIDs([], for: profileID)
            model.reloadAccounts()
            XCTAssertFalse(model.activeProfileAwaitsIdentity)
            profiles.setActiveAccountIDs(["arriving"], for: profileID)
            model.reloadAccounts()
            XCTAssertEqual(model.activeProfileAwaitsIdentity, provider == .plex)

            let other = profiles.add(name: "Other", activeAccountIDs: ["arriving"])
            profiles.select(other.id)
            model.reloadAccounts()
            XCTAssertFalse(model.activeProfileAwaitsIdentity)
            profiles.select(profileID)
            model.reloadAccounts()
            XCTAssertEqual(model.activeProfileAwaitsIdentity, provider == .plex)

            var answered = profiles.activeProfile
            answered.resolveAccountAwaitingIdentity("arriving")
            profiles.update(answered)
            XCTAssertFalse(model.activeProfileAwaitsIdentity)
        }
    }

    func testProviderResolutionGatesOnTokenSeam() throws {
        let (model, _, _) = try makeModel(accountIDs: [("a", "a.example.com")])
        model.reloadAccounts()

        // No token → nil, before the registry is even consulted.
        model.tokenResolver = { _ in nil }
        XCTAssertNil(model.provider(forAccountID: "a"))
        // Unknown account id → nil regardless of the token seam.
        model.tokenResolver = { _ in "tok" }
        XCTAssertNil(model.provider(forAccountID: "does-not-exist"))
    }

    func testDeviceIDDelegatesToStore() throws {
        let (model, store, _) = try makeModel(accountIDs: [])
        XCTAssertEqual(model.deviceID, store.deviceID())
    }

    func testPrimaryActiveAccountFallsBackToFirst() throws {
        let (model, _, _) = try makeModel(accountIDs: [("a", "a.example.com"), ("b", "b.example.com")])
        model.reloadAccounts()
        // Even if the active set were empty, primaryActiveAccount falls back to the
        // first account so the signed-in UI is never empty.
        XCTAssertNotNil(model.primaryActiveAccount)
        XCTAssertTrue(["a", "b"].contains(model.primaryActiveAccount!.id))
    }

    // MARK: Active-set resolution matrix (reloadAccounts)
    // The hub is the sole authority for account-set resolution. These unit-test
    // the three explicit-choice branches directly on the hub (previously only
    // covered end-to-end via ServerToggleTests through AppState), driving them
    // through the same injected profilesModel/accountStore seams.

    /// (a) An explicit EMPTY choice is honored — "watch nothing" / master toggle
    /// off — and must NOT be silently re-expanded to the household-global set.
    func testReloadHonorsExplicitEmptyChoice() throws {
        let (model, _, profiles) = try makeModel(accountIDs: [("a", "a.example.com"), ("b", "b.example.com")])
        // The profile explicitly chose to watch nothing.
        profiles.setActiveAccountIDs([], for: profiles.activeProfileID)

        model.reloadAccounts()

        XCTAssertTrue(model.activeAccountIDs.isEmpty)
    }

    /// (b) An explicit choice whose accounts have ALL gone stale falls back to the
    /// household-global active set (so a profile isn't left permanently blank by a
    /// removal it didn't make) — not to empty.
    func testReloadFallsBackToGlobalWhenAllChosenAreStale() throws {
        let (model, store, profiles) = try makeModel(accountIDs: [("a", "a.example.com"), ("b", "b.example.com")])
        // Household-global active set is just "b".
        store.setActiveAccountIDs(["b"])
        // The profile's explicit choice references only accounts that no longer exist.
        profiles.setActiveAccountIDs(["gone-1", "gone-2"], for: profiles.activeProfileID)

        model.reloadAccounts()

        // Falls back to the global set (filtered to known), NOT empty, NOT all.
        XCTAssertEqual(model.activeAccountIDs, ["b"])
    }

    /// (c) An explicit choice where only SOME chosen accounts survive honors
    /// exactly the survivors — it does not fall back to the global set.
    func testReloadHonorsSurvivingSubsetOfExplicitChoice() throws {
        let (model, store, profiles) = try makeModel(accountIDs: [("a", "a.example.com"), ("b", "b.example.com")])
        // Global set is everything, to prove we do NOT fall back to it here.
        store.setActiveAccountIDs(["a", "b"])
        // The profile chose "a" plus an account that no longer exists.
        profiles.setActiveAccountIDs(["a", "gone"], for: profiles.activeProfileID)

        model.reloadAccounts()

        // Exactly the surviving chosen account — not the global {a, b}.
        XCTAssertEqual(model.activeAccountIDs, ["a"])
    }

    func testLiveTVNeverFallsBackToAnExcludedAccount() throws {
        let (model, store, profiles) = try makeModel(accountIDs: [("a", "a.example.com"), ("b", "b.example.com")])
        model.registry.register(.jellyfin) { LiveTVAccountsTestProvider(session: $0.session) }
        model.tokenResolver = { _ in "fixture-effective-user-token" }
        store.setActiveAccountIDs(["a", "b"])
        profiles.setActiveAccountIDs(["a"], for: profiles.activeProfileID)
        model.reloadAccounts()
        let resolver = model.liveTVProviderResolver()
        XCTAssertEqual(model.liveTVServerChoices.map(\.id), ["a"])
        XCTAssertNotNil(resolver("a"))
        XCTAssertNil(resolver("b"))

        profiles.setActiveAccountIDs([], for: profiles.activeProfileID)
        model.reloadAccounts()
        XCTAssertNotNil(model.provider(forAccountID: "a"))
        XCTAssertTrue(model.liveTVServerChoices.isEmpty)
        XCTAssertNil(resolver("a"))
    }

    func testLiveTVUsesEffectiveCredentialsAndInvalidatesTheirIdentity() throws {
        let (model, store, profiles) = try makeModel(accountIDs: [("a", "a.example.com")])
        model.registry.register(.jellyfin) { LiveTVAccountsTestProvider(session: $0.session) }
        model.tokenResolver = { _ in "fixture-effective-user-token" }
        var revision = CredentialRevision()
        model.credentialRevision = { _ in revision }
        store.setActiveAccountIDs(["a"])
        profiles.setActiveAccountIDs(["a"], for: profiles.activeProfileID)
        model.reloadAccounts()
        let resolver = model.liveTVProviderResolver()
        let original = try XCTUnwrap(resolver("a"))
        let provider = try XCTUnwrap(original.provider as? LiveTVAccountsTestProvider)
        XCTAssertEqual(provider.session.accessToken, "fixture-effective-user-token")
        revision = CredentialRevision()
        let replacement = try XCTUnwrap(resolver("a"))
        XCTAssertNotEqual(original.authorizationID, replacement.authorizationID)
        XCTAssertFalse(replacement.authorizationID.contains("fixture-effective-user-token"))
    }

    func testLiveTVResolverIsBoundToTheProfileThatCreatedIt() throws {
        let (model, store, profiles) = try makeModel(accountIDs: [("a", "a.example.com")])
        model.registry.register(.jellyfin) { LiveTVAccountsTestProvider(session: $0.session) }
        model.tokenResolver = { _ in "fixture-effective-user-token" }
        store.setActiveAccountIDs(["a"])
        profiles.setActiveAccountIDs(["a"], for: profiles.activeProfileID)
        model.reloadAccounts()
        let resolver = model.liveTVProviderResolver()
        let original = try XCTUnwrap(resolver("a"))
        let other = profiles.add(name: "Other profile", activeAccountIDs: ["a"])
        profiles.select(other.id)
        model.reloadAccounts()
        XCTAssertNil(resolver("a"))
        let replacement = try XCTUnwrap(model.liveTVProviderResolver()("a"))
        XCTAssertNotEqual(original.authorizationID, replacement.authorizationID)
    }
}

private final class LiveTVAccountsTestProvider: MediaProvider, ServerLiveTVProviding, ServerAddressUpdating, Sendable {
    let kind: ProviderKind = .jellyfin
    let session: UserSession
    private let routes = Mutex<[URL]>([])
    var alternatives: [URL] { routes.withLock { $0 } }
    func updateServerAddresses(_ alternatives: [URL]) { routes.withLock { $0 = alternatives } }

    init(session: UserSession) { self.session = session }
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: 0, totalCount: 0)
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
    func liveTVAvailability() async throws -> ServerLiveTVAvailability {
        XCTFail("Listing authorized accounts must not contact a Live TV server")
        throw ServerLiveTVError.unsupportedAPI
    }
    func liveTVChannels() async throws -> [ServerLiveTVChannel] {
        XCTFail("Listing authorized accounts must not load channels")
        return []
    }
    func liveTVGuide(channelIDs: [String], from: Date, to: Date) async throws -> [ServerLiveTVProgramme] {
        XCTFail("Listing authorized accounts must not load a guide")
        return []
    }
    func openLiveTVChannel(id: String) async throws -> any LiveTVStreamLease {
        XCTFail("Listing authorized accounts must not open a tuner")
        throw ServerLiveTVError.unsupportedPlaybackMode
    }
}
