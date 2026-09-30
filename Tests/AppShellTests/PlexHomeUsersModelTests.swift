import XCTest
import CoreModels
import FeatureAuth
import FeatureProfiles
@testable import AppRuntime
@testable import AppShell

/// Unit tests for ``PlexHomeUsersModel`` — the Plex Home users / "who's watching"
/// facet split out of ``AppState``. Cover the facet's own deterministic behavior:
/// token resolution prefers a live override, the PIN-cancel fallback routes through
/// the injected `switchProfile`, and account-lifecycle hooks clear per-account
/// state. The full switch/prompt flow (with a stubbed PlexAuthClient) stays covered
/// by ServerToggleTests through AppState.
@MainActor
final class PlexHomeUsersModelTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "PlexHomeUsersModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func plexAccount(id: String) -> Account {
        Account(
            id: id,
            server: MediaServer(
                id: "srv-\(id)",
                name: "Plex \(id)",
                baseURL: URL(string: "https://\(id).plex.tv")!,
                provider: .plex
            ),
            userID: "user-\(id)",
            userName: "User \(id)",
            deviceID: "device"
        )
    }

    private func makeModel(
        accountIDs: [String] = [],
        cache: PlexHomeUserTokenCache = PlexHomeUserTokenCache(store: InMemorySecureStore()),
        switchProfile: @escaping @MainActor (String) -> Void = { _ in }
    ) throws -> (PlexHomeUsersModel, AccountsProvidersModel, ProfilesModel) {
        let store = AccountStore(secureStore: InMemorySecureStore())
        for id in accountIDs {
            try store.add(plexAccount(id: id), token: "admin-\(id)")
        }
        let profiles = ProfilesModel(store: ProfileStore(defaults: makeDefaults()))
        let hub = AccountsProvidersModel(
            accountStore: store,
            registry: ProviderRegistry(),
            profilesModel: profiles
        )
        hub.reloadAccounts()
        let model = PlexHomeUsersModel(
            accountsProviders: hub,
            profilesModel: profiles,
            plexHomeUserTokenCache: cache,
            automaticSignInStore: AutomaticSignInStore(defaults: makeDefaults(), secureStore: InMemorySecureStore()),
            switchProfile: switchProfile
        )
        return (model, hub, profiles)
    }

    func testResolvedTokenFallsBackToAdminTokenWithoutOverride() throws {
        let (model, _, _) = try makeModel(accountIDs: ["a"])
        // No override yet → the stored admin token is used.
        XCTAssertEqual(model.resolvedToken(for: "a"), "admin-a")
        // Unknown account → nil.
        XCTAssertNil(model.resolvedToken(for: "missing"))
    }

    func testCancelPINWithoutAlternateProfileClearsInsteadOfSwitching() throws {
        var switched: [String] = []
        let (model, _, _) = try makeModel(accountIDs: ["a"], switchProfile: { switched.append($0) })
        // With only the default profile, cancel can't switch away — it clears
        // overrides instead and never calls switchProfile.
        model.cancelPlexPIN()
        XCTAssertTrue(switched.isEmpty)
        XCTAssertNil(model.pendingPlexPINRequest)
        XCTAssertNil(model.plexPINError)
    }

    func testPresentAndClearUserSelection() throws {
        let (model, _, _) = try makeModel(accountIDs: ["a"])
        XCTAssertNil(model.pendingPlexUserSelection)
        model.presentUserSelection(
            .init(accountID: "a", serverName: "Plex a", users: [], isFirstRun: true)
        )
        XCTAssertEqual(model.pendingPlexUserSelection?.accountID, "a")
        model.clearUserSelection()
        XCTAssertNil(model.pendingPlexUserSelection)
    }

    func testResetAllForDebugClearsPendingState() throws {
        let (model, _, _) = try makeModel(accountIDs: ["a"])
        model.presentUserSelection(
            .init(accountID: "a", serverName: "Plex a", users: [], isFirstRun: false)
        )
        model.resetAllForDebug()
        XCTAssertNil(model.pendingPlexUserSelection)
        XCTAssertNil(model.pendingPlexPINRequest)
        XCTAssertNil(model.plexPINError)
    }

    func testForgetAccountIsSafeForUnknownID() throws {
        let (model, _, _) = try makeModel(accountIDs: ["a"])
        // Should not crash and should leave token resolution intact for others.
        model.forgetAccount("missing")
        XCTAssertEqual(model.resolvedToken(for: "a"), "admin-a")
    }

    // MARK: Generation-guard regression (stale background-refresh race)

    /// Drains queued main-actor work so a `Task { … }` spawned by the model runs to
    /// completion. Deterministic on the single-threaded main actor.
    private func drainMainActor(_ iterations: Int = 200) async {
        for _ in 0..<iterations { await Task.yield() }
    }

    /// Binds the active profile to an unprotected Home user on `accountID` and lets
    /// the confirming background refresh install + cache its token, so a later
    /// re-scope has an override to move the identity generation off.
    private func installUnprotectedOverride(
        _ model: PlexHomeUsersModel,
        accountID: String,
        userID: String,
        token: String
    ) async {
        model.plexHomeUserSwitch = { uuid, _, _, _ in "acct-\(uuid)" }
        model.plexServerTokenResolve = { _, _, _ in token }
        model.setPlexHomeUserForActiveProfile(
            accountID: accountID,
            user: PlexHomeUser(id: userID, name: userID, requiresPIN: false)
        )
        await drainMainActor()
    }

    /// A background token refresh whose profile was switched out from under it (the
    /// identity generation moved during its network window) must NOT re-install the
    /// old Home-user's token — the staleness guard drops the confirming write.
    func testStaleBackgroundRefreshDoesNotOverwriteNewerIdentity() async throws {
        let (model, _, _) = try makeModel(accountIDs: ["a"])
        // 1) Establish a live override for "old" (generation now > 0, override present).
        await installUnprotectedOverride(model, accountID: "a", userID: "old", token: "tok-old")
        XCTAssertEqual(model.resolvedToken(for: "a"), "tok-old")

        // 2) Re-scope to a DIFFERENT unprotected user, and — mid-refresh, from inside
        //    the injected server-token resolve (which runs right before the guarded
        //    write) — simulate the active profile's binding being dropped. That bumps
        //    the identity generation, so the in-flight refresh's captured generation
        //    goes stale.
        model.plexHomeUserSwitch = { uuid, _, _, _ in "acct-\(uuid)" }
        model.plexServerTokenResolve = { [weak model] _, _, _ in
            await MainActor.run { model?.setPlexHomeUserForActiveProfile(accountID: "a", user: nil) }
            return "tok-new-STALE"
        }
        model.setPlexHomeUserForActiveProfile(
            accountID: "a",
            user: PlexHomeUser(id: "new", name: "new", requiresPIN: false)
        )
        await drainMainActor()

        // The stale refresh dropped its write: the override is gone (fell back to the
        // admin token), and the stale "tok-new-STALE" was never installed.
        XCTAssertEqual(model.resolvedToken(for: "a"), "admin-a")
        XCTAssertNotEqual(model.resolvedToken(for: "a"), "tok-new-STALE")
    }

    /// The guard must NOT false-abort the common case: with no interleaving profile
    /// switch, the background refresh installs/confirms its token normally.
    func testHappyPathRefreshInstallsTokenWhenGenerationStable() async throws {
        let (model, _, _) = try makeModel(accountIDs: ["a"])
        model.plexHomeUserSwitch = { uuid, _, _, _ in "acct-\(uuid)" }
        model.plexServerTokenResolve = { _, _, _ in "tok-happy" }
        model.setPlexHomeUserForActiveProfile(
            accountID: "a",
            user: PlexHomeUser(id: "solo", name: "solo", requiresPIN: false)
        )
        await drainMainActor()

        // Generation was stable through the refresh → the confirming write proceeded.
        XCTAssertEqual(model.resolvedToken(for: "a"), "tok-happy")
    }

    func testPartialWarmCacheRecoversCloudTokenWhenServerResolutionFails() async throws {
        let cache = PlexHomeUserTokenCache(store: InMemorySecureStore())
        cache.store(token: "CACHED-CHILD-SERVER", account: "a", homeUser: "child")
        let (model, _, _) = try makeModel(accountIDs: ["a"], cache: cache)
        model.plexHomeUserSwitch = { user, _, _, _ in
            XCTAssertEqual(user, "child")
            return "FRESH-CHILD-CLOUD"
        }
        model.plexServerTokenResolve = { _, _, _ in nil }
        model.setPlexHomeUserForActiveProfile(
            accountID: "a", user: PlexHomeUser(id: "child", name: "Child", requiresPIN: false)
        )
        let generation = model.plexIdentityGeneration
        await drainMainActor()
        XCTAssertEqual(model.resolvedToken(for: "a"), "CACHED-CHILD-SERVER")
        XCTAssertEqual(model.discoverToken(for: "a"), "FRESH-CHILD-CLOUD",
                       "A failed server-token lookup must not discard the successfully authenticated cloud credential.")
        XCTAssertEqual(cache.discoverToken(account: "a", homeUser: "child"), "FRESH-CHILD-CLOUD")
        XCTAssertEqual(model.plexIdentityGeneration, generation, "Repairing cloud access must not rebuild the browsing tree.")
    }

    func testAlreadyResolvedUnprotectedUserRepairsMissingCloudHalf() async throws {
        let (model, _, _) = try makeModel(accountIDs: ["a"])
        await installUnprotectedOverride(model, accountID: "a", userID: "child", token: "CHILD-SERVER")
        model.plexDiscoverTokens.setToken(nil, for: "a")
        model.plexHomeUserSwitch = { _, _, _, _ in "REFRESHED-CHILD-CLOUD" }
        model.plexServerTokenResolve = { _, _, _ in nil }
        model.ensurePlexIdentityForActiveProfile()
        await drainMainActor()
        XCTAssertEqual(model.resolvedToken(for: "a"), "CHILD-SERVER")
        XCTAssertEqual(model.discoverToken(for: "a"), "REFRESHED-CHILD-CLOUD")
    }

    func testAwaitedCloudRecoveryPreservesServerIdentityAndPlozzLock() async throws {
        let cache = PlexHomeUserTokenCache(store: InMemorySecureStore())
        let (model, hub, profiles) = try makeModel(accountIDs: ["a"], cache: cache)
        await installUnprotectedOverride(model, accountID: "a", userID: "child", token: "CHILD-SERVER")
        var profile = profiles.activeProfile
        profile.replaceLock(with: ProfileLock.make(pin: "1357", iterations: 1))
        profiles.update(profile)
        model.plexDiscoverTokens.setToken(nil, for: "a")
        model.plexHomeUserSwitch = { user, pin, credential, _ in
            XCTAssertEqual(user, "child")
            XCTAssertNil(pin, "A Plozz profile PIN must not be sent to Plex.")
            XCTAssertEqual(credential, "admin-a", "The stored credential authorizes only the scoped switch.")
            return "RECOVERED-CHILD-CLOUD"
        }
        model.plexServerTokenResolve = { _, _, _ in
            XCTFail("Cloud-only recovery must not rotate a working library credential.")
            return "ROTATED-SERVER-CREDENTIAL"
        }
        let generation = model.plexIdentityGeneration
        let revision = model.effectiveCredentialRevision(for: hub.accounts[0])
        let token = try await model.resolveDiscoverToken(for: "a")
        XCTAssertEqual(token, "RECOVERED-CHILD-CLOUD")
        XCTAssertEqual(model.resolvedToken(for: "a"), "CHILD-SERVER")
        XCTAssertEqual(model.plexIdentityGeneration, generation)
        XCTAssertEqual(model.effectiveCredentialRevision(for: hub.accounts[0]), revision)
        XCTAssertEqual(profiles.activeProfile.lock, profile.lock)
        XCTAssertNil(model.pendingPlexPINRequest)
        XCTAssertEqual(cache.discoverToken(account: "a", homeUser: "child"), token)
    }

    func testCloudRecoveryCannotSilentlyUnlockProtectedPlexUser() async throws {
        let cache = PlexHomeUserTokenCache(store: InMemorySecureStore())
        cache.store(token: "PROTECTED-SERVER", account: "a", homeUser: "parent")
        cache.storeDiscoverToken("PROTECTED-CLOUD", account: "a", homeUser: "parent")
        let (model, _, _) = try makeModel(accountIDs: ["a"], cache: cache)
        model.plexHomeUserSwitch = { _, _, _, _ in
            XCTFail("Cloud recovery must not switch a protected user without their PIN.")
            return "UNAUTHORIZED-CLOUD"
        }
        model.setPlexHomeUserForActiveProfile(
            accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        do {
            _ = try await model.resolveDiscoverToken(for: "a")
            XCTFail("Expected normal Plex PIN authorization.")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
        }
        XCTAssertEqual(model.pendingPlexPINRequest?.homeUserID, "parent")
        XCTAssertNil(model.discoverToken(for: "a"))
        XCTAssertNil(cache.discoverToken(account: "a", homeUser: "parent"))
    }

    func testCloudOnlyIdentityIsClearedWhenLeavingItsScope() async throws {
        enum Departure: CaseIterable {
            case owner, otherUser, protectedUser, activation, forgetAccount
        }
        for departure in Departure.allCases {
            let cache = PlexHomeUserTokenCache(store: InMemorySecureStore())
            let (model, _, profiles) = try makeModel(accountIDs: ["a"], cache: cache)
            profiles.update(profiles.activeProfile.settingHomeUserBinding(
                PlexHomeUserBinding(homeUserID: "child", name: "Child", requiresPIN: false),
                forPlexAccount: "a"
            ))
            model.plexHomeUserSwitch = { _, _, _, _ in "CLOUD-ONLY-CHILD" }
            model.plexServerTokenResolve = { _, _, _ in
                XCTFail("Cloud recovery must not change the server credential.")
                return nil
            }
            _ = try await model.resolveDiscoverToken(for: "a")
            XCTAssertEqual(model.resolvedToken(for: "a"), "admin-a")
            XCTAssertEqual(model.discoverToken(for: "a"), "CLOUD-ONLY-CHILD")
            model.plexHomeUserSwitch = { _, _, _, _ in throw AppError.unauthorized }
            switch departure {
            case .owner:
                model.setPlexHomeUserForActiveProfile(accountID: "a", user: nil)
            case .otherUser, .protectedUser:
                model.setPlexHomeUserForActiveProfile(
                    accountID: "a",
                    user: PlexHomeUser(id: "other", name: "Other", requiresPIN: departure == .protectedUser)
                )
            case .activation:
                model.beginExplicitProfileActivation()
            case .forgetAccount:
                model.forgetAccount("a")
                XCTAssertNil(cache.discoverToken(account: "a", homeUser: "child"))
            }
            await drainMainActor()
            XCTAssertNil(model.discoverToken(for: "a"), "\(departure) must clear cloud-only identity too.")
        }
    }

    func testCloudRecoveryDoesNotDismissAnotherAccountsPINPrompt() async throws {
        let (model, _, profiles) = try makeModel(accountIDs: ["a", "b"])
        model.setPlexHomeUserForActiveProfile(
            accountID: "b", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        profiles.update(profiles.activeProfile.settingHomeUserBinding(
            PlexHomeUserBinding(homeUserID: "child", name: "Child", requiresPIN: false),
            forPlexAccount: "a"
        ))
        model.plexHomeUserSwitch = { user, pin, _, _ in
            XCTAssertEqual(user, "child")
            XCTAssertNil(pin)
            return "CHILD-CLOUD"
        }
        _ = try await model.resolveDiscoverToken(for: "a")
        XCTAssertEqual(model.pendingPlexPINRequest?.accountID, "b")
        XCTAssertEqual(model.pendingPlexPINRequest?.homeUserID, "parent")
    }

    func testCloudRecoveryRejectsSupersededAuthorizationBeforePublishing() async throws {
        enum Mutation: CaseIterable {
            case profile, binding, plexProtection, lock, accountRemoval, accountCredential, activation
        }
        for mutation in Mutation.allCases {
            let cache = PlexHomeUserTokenCache(store: InMemorySecureStore())
            let (model, hub, profiles) = try makeModel(accountIDs: ["a"], cache: cache)
            await installUnprotectedOverride(model, accountID: "a", userID: "child", token: "CHILD-SERVER")
            model.plexDiscoverTokens.setToken(nil, for: "a")
            model.plexHomeUserSwitch = { _, _, _, _ in
                try await MainActor.run {
                    switch mutation {
                    case .profile:
                        let other = profiles.add(name: "Other", avatarSymbol: "person", colorIndex: 1)
                        profiles.select(other.id)
                    case .binding:
                        profiles.update(profiles.activeProfile.settingHomeUserBinding(
                            PlexHomeUserBinding(homeUserID: "other", name: "Other", requiresPIN: false),
                            forPlexAccount: "a"
                        ))
                    case .plexProtection:
                        profiles.update(profiles.activeProfile.settingHomeUserBinding(
                            PlexHomeUserBinding(homeUserID: "child", name: "Child", requiresPIN: true),
                            forPlexAccount: "a"
                        ))
                    case .lock:
                        var profile = profiles.activeProfile
                        profile.replaceLock(with: ProfileLock.make(pin: "2468", iterations: 1))
                        profiles.update(profile)
                    case .accountRemoval:
                        model.forgetAccount("a")
                        try hub.accountStore.remove(id: "a")
                        hub.reloadAccounts()
                    case .accountCredential:
                        try hub.accountStore.add(hub.accounts[0], token: "NEW-ACCOUNT-CREDENTIAL")
                        hub.reloadAccounts()
                    case .activation:
                        model.beginExplicitProfileActivation()
                    }
                }
                return "STALE-CHILD-CLOUD"
            }
            model.plexServerTokenResolve = { _, _, _ in nil }
            do {
                _ = try await model.resolveDiscoverToken(for: "a")
                XCTFail("A superseded \(mutation) must cancel recovery.")
            } catch is CancellationError {}
            XCTAssertNil(model.discoverToken(for: "a"), "\(mutation)")
            XCTAssertNotEqual(cache.discoverToken(account: "a", homeUser: "child"), "STALE-CHILD-CLOUD", "\(mutation)")
        }
    }

    /// A failing Home-users fetch is logged (see PlozzLog.auth) but still honours the
    /// `[]` contract — an empty picker instead of a crash.
    func testPlexHomeUsersReturnsEmptyOnFetchFailure() async throws {
        struct FetchError: Error {}
        let (model, _, _) = try makeModel(accountIDs: ["a"])
        model.plexHomeUsersFetch = { _, _ in throw FetchError() }
        let users = await model.plexHomeUsers(forAccountID: "a")
        XCTAssertTrue(users.isEmpty)
    }
}
