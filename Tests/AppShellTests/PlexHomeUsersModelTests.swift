import XCTest
import CoreModels
import CoreUI
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
        model.plexHomeUsersFetch = { _, _ in throw URLError(.notConnectedToInternet) }
        model.plexHomeUserSwitch = { _, _, _, _ in throw AppError.unauthorized }
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

    func testDisabledPlexBindingsDoNotRequestAuthorization() async throws {
        let (model, hub, profiles) = try makeModel(accountIDs: ["a", "b"])
        for id in ["a", "b"] {
            profiles.update(profiles.activeProfile.settingHomeUserBinding(
                .init(homeUserID: "parent", name: "Parent", requiresPIN: true), forPlexAccount: id
            ))
        }
        profiles.setActiveAccountIDs(["b"], for: profiles.activeProfileID)
        hub.reloadAccounts()
        model.plexHomeUsersFetch = { token, _ in
            XCTAssertEqual(token, "admin-b", "A disabled source must not contact Plex.")
            return [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)]
        }
        model.ensurePlexIdentityForActiveProfile()
        await model.waitForPlexPINRequirementCheck()
        XCTAssertEqual(model.pendingPlexPINRequest?.accountID, "b")
        XCTAssertEqual(model.plexPINEntryAvailability, .available)
        XCTAssertNil(model.resolvedToken(for: "a"))
        XCTAssertFalse(model.hasResolvedWatchMutationIdentity(forAccountID: "a"))
        XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "a")?.homeUserID, "parent")

        profiles.setActiveAccountIDs([], for: profiles.activeProfileID)
        hub.reloadAccounts()
        model.ensurePlexIdentityForActiveProfile()
        XCTAssertNil(model.pendingPlexPINRequest)
        XCTAssertNil(model.plexPINError)
    }

    func testDisablingAnAuthorizedSourceRevokesCredentialsAndRequiresPINOnReenable() async throws {
        let (model, hub, profiles) = try makeModel(accountIDs: ["a"])
        model.plexHomeUsersFetch = { _, _ in
            [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)]
        }
        model.plexHomeUserSwitch = { _, pin, _, _ in
            XCTAssertEqual(pin, "2468")
            return "parent-cloud"
        }
        model.plexServerTokenResolve = { _, _, _ in "parent-server" }
        activateSavedUser(model, profiles: profiles, accountID: "a",
                          user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true))
        model.submitPlexPIN("2468")
        await model.waitForPlexPINRequirementCheck()
        XCTAssertEqual(model.resolvedToken(for: "a"), "parent-server")
        let binding = profiles.activeProfile.homeUserBinding(forPlexAccount: "a")

        profiles.setActiveAccountIDs([], for: profiles.activeProfileID)
        hub.reloadAccounts()
        model.ensurePlexIdentityForActiveProfile()
        XCTAssertNil(model.pendingPlexPINRequest)
        XCTAssertNil(model.resolvedToken(for: "a"))
        XCTAssertNil(model.discoverToken(for: "a"))
        XCTAssertNil(model.plexDiscoverTokens.token(for: "a"))
        XCTAssertFalse(model.hasResolvedWatchMutationIdentity(forAccountID: "a"))
        XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "a"), binding)

        profiles.setActiveAccountIDs(["a"], for: profiles.activeProfileID)
        hub.reloadAccounts()
        model.ensurePlexIdentityForActiveProfile()
        await model.waitForPlexPINRequirementCheck()
        XCTAssertEqual(model.pendingPlexPINRequest?.accountID, "a")
        XCTAssertEqual(model.plexPINEntryAvailability, .available)
        XCTAssertNil(model.resolvedToken(for: "a"), "Old PIN proof must not survive disabling the source.")
        model.submitPlexPIN("2468")
        await model.waitForPlexPINRequirementCheck()
        XCTAssertEqual(model.resolvedToken(for: "a"), "parent-server")
    }

    func testDisabledOwnerSourceCannotResolveCredentialsWithoutABinding() throws {
        let (model, hub, profiles) = try makeModel(accountIDs: ["a"])
        profiles.setActiveAccountIDs([], for: profiles.activeProfileID)
        hub.reloadAccounts()
        model.ensurePlexIdentityForActiveProfile()
        XCTAssertNil(model.resolvedToken(for: "a"))
        XCTAssertFalse(model.hasResolvedWatchMutationIdentity(forAccountID: "a"))
    }

    func testDisablingDuringMetadataCheckCannotRestoreThePINPrompt() async throws {
        let (model, hub, profiles) = try makeModel(accountIDs: ["a"])
        model.plexHomeUsersFetch = { _, _ in
            await MainActor.run {
                profiles.setActiveAccountIDs([], for: profiles.activeProfileID)
                hub.reloadAccounts()
                model.ensurePlexIdentityForActiveProfile()
            }
            return [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)]
        }
        activateSavedUser(model, profiles: profiles, accountID: "a",
                          user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true))
        await model.waitForPlexPINRequirementCheck()
        XCTAssertNil(model.pendingPlexPINRequest)
        XCTAssertNil(model.plexPINError)
        XCTAssertNil(model.discoverToken(for: "a"))
    }

    func testDisableAndReenableDuringPINSubmissionRejectsTheOldResponse() async throws {
        let (model, hub, profiles) = try makeModel(accountIDs: ["a"])
        model.plexHomeUsersFetch = { _, _ in
            [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)]
        }
        model.plexHomeUserSwitch = { _, _, _, _ in "stale-cloud" }
        model.plexServerTokenResolve = { _, _, _ in
            await MainActor.run {
                profiles.setActiveAccountIDs([], for: profiles.activeProfileID)
                hub.reloadAccounts()
                model.ensurePlexIdentityForActiveProfile()
                profiles.setActiveAccountIDs(["a"], for: profiles.activeProfileID)
                hub.reloadAccounts()
                model.ensurePlexIdentityForActiveProfile()
            }
            return "stale-server"
        }
        activateSavedUser(model, profiles: profiles, accountID: "a",
                          user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true))
        model.submitPlexPIN("2468")
        await model.waitForPlexPINRequirementCheck()
        await model.waitForPlexPINRequirementCheck()
        XCTAssertEqual(model.pendingPlexPINRequest?.accountID, "a")
        XCTAssertEqual(model.plexPINEntryAvailability, .available)
        XCTAssertNil(model.resolvedToken(for: "a"))
        XCTAssertNil(model.discoverToken(for: "a"))
        XCTAssertFalse(model.isSubmittingPlexPIN)
    }

    // MARK: Generation-guard regression (stale background-refresh race)

    /// Drains queued main-actor work so a `Task { … }` spawned by the model runs to
    /// completion. Deterministic on the single-threaded main actor.
    private func drainMainActor(_ iterations: Int = 200) async {
        for _ in 0..<iterations { await Task.yield() }
    }

    private func activateSavedUser(
        _ model: PlexHomeUsersModel, profiles: ProfilesModel, accountID: String, user: PlexHomeUser?
    ) {
        profiles.update(profiles.activeProfile.settingHomeUserBinding(user.map {
            .init(
                homeUserID: $0.id, name: $0.name, requiresPIN: $0.requiresPIN,
                pinRequirementVerified: $0.pinRequirementVerified
            )
        }, forPlexAccount: accountID))
        model.ensurePlexIdentityForActiveProfile()
    }

    /// Authenticates an unprotected user so a later re-scope has a live identity.
    private func installUnprotectedOverride(
        _ model: PlexHomeUsersModel,
        accountID: String,
        userID: String,
        token: String
    ) async {
        model.plexHomeUsersFetch = { _, _ in
            [PlexHomeUser(id: userID, name: userID, requiresPIN: false)]
        }
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
        let (model, _, profiles) = try makeModel(accountIDs: ["a"])
        // 1) Establish a live override for "old" (generation now > 0, override present).
        await installUnprotectedOverride(model, accountID: "a", userID: "old", token: "tok-old")
        XCTAssertEqual(model.resolvedToken(for: "a"), "tok-old")

        // 2) Re-scope to a DIFFERENT unprotected user, and — mid-refresh, from inside
        //    the injected server-token resolve (which runs right before the guarded
        //    write) — simulate the active profile's binding being dropped. That bumps
        //    the identity generation, so the in-flight refresh's captured generation
        //    goes stale.
        model.plexHomeUsersFetch = { _, _ in
            [PlexHomeUser(id: "new", name: "new", requiresPIN: false)]
        }
        model.plexHomeUserSwitch = { uuid, _, _, _ in "acct-\(uuid)" }
        model.plexServerTokenResolve = { [weak model] _, _, _ in
            await MainActor.run { model?.setPlexHomeUserForActiveProfile(accountID: "a", user: nil) }
            return "tok-new-STALE"
        }
        activateSavedUser(model, profiles: profiles,
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
        let (model, _, profiles) = try makeModel(accountIDs: ["a"])
        model.plexHomeUsersFetch = { _, _ in
            [PlexHomeUser(id: "solo", name: "solo", requiresPIN: false)]
        }
        model.plexHomeUserSwitch = { uuid, _, _, _ in "acct-\(uuid)" }
        model.plexServerTokenResolve = { _, _, _ in "tok-happy" }
        activateSavedUser(model, profiles: profiles,
            accountID: "a",
            user: PlexHomeUser(id: "solo", name: "solo", requiresPIN: false)
        )
        await drainMainActor()

        // Generation was stable through the refresh → the confirming write proceeded.
        XCTAssertEqual(model.resolvedToken(for: "a"), "tok-happy")
    }

    func testPartialLegacyCacheDoesNotAuthorizeEntryBeforeFreshAuthentication() async throws {
        let cache = PlexHomeUserTokenCache(store: InMemorySecureStore())
        cache.store(token: "CACHED-CHILD-SERVER", account: "a", homeUser: "child")
        let (model, _, profiles) = try makeModel(accountIDs: ["a"], cache: cache)
        model.plexHomeUsersFetch = { _, _ in
            [PlexHomeUser(id: "child", name: "Child", requiresPIN: false)]
        }
        model.plexHomeUserSwitch = { user, _, _, _ in
            XCTAssertEqual(user, "child")
            return "FRESH-CHILD-CLOUD"
        }
        model.plexServerTokenResolve = { _, _, _ in nil }
        activateSavedUser(model, profiles: profiles,
            accountID: "a", user: PlexHomeUser(id: "child", name: "Child", requiresPIN: false)
        )
        let generation = model.plexIdentityGeneration
        XCTAssertNotNil(model.pendingPlexPINRequest)
        XCTAssertNil(model.resolvedToken(for: "a"))
        await drainMainActor()
        XCTAssertEqual(model.resolvedToken(for: "a"), "FRESH-CHILD-CLOUD")
        XCTAssertEqual(model.discoverToken(for: "a"), "FRESH-CHILD-CLOUD",
                       "A failed server-token lookup must not discard the successfully authenticated cloud credential.")
        XCTAssertNil(cache.token(account: "a", homeUser: "child"))
        XCTAssertNil(cache.discoverToken(account: "a", homeUser: "child"))
        XCTAssertGreaterThan(model.plexIdentityGeneration, generation, "Only the newly authorized identity is published.")
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
        XCTAssertNil(cache.discoverToken(account: "a", homeUser: "child"))
    }

    func testCloudRecoveryCannotSilentlyUnlockProtectedPlexUser() async throws {
        let cache = PlexHomeUserTokenCache(store: InMemorySecureStore())
        cache.store(token: "PROTECTED-SERVER", account: "a", homeUser: "parent")
        cache.storeDiscoverToken("PROTECTED-CLOUD", account: "a", homeUser: "parent")
        let (model, _, profiles) = try makeModel(accountIDs: ["a"], cache: cache)
        model.plexHomeUserSwitch = { _, pin, _, _ in
            XCTAssertNil(pin)
            throw AppError.unauthorized
        }
        activateSavedUser(model, profiles: profiles,
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

    func testCloudRecoveryCannotAuthorizeAnUnresolvedPreviouslyUnprotectedUser() async throws {
        for explicitActivation in [false, true] {
            let cache = PlexHomeUserTokenCache(store: InMemorySecureStore())
            let (model, _, profiles) = try makeModel(accountIDs: ["a"], cache: cache)
            profiles.update(profiles.activeProfile.settingHomeUserBinding(
                PlexHomeUserBinding(homeUserID: "child", name: "Child", requiresPIN: false),
                forPlexAccount: "a"
            ))
            cache.store(token: "OLD-SERVER", account: "a", homeUser: "child")
            cache.storeDiscoverToken("OLD-CLOUD", account: "a", homeUser: "child")
            model.plexHomeUserSwitch = { _, _, _, _ in
                XCTFail("Cloud recovery cannot authenticate before profile entry verifies current protection.")
                return "CLOUD-ONLY-CHILD"
            }
            if explicitActivation { model.beginExplicitProfileActivation() }
            do {
                _ = try await model.resolveDiscoverToken(for: "a")
                XCTFail("An unresolved identity must remain gated.")
            } catch let error as AppError {
                XCTAssertEqual(error, .unauthorized)
            }
            XCTAssertNil(model.resolvedToken(for: "a"))
            XCTAssertNil(model.discoverToken(for: "a"))
            model.ensurePlexIdentityForActiveProfile()
            await model.waitForPlexPINRequirementCheck()
            XCTAssertNotNil(model.pendingPlexPINRequest)
            XCTAssertNil(cache.token(account: "a", homeUser: "child"))
            XCTAssertNil(cache.discoverToken(account: "a", homeUser: "child"))
        }
    }

    func testCloudRecoveryDoesNotDismissAnotherAccountsPINPrompt() async throws {
        let (model, _, profiles) = try makeModel(accountIDs: ["a", "b"])
        await installUnprotectedOverride(model, accountID: "a", userID: "child", token: "CHILD-SERVER")
        activateSavedUser(model, profiles: profiles,
            accountID: "b", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        await model.waitForPlexPINRequirementCheck()
        model.plexDiscoverTokens.setToken(nil, for: "a")
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

    func testRemovedPlexPINClearsOnlyPlexRequirementAfterAuthenticatedSwitch() async throws {
        let cache = PlexHomeUserTokenCache(store: InMemorySecureStore())
        let (model, _, profiles) = try makeModel(accountIDs: ["a"], cache: cache)
        var profile = profiles.activeProfile
        profile.replaceLock(with: ProfileLock.make(pin: "2468", matchesPlexPIN: true, iterations: 1))
        profiles.update(profile)
        model.plexHomeUsersFetch = { _, _ in
            [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: false)]
        }
        model.plexHomeUserSwitch = { user, pin, admin, _ in
            XCTAssertEqual(user, "parent")
            if let pin {
                XCTAssertEqual(pin, "2468")
                throw AppError.unauthorized
            }
            XCTAssertNil(pin)
            XCTAssertEqual(admin, "admin-a")
            await MainActor.run {
                XCTAssertNotNil(model.pendingPlexPINRequest, "The gate stays up until authentication finishes.")
                XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "a")?.requiresPIN, true)
                var renamed = profiles.activeProfile
                renamed.name = "Renamed during authentication"
                profiles.update(renamed)
            }
            return "PARENT-CLOUD"
        }
        model.plexServerTokenResolve = { _, _, _ in "PARENT-SERVER" }
        activateSavedUser(model, profiles: profiles,
            accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        model.prefillPlexPIN("2468", forProfile: profile.id)
        model.ensurePlexIdentityForActiveProfile()
        await model.waitForPlexPINRequirementCheck()

        XCTAssertNil(model.pendingPlexPINRequest)
        XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "a")?.requiresPIN, false)
        XCTAssertEqual(profiles.activeProfile.plexHomeUserRequiresPIN, false)
        XCTAssertEqual(profiles.activeProfile.lock, profile.lock)
        XCTAssertEqual(profiles.activeProfile.lockRevision, profile.lockRevision)
        XCTAssertEqual(profiles.activeProfile.name, "Renamed during authentication")
        XCTAssertEqual(model.resolvedToken(for: "a"), "PARENT-SERVER")
        XCTAssertEqual(model.discoverToken(for: "a"), "PARENT-CLOUD")
        XCTAssertNil(cache.token(account: "a", homeUser: "parent"))
        model.plexHomeUserSwitch = { _, _, _, _ in "PARENT-CLOUD" }
        model.beginExplicitProfileActivation()
        model.ensurePlexIdentityForActiveProfile()
        XCTAssertNotNil(model.pendingPlexPINRequest, "Each activation must check for a newly added PIN.")
        XCTAssertEqual(model.plexPINEntryAvailability, .checking)
        XCTAssertFalse(model.isAutomaticallySignedIn(profiles.activeProfile))
        await drainMainActor()
        XCTAssertNil(model.pendingPlexPINRequest, "A still-unprotected user must authenticate without PIN entry.")
    }

    func testPlexPINRefreshFailsClosedWithoutPositiveAuthentication() async throws {
        enum Failure: CaseIterable, Equatable, Sendable { case unavailable, rejected, emptyToken }
        for failure in Failure.allCases {
            let (model, _, profiles) = try makeModel(accountIDs: ["a"])
            model.plexHomeUsersFetch = { _, _ in
                [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: false)]
            }
            model.plexHomeUserSwitch = { _, pin, _, _ in
                XCTAssertNil(pin)
                switch failure {
                case .unavailable: throw URLError(.notConnectedToInternet)
                case .rejected: throw AppError.unauthorized
                case .emptyToken: return ""
                }
            }
            activateSavedUser(model, profiles: profiles,
                accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
            )
            await model.waitForPlexPINRequirementCheck()
            XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "a")?.requiresPIN, true, "\(failure)")
            XCTAssertEqual(model.pendingPlexPINRequest?.homeUserID, "parent", "\(failure)")
            XCTAssertNil(model.discoverToken(for: "a"), "\(failure)")
            XCTAssertEqual(model.plexPINEntryAvailability, .unavailable)
            XCTAssertNotNil(model.plexPINError)
            XCTAssertNotEqual(model.plexPINError, ProfileLockCopy.incorrectPIN)
        }
    }

    private enum MetadataState: CaseIterable, Sendable {
        case unavailable, missingUser, unknownProtection, protected, unprotected

        func users() throws -> [PlexHomeUser] {
            switch self {
            case .unavailable: throw URLError(.notConnectedToInternet)
            case .missingUser: return []
            case .unknownProtection:
                return [PlexHomeUser(
                    id: "parent", name: "Parent", requiresPIN: false, pinRequirementVerified: false
                )]
            case .protected, .unprotected:
                return [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: self == .protected)]
            }
        }
    }

    func testExplicitPINAuthenticatesIndependentlyOfHomeUserMetadata() async throws {
        for metadata in MetadataState.allCases {
            let (model, _, profiles) = try makeModel(accountIDs: ["a"])
            model.plexHomeUsersFetch = { _, _ in
                XCTFail("An entered PIN must go directly to Plex authentication: \(metadata)")
                return try metadata.users()
            }
            model.plexHomeUserSwitch = { _, pin, _, _ in
                XCTAssertEqual(pin, "2468")
                return "PARENT-CLOUD"
            }
            model.plexServerTokenResolve = { _, _, _ in "PARENT-SERVER" }
            model.setPlexHomeUserForActiveProfile(
                accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
            )
            model.submitPlexPIN("2468")
            await model.waitForPlexPINRequirementCheck()
            XCTAssertNil(model.pendingPlexPINRequest, "\(metadata)")
            XCTAssertEqual(model.discoverToken(for: "a"), "PARENT-CLOUD", "\(metadata)")
            XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "a")?.requiresPIN, true)
        }
    }

    func testSuppliedPINNetworkFailureNeverLeavesUnconfirmedProtectionLoading() async throws {
        for confirmedProtection in [false, true] {
            let (model, _, profiles) = try makeModel(accountIDs: ["a"])
            model.plexHomeUsersFetch = { _, _ in
                [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)]
            }
            activateSavedUser(model, profiles: profiles,
                accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
            )
            if confirmedProtection {
                await model.waitForPlexPINRequirementCheck()
                XCTAssertEqual(model.plexPINEntryAvailability, .available)
            } else {
                XCTAssertEqual(model.plexPINEntryAvailability, .checking)
            }
            model.plexHomeUsersFetch = { _, _ in
                XCTFail("A network failure must not replace the supplied PIN with a metadata request.")
                return []
            }
            model.plexHomeUserSwitch = { _, pin, _, _ in
                XCTAssertEqual(pin, "2468")
                throw URLError(.notConnectedToInternet)
            }
            model.prefillPlexPIN("2468", forProfile: profiles.activeProfileID)
            model.ensurePlexIdentityForActiveProfile()
            await model.waitForPlexPINRequirementCheck()

            XCTAssertEqual(model.plexPINEntryAvailability, confirmedProtection ? .available : .unavailable)
            XCTAssertNotNil(model.pendingPlexPINRequest)
            XCTAssertNotNil(model.plexPINError)
            XCTAssertFalse(model.isSubmittingPlexPIN)
            XCTAssertNil(model.discoverToken(for: "a"))
        }
    }

    func testPINlessSuccessCannotOverrideMissingOrProtectedHomeUserMetadata() async throws {
        for metadata in MetadataState.allCases {
            let (model, _, profiles) = try makeModel(accountIDs: ["a"])
            model.plexHomeUsersFetch = { _, _ in
                return try metadata.users()
            }
            model.plexHomeUserSwitch = { _, pin, _, _ in
                XCTAssertEqual(metadata, .unprotected, "Only confirmed PIN removal permits a PIN-less switch.")
                XCTAssertNil(pin)
                return "PARENT-CLOUD"
            }
            model.plexServerTokenResolve = { _, _, _ in "PARENT-SERVER" }
            activateSavedUser(model, profiles: profiles,
                accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
            )
            XCTAssertEqual(model.plexPINEntryAvailability, .checking)
            await model.waitForPlexPINRequirementCheck()
            XCTAssertEqual(
                model.plexPINEntryAvailability,
                metadata == .protected ? .available : metadata == .unprotected ? .checking : .unavailable
            )
            if metadata == .unprotected {
                XCTAssertNil(model.pendingPlexPINRequest)
                XCTAssertEqual(model.discoverToken(for: "a"), "PARENT-CLOUD")
                XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "a")?.requiresPIN, false)
            } else {
                XCTAssertNotNil(model.pendingPlexPINRequest, "\(metadata)")
                XCTAssertNil(model.discoverToken(for: "a"), "\(metadata)")
                XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "a")?.requiresPIN, true)
            }
        }
    }

    func testRepeatedReconciliationDoesNotRepeatProtectionCheck() async throws {
        let (model, _, _) = try makeModel(accountIDs: ["a"])
        let checked = expectation(description: "One protection check")
        checked.assertForOverFulfill = true
        model.plexHomeUsersFetch = { _, _ in
            checked.fulfill()
            return [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)]
        }
        model.plexHomeUserSwitch = { _, _, _, _ in
            XCTFail("A protected user must not be probed without a PIN.")
            return "UNVERIFIED-CLOUD"
        }
        model.setPlexHomeUserForActiveProfile(
            accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        for _ in 0..<4 { model.ensurePlexIdentityForActiveProfile() }
        await model.waitForPlexPINRequirementCheck()
        model.ensurePlexIdentityForActiveProfile()
        await model.waitForPlexPINRequirementCheck()
        await fulfillment(of: [checked], timeout: 1)
        XCTAssertNotNil(model.pendingPlexPINRequest)
    }

    func testMetadataRetryCanResolveAnUnprotectedUserWithoutPINEntry() async throws {
        let (model, _, _) = try makeModel(accountIDs: ["a"])
        model.setPlexHomeUserForActiveProfile(
            accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        await model.waitForPlexPINRequirementCheck()
        XCTAssertEqual(model.plexPINEntryAvailability, .unavailable)
        model.plexHomeUsersFetch = { _, _ in
            [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: false)]
        }
        model.plexHomeUserSwitch = { _, pin, _, _ in
            XCTAssertNil(pin)
            await MainActor.run { XCTAssertEqual(model.plexPINEntryAvailability, .checking) }
            return "PARENT-CLOUD"
        }
        model.plexServerTokenResolve = { _, _, _ in "PARENT-SERVER" }
        model.retryPlexPINRequirement()
        XCTAssertEqual(model.plexPINEntryAvailability, .checking)
        await model.waitForPlexPINRequirementCheck()
        XCTAssertNil(model.pendingPlexPINRequest)
        XCTAssertEqual(model.plexPINEntryAvailability, .checking)
        XCTAssertEqual(model.discoverToken(for: "a"), "PARENT-CLOUD")
    }

    func testStalePINlessProbeCannotChangeNewerAuthorization() async throws {
        enum Mutation: CaseIterable, Equatable, Sendable {
            case cancel, activation, profile, binding, accountRemoval, accountCredential, lock, explicitPIN
        }
        for mutation in Mutation.allCases {
            let (model, hub, profiles) = try makeModel(accountIDs: ["a"])
            let originalID = profiles.activeProfileID
            model.plexHomeUsersFetch = { _, _ in
                [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: false)]
            }
            model.plexServerTokenResolve = { _, _, _ in "EXPLICIT-SERVER" }
            model.plexHomeUserSwitch = { _, pin, _, _ in
                XCTAssertNil(pin)
                try await MainActor.run {
                    switch mutation {
                    case .cancel: model.cancelPlexPIN()
                    case .activation: model.beginExplicitProfileActivation()
                    case .profile:
                        let other = profiles.add(name: "Other", avatarSymbol: "person", colorIndex: 1)
                        profiles.select(other.id)
                    case .binding:
                        profiles.update(profiles.activeProfile.settingHomeUserBinding(
                            .init(homeUserID: "other", name: "Other", requiresPIN: true), forPlexAccount: "a"
                        ))
                    case .accountRemoval:
                        model.forgetAccount("a")
                        try hub.accountStore.remove(id: "a")
                        hub.reloadAccounts()
                    case .accountCredential:
                        try hub.accountStore.add(hub.accounts[0], token: "ROTATED-CREDENTIAL")
                        hub.reloadAccounts()
                    case .lock:
                        var profile = profiles.activeProfile
                        profile.replaceLock(with: ProfileLock.make(pin: "1357", iterations: 1))
                        profiles.update(profile)
                    case .explicitPIN:
                        model.plexHomeUserSwitch = { _, pin, _, _ in
                            XCTAssertEqual(pin, "2468")
                            return "EXPLICIT-CLOUD"
                        }
                        model.submitPlexPIN("2468")
                    }
                }
                return "STALE-CLOUD"
            }
            activateSavedUser(model, profiles: profiles,
                accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
            )
            await model.waitForPlexPINRequirementCheck()
            await model.waitForPlexPINRequirementCheck()
            let original = try XCTUnwrap(profiles.profiles.first { $0.id == originalID })
            XCTAssertEqual(original.homeUserBinding(forPlexAccount: "a")?.requiresPIN, true, "\(mutation)")
            if mutation == .explicitPIN {
                XCTAssertEqual(model.discoverToken(for: "a"), "EXPLICIT-CLOUD")
            } else {
                XCTAssertNil(model.discoverToken(for: "a"), "\(mutation)")
            }
        }
    }

    func testUnrelatedServerRefreshCannotDismissProtectedAccountsPrompt() async throws {
        let (model, _, profiles) = try makeModel(accountIDs: ["a", "b"])
        await installUnprotectedOverride(model, accountID: "a", userID: "child", token: "CHILD-SERVER")
        profiles.update(profiles.activeProfile.settingHomeUserBinding(
            .init(homeUserID: "parent", name: "Parent", requiresPIN: true), forPlexAccount: "b"
        ))
        model.plexHomeUsersFetch = { _, _ in
            [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)]
        }
        model.plexHomeUserSwitch = { user, _, _, _ in
            guard user == "child" else { throw AppError.unauthorized }
            return "CHILD-CLOUD"
        }
        model.plexServerTokenResolve = { _, _, _ in "CHILD-SERVER" }
        model.ensurePlexIdentityForActiveProfile()
        await model.waitForPlexPINRequirementCheck()
        let request = model.pendingPlexPINRequest
        model.plexDiscoverTokens.setToken(nil, for: "a")
        model.ensurePlexIdentityForActiveProfile()
        await drainMainActor()
        XCTAssertEqual(model.discoverToken(for: "a"), "CHILD-CLOUD")
        XCTAssertEqual(model.pendingPlexPINRequest, request)
        XCTAssertEqual(model.pendingPlexPINRequest?.accountID, "b")
        XCTAssertNil(model.discoverToken(for: "b"))
    }

    func testRemovedPINAdvancesToNextProtectedAccount() async throws {
        let (model, _, profiles) = try makeModel(accountIDs: ["a", "b"])
        var profile = profiles.activeProfile
        for accountID in ["a", "b"] {
            profile = profile.settingHomeUserBinding(
                .init(homeUserID: "parent-\(accountID)", name: "Parent", requiresPIN: true), forPlexAccount: accountID
            )
        }
        profiles.update(profile)
        model.plexHomeUsersFetch = { _, _ in
            [
                PlexHomeUser(id: "parent-a", name: "Parent A", requiresPIN: false),
                PlexHomeUser(id: "parent-b", name: "Parent B", requiresPIN: true)
            ]
        }
        model.plexHomeUserSwitch = { user, pin, _, _ in
            XCTAssertNil(pin)
            guard user == "parent-a" else { throw AppError.unauthorized }
            return "PARENT-A-CLOUD"
        }
        model.plexServerTokenResolve = { _, _, _ in "PARENT-A-SERVER" }
        model.ensurePlexIdentityForActiveProfile()
        await model.waitForPlexPINRequirementCheck()
        await model.waitForPlexPINRequirementCheck()
        XCTAssertEqual(model.pendingPlexPINRequest?.accountID, "b")
        XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "a")?.requiresPIN, false)
        XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "b")?.requiresPIN, true)
        XCTAssertNil(model.discoverToken(for: "b"))
    }

    func testCancelledMetadataRefreshCannotAuthorizeRemovedPIN() async throws {
        let (model, _, profiles) = try makeModel(accountIDs: ["a"])
        model.plexHomeUsersFetch = { _, _ in
            await MainActor.run { model.cancelPlexPIN() }
            return [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: false)]
        }
        model.plexHomeUserSwitch = { _, _, _, _ in
            XCTFail("Cancelled metadata must not authorize a later switch.")
            return "STALE-CLOUD"
        }
        activateSavedUser(model, profiles: profiles,
            accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        await model.waitForPlexPINRequirementCheck()
        XCTAssertNotNil(model.pendingPlexPINRequest)
        XCTAssertNil(model.discoverToken(for: "a"))
        XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "a")?.requiresPIN, true)
    }

    func testSavedFalseRequirementCannotRestoreCachedProtectedCredentials() async throws {
        for (metadata, previouslyVerified) in MetadataState.allCases.flatMap({ state in
            [false, true].map { (state, $0) }
        }) {
            let cache = PlexHomeUserTokenCache(store: InMemorySecureStore())
            cache.store(token: "UNVERIFIED-SERVER", account: "a", homeUser: "parent")
            cache.storeDiscoverToken("UNVERIFIED-CLOUD", account: "a", homeUser: "parent")
            let (model, _, profiles) = try makeModel(accountIDs: ["a"], cache: cache)
            var legacy = try JSONDecoder().decode(PlexHomeUserBinding.self, from: Data(
                #"{"homeUserID":"parent","name":"Parent","requiresPIN":false}"#.utf8
            ))
            legacy.pinRequirementVerified = previouslyVerified ? true : nil
            profiles.update(profiles.activeProfile.settingHomeUserBinding(legacy, forPlexAccount: "a"))
            model.plexHomeUsersFetch = { _, _ in try metadata.users() }
            model.plexHomeUserSwitch = { _, pin, _, _ in
                XCTAssertEqual(metadata, .unprotected)
                XCTAssertNil(pin)
                return "CONFIRMED-CLOUD"
            }
            model.plexServerTokenResolve = { _, _, _ in "CONFIRMED-SERVER" }
            model.ensurePlexIdentityForActiveProfile()
            XCTAssertNotNil(model.pendingPlexPINRequest)
            XCTAssertNil(model.resolvedToken(for: "a"))
            XCTAssertNil(model.discoverToken(for: "a"))
            XCTAssertNil(cache.token(account: "a", homeUser: "parent"))
            await model.waitForPlexPINRequirementCheck()
            if metadata == .unprotected {
                XCTAssertNil(model.pendingPlexPINRequest)
                XCTAssertEqual(model.discoverToken(for: "a"), "CONFIRMED-CLOUD")
            } else {
                XCTAssertNotNil(model.pendingPlexPINRequest)
                XCTAssertNil(model.resolvedToken(for: "a"))
                XCTAssertNil(model.discoverToken(for: "a"))
            }
        }
    }

    func testRejectedPINCannotFallBackToOwnerAuthorizedSwitchForProtectedUser() async throws {
        let (model, _, profiles) = try makeModel(accountIDs: ["a"])
        model.plexHomeUsersFetch = { _, _ in
            [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)]
        }
        model.plexHomeUserSwitch = { _, pin, _, _ in
            if pin == "0000" { throw AppError.unauthorized }
            XCTFail("A rejected PIN must not trigger an owner-authorized PIN-less switch.")
            return "UNVERIFIED-CLOUD"
        }
        activateSavedUser(model, profiles: profiles,
            accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        model.submitPlexPIN("0000")
        await model.waitForPlexPINRequirementCheck()
        XCTAssertNotNil(model.pendingPlexPINRequest)
        XCTAssertNotNil(model.plexPINError)
        XCTAssertNil(model.discoverToken(for: "a"))
        XCTAssertEqual(profiles.activeProfile.homeUserBinding(forPlexAccount: "a")?.requiresPIN, true)
    }

    func testCancellingDefaultProfilePINRetainsTheUnresolvedGate() async throws {
        let (model, _, profiles) = try makeModel(accountIDs: ["a"])
        activateSavedUser(model, profiles: profiles,
            accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        let request = model.pendingPlexPINRequest
        model.cancelPlexPIN()
        await model.waitForPlexPINRequirementCheck()
        XCTAssertEqual(model.pendingPlexPINRequest, request)
        XCTAssertNil(model.discoverToken(for: "a"))
        XCTAssertFalse(model.hasResolvedWatchMutationIdentity(forAccountID: "a"))
    }

    func testCancelledSubmissionLeavesRetainedGateReadyForAnotherPIN() async throws {
        let (model, _, profiles) = try makeModel(accountIDs: ["a"])
        model.plexHomeUserSwitch = { _, pin, _, _ in
            XCTAssertEqual(pin, "2468")
            await MainActor.run {
                XCTAssertTrue(model.isSubmittingPlexPIN)
                model.cancelPlexPIN()
            }
            return "CANCELLED-CLOUD"
        }
        activateSavedUser(model, profiles: profiles,
            accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        model.submitPlexPIN("2468")
        await model.waitForPlexPINRequirementCheck()
        XCTAssertFalse(model.isSubmittingPlexPIN)
        XCTAssertNotNil(model.pendingPlexPINRequest)
        model.plexHomeUserSwitch = { _, pin, _, _ in
            XCTAssertEqual(pin, "1357")
            return "RETRIED-CLOUD"
        }
        model.plexServerTokenResolve = { _, _, _ in "RETRIED-SERVER" }
        model.submitPlexPIN("1357")
        XCTAssertTrue(model.isSubmittingPlexPIN)
        await model.waitForPlexPINRequirementCheck()
        XCTAssertFalse(model.isSubmittingPlexPIN)
        XCTAssertNil(model.pendingPlexPINRequest)
        XCTAssertEqual(model.discoverToken(for: "a"), "RETRIED-CLOUD")
    }

    func testCancelledLockedFallbackCannotReleaseTheOriginalPlexGate() throws {
        var flow: ProfileFlowModel?
        let (model, hub, profiles) = try makeModel(
            accountIDs: ["a"], switchProfile: { flow?.switchProfile(to: $0) }
        )
        var fallback = profiles.activeProfile
        fallback.replaceLock(with: ProfileLock.make(pin: "2468", iterations: 1))
        profiles.update(fallback)
        let selected = profiles.add(name: "Selected", avatarSymbol: "person", colorIndex: 1)
        profiles.select(selected.id)
        flow = ProfileFlowModel(
            profilesModel: profiles, accountsProviders: hub, plexHomeUsers: model,
            profileSettings: .init(namespace: profiles.activeNamespace),
            audioController: .init(),
            updateTrackersForActiveProfile: {}, discardWatchReconciler: { _ in }
        )
        activateSavedUser(model, profiles: profiles,
            accountID: "a", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        let request = model.pendingPlexPINRequest
        model.cancelPlexPIN()
        XCTAssertEqual(flow?.pendingLockedProfile?.id, fallback.id)
        flow?.cancelProfileLockPrompt()
        XCTAssertEqual(profiles.activeProfileID, selected.id)
        XCTAssertEqual(model.pendingPlexPINRequest, request)
        XCTAssertFalse(model.isSubmittingPlexPIN)
    }
}
