import XCTest
import CoreModels
import FeatureAuth
import FeatureMusic
import FeatureSettings
@testable import AppRuntime
@testable import AppShell

@MainActor
final class AutomaticSignInTests: XCTestCase {
    private struct Household {
        let profiles: ProfileStore
        let accounts: AccountStore
        let startup: AutomaticSignInStore
        let defaults: UserDefaults
        let secrets: InMemorySecureStore
    }

    private struct Launch {
        let profiles: ProfilesModel
        let hub: AccountsProvidersModel
        let plex: PlexHomeUsersModel
        let flow: ProfileFlowModel
        let switchCache: PlexHomeUserTokenCache
    }

    private func household(provider: ProviderKind = .plex) throws -> Household {
        let name = "AutomaticSignInTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let accounts = AccountStore(secureStore: InMemorySecureStore())
        try accounts.add(Account(
            id: "account",
            server: MediaServer(
                id: "server", name: "Server",
                baseURL: URL(string: "https://server.example")!, provider: provider
            ),
            userID: "owner", userName: "Owner", deviceID: "device"
        ), token: "owner-token")
        let secrets = InMemorySecureStore()
        return Household(
            profiles: ProfileStore(defaults: defaults),
            accounts: accounts,
            startup: AutomaticSignInStore(defaults: defaults, secureStore: secrets),
            defaults: defaults, secrets: secrets
        )
    }

    private func launch(_ household: Household, startup: AutomaticSignInStore? = nil) -> Launch {
        let profiles = ProfilesModel(store: household.profiles)
        let hub = AccountsProvidersModel(
            accountStore: household.accounts,
            registry: ProviderRegistry(), profilesModel: profiles
        )
        hub.reloadAccounts()
        let cache = PlexHomeUserTokenCache(store: InMemorySecureStore())
        let plex = PlexHomeUsersModel(
            accountsProviders: hub, profilesModel: profiles,
            plexHomeUserTokenCache: cache,
            automaticSignInStore: startup ?? household.startup,
            switchProfile: { _ in }
        )
        plex.plexHomeUserSwitch = { user, pin, _, _ in
            guard pin == "2468" else { throw AppError.unauthorized }
            return "discover-\(user)"
        }
        plex.plexServerTokenResolve = { _, token, _ in "server-\(token)" }
        let flow = ProfileFlowModel(
            profilesModel: profiles, accountsProviders: hub, plexHomeUsers: plex,
            profileSettings: ProfileSettingsModel(namespace: profiles.activeNamespace),
            audioController: AudioPlaybackController(),
            updateTrackersForActiveProfile: {}, discardWatchReconciler: { _ in }
        )
        return Launch(profiles: profiles, hub: hub, plex: plex, flow: flow, switchCache: cache)
    }

    private func drain() async {
        for _ in 0..<200 { await Task.yield() }
    }

    private func authenticatePlex(_ env: Launch, user: String = "parent") async {
        env.plex.setPlexHomeUserForActiveProfile(
            accountID: "account",
            user: PlexHomeUser(id: user, name: user, requiresPIN: true)
        )
        XCTAssertNotNil(env.plex.pendingPlexPINRequest)
        env.plex.submitPlexPIN("2468")
        await drain()
        XCTAssertNil(env.plex.pendingPlexPINRequest)
        XCTAssertEqual(env.plex.resolvedToken(for: "account"), "server-discover-\(user)")
    }

    func testDisabledByDefaultAndExistingLaunchPickerIsUnchanged() throws {
        let house = try household()
        let env = launch(house)
        _ = env.profiles.add(name: "Second", avatarSymbol: "person", colorIndex: 1)
        env.flow.prepareLaunchPicker()
        XCTAssertFalse(env.plex.automaticallySignIn)
        XCTAssertTrue(env.flow.isChoosingProfile)
        XCTAssertNil(try house.startup.load())
    }

    func testProtectedPlexStartupRestoresBothTokensWithoutChangingPIN() async throws {
        let house = try household()
        let first = launch(house)
        await authenticatePlex(first)
        first.flow.setAutomaticallySignIn(true)
        XCTAssertTrue(first.plex.automaticallySignIn)
        XCTAssertNil(first.switchCache.token(account: "account", homeUser: "parent"))
        XCTAssertNil(first.switchCache.discoverToken(account: "account", homeUser: "parent"))

        let next = launch(house)
        next.flow.prepareLaunchPicker()
        next.plex.ensurePlexIdentityForActiveProfile()
        XCTAssertFalse(next.flow.isChoosingProfile)
        XCTAssertNil(next.plex.pendingPlexPINRequest)
        XCTAssertEqual(next.plex.resolvedToken(for: "account"), "server-discover-parent")
        XCTAssertEqual(next.plex.discoverToken(for: "account"), "discover-parent")
        XCTAssertEqual(next.profiles.activeProfile.homeUserBinding(forPlexAccount: "account")?.requiresPIN, true)
        XCTAssertFalse(next.plex.restoreAutomaticSignInAtLaunch(), "The launch exemption is one-shot")
    }

    func testManualSwitchBackToSamePlexUserStillPrompts() async throws {
        let house = try household()
        let first = launch(house)
        let parent = first.profiles.activeProfileID
        await authenticatePlex(first)
        first.flow.setAutomaticallySignIn(true)
        let next = launch(house)
        next.flow.prepareLaunchPicker()
        let other = next.profiles.add(
            name: "Other", avatarSymbol: "person", colorIndex: 1,
            plexHomeUserID: "parent", plexHomeUserName: "Parent",
            plexHomeUserAccountID: "account", plexHomeUserRequiresPIN: true
        )
        next.flow.switchProfile(to: other.id)
        XCTAssertNotNil(next.plex.pendingPlexPINRequest)
        XCTAssertNil(next.plex.discoverToken(for: "account"))
        XCTAssertNil(try house.startup.load(), "A pending switch must revoke the old startup session")
        next.flow.switchProfile(to: parent)
        XCTAssertNotNil(next.plex.pendingPlexPINRequest)
        XCTAssertFalse(next.plex.restoreAutomaticSignInAtLaunch())
        next.plex.submitPlexPIN("0000")
        await drain()
        XCTAssertNotNil(next.plex.plexPINError)
        XCTAssertNotNil(next.plex.pendingPlexPINRequest)
        XCTAssertNil(try house.startup.load())
        next.plex.submitPlexPIN("2468")
        await drain()
        XCTAssertNil(next.plex.pendingPlexPINRequest)
    }

    func testJellyfinAndLocalProfileLockUseStartupOnlyUnlockCredit() throws {
        let house = try household(provider: .jellyfin)
        let first = launch(house)
        var parent = first.profiles.activeProfile
        parent.replaceLock(with: ProfileLock.make(pin: "1357", iterations: 1))
        first.profiles.update(parent)
        first.flow.switchProfile(to: parent.id)
        XCTAssertTrue(first.flow.submitProfileLockPIN("1357"))
        first.flow.setAutomaticallySignIn(true)

        let next = launch(house)
        next.flow.prepareLaunchPicker()
        XCTAssertFalse(next.flow.isChoosingProfile)
        XCTAssertFalse(next.flow.activeProfileAwaitsUnlock)
        XCTAssertFalse(next.flow.isUnlockedThisRun(parent.id), "Startup must not grant manual PIN credit")
        XCTAssertFalse(next.flow.enforceLockOnActiveProfile())
        XCTAssertEqual(next.profiles.activeProfile.lock, parent.lock)
        let other = next.profiles.add(name: "Other", avatarSymbol: "person", colorIndex: 1)
        next.flow.switchProfile(to: other.id)
        next.flow.switchProfile(to: parent.id)
        XCTAssertEqual(next.flow.pendingLockedProfile?.id, parent.id)
        next.flow.cancelProfileLockPrompt()
        XCTAssertEqual(next.profiles.activeProfileID, other.id)
    }

    func testLastSuccessfullySelectedProfileIsRemembered() throws {
        let house = try household(provider: .jellyfin)
        let first = launch(house)
        first.flow.setAutomaticallySignIn(true)
        let other = first.profiles.add(name: "Other", avatarSymbol: "person", colorIndex: 1)
        first.flow.switchProfile(to: other.id)
        let next = launch(house)
        next.flow.prepareLaunchPicker()
        XCTAssertEqual(next.profiles.activeProfileID, other.id)
        XCTAssertFalse(next.flow.isChoosingProfile)
    }

    func testDisableDeletesTrustAndRestoresLaunchPrompt() async throws {
        let house = try household()
        let env = launch(house)
        await authenticatePlex(env)
        env.flow.setAutomaticallySignIn(true)
        env.flow.setAutomaticallySignIn(false)
        XCTAssertNil(house.secrets.string(for: "startupSession"))
        let next = launch(house)
        next.flow.prepareLaunchPicker()
        next.plex.ensurePlexIdentityForActiveProfile()
        XCTAssertFalse(next.plex.automaticallySignIn)
        XCTAssertNotNil(next.plex.pendingPlexPINRequest)
    }

    func testCannotEnableFromUnprovedOrPendingProfile() throws {
        let house = try household()
        let env = launch(house)
        env.plex.setPlexHomeUserForActiveProfile(
            accountID: "account",
            user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        env.flow.setAutomaticallySignIn(true)
        XCTAssertFalse(env.plex.automaticallySignIn)
        XCTAssertNotNil(env.plex.automaticSignInError)
        XCTAssertNil(try house.startup.load())
        var profile = env.profiles.activeProfile
        profile.replaceLock(with: ProfileLock.make(pin: "1357", iterations: 1))
        env.profiles.update(profile)
        env.plex.setAutomaticallySignIn(true, profileIsUnlocked: false)
        XCTAssertFalse(env.plex.automaticallySignIn)
    }

    func testChangedPlexBindingRejectsSavedIdentity() async throws {
        let house = try household()
        let env = launch(house)
        await authenticatePlex(env)
        env.flow.setAutomaticallySignIn(true)
        env.profiles.update(env.profiles.activeProfile.settingHomeUserBinding(
            .init(homeUserID: "another", name: "Another", requiresPIN: true),
            forPlexAccount: "account"
        ))
        let next = launch(house)
        XCTAssertFalse(next.plex.restoreAutomaticSignInAtLaunch())
        XCTAssertNil(next.plex.discoverToken(for: "account"))
        next.plex.ensurePlexIdentityForActiveProfile()
        XCTAssertEqual(next.plex.pendingPlexPINRequest?.homeUserID, "another")
    }

    func testChangedAccountCredentialRejectsSavedIdentity() async throws {
        let house = try household()
        let env = launch(house)
        await authenticatePlex(env)
        env.flow.setAutomaticallySignIn(true)
        var account = try XCTUnwrap(env.hub.accounts.first)
        account.credentialRevision = CredentialRevision()
        try house.accounts.add(account, token: "new-owner-token")
        let next = launch(house)
        XCTAssertFalse(next.plex.restoreAutomaticSignInAtLaunch())
        XCTAssertNil(next.plex.discoverToken(for: "account"))
    }

    func testChangedLocalLockRejectsSavedStartupUnlock() throws {
        let house = try household(provider: .emby)
        let env = launch(house)
        env.flow.setAutomaticallySignIn(true)
        var profile = env.profiles.activeProfile
        profile.replaceLock(with: ProfileLock.make(pin: "1357", iterations: 1))
        env.profiles.update(profile)
        let next = launch(house)
        next.flow.prepareLaunchPicker()
        XCTAssertTrue(next.flow.isChoosingProfile)
        XCTAssertTrue(next.flow.activeProfileAwaitsUnlock)
        XCTAssertNil(try house.startup.load())
    }

    func testSignOutAndPINCancelRemoveSavedSession() async throws {
        let house = try household()
        let env = launch(house)
        await authenticatePlex(env)
        env.flow.setAutomaticallySignIn(true)
        env.plex.forgetAccount("account")
        XCTAssertNil(try house.startup.load())
        await authenticatePlex(env)
        XCTAssertNotNil(try house.startup.load())
        env.plex.cancelPlexPIN()
        XCTAssertNil(try house.startup.load())
    }

    func testQueuedPINCannotUnlockLaterManualActivation() async throws {
        let house = try household()
        let env = launch(house)
        env.plex.setPlexHomeUserForActiveProfile(
            accountID: "account",
            user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        env.plex.submitPlexPIN("2468")
        env.flow.switchProfile(to: env.profiles.activeProfileID)
        await drain()
        XCTAssertNotNil(env.plex.pendingPlexPINRequest)
        XCTAssertNil(env.plex.discoverToken(for: "account"))
    }

    func testPreferenceDoesNotTravelWithProfileSettings() throws {
        let house = try household(provider: .jellyfin)
        let env = launch(house)
        env.flow.setAutomaticallySignIn(true)
        XCTAssertTrue(house.startup.isEnabled)
        XCTAssertNil(ProfileSettingsTransfer.capture(namespace: nil, defaults: house.defaults)["plozz.device.automaticallySignIn"])
        let otherDevice = try household(provider: .jellyfin)
        XCTAssertFalse(launch(otherDevice).plex.automaticallySignIn)
    }

    func testCorruptSessionFailsClosedWithVisibleError() throws {
        let house = try household(provider: .jellyfin)
        launch(house).flow.setAutomaticallySignIn(true)
        try house.secrets.setString("not valid JSON", for: "startupSession")
        let next = launch(house)
        XCTAssertFalse(next.plex.restoreAutomaticSignInAtLaunch())
        XCTAssertFalse(next.plex.automaticallySignIn)
        XCTAssertNotNil(next.plex.automaticSignInError)
    }

    func testAllBoundPlexAccountsRestoreTogether() async throws {
        let house = try household()
        let initial = launch(house)
        let original = try XCTUnwrap(initial.hub.accounts.first)
        var second = original
        second.id = "second-account"
        second.credentialRevision = CredentialRevision()
        try house.accounts.add(second, token: "second-owner")
        let env = launch(house)
        await authenticatePlex(env)
        env.plex.setPlexHomeUserForActiveProfile(
            accountID: second.id,
            user: PlexHomeUser(id: "other-parent", name: "Other Parent", requiresPIN: true)
        )
        env.plex.submitPlexPIN("2468")
        await drain()
        env.flow.setAutomaticallySignIn(true)
        XCTAssertTrue(env.plex.automaticallySignIn)
        let next = launch(house)
        XCTAssertTrue(next.plex.restoreAutomaticSignInAtLaunch())
        next.plex.ensurePlexIdentityForActiveProfile()
        XCTAssertNil(next.plex.pendingPlexPINRequest)
        XCTAssertEqual(next.plex.discoverToken(for: "account"), "discover-parent")
        XCTAssertEqual(next.plex.discoverToken(for: second.id), "discover-other-parent")

        let saved = try XCTUnwrap(house.startup.load())
        try house.startup.save(.init(
            profile: saved.profile, accounts: saved.accounts,
            plexCredentials: ["account": try XCTUnwrap(saved.plexCredentials["account"])]
        ))
        let incomplete = launch(house)
        XCTAssertFalse(incomplete.plex.restoreAutomaticSignInAtLaunch())
        XCTAssertNil(incomplete.plex.discoverToken(for: "account"), "No partial restore")
        XCTAssertNil(incomplete.plex.discoverToken(for: second.id))
    }

    func testInFlightPINCannotUnlockAReactivatedProfile() async throws {
        let house = try household()
        let env = launch(house)
        let flow = env.flow
        let profileID = env.profiles.activeProfileID
        env.plex.plexServerTokenResolve = { _, _, _ in
            await MainActor.run { flow.switchProfile(to: profileID) }
            return "stale-server-token"
        }
        env.plex.setPlexHomeUserForActiveProfile(
            accountID: "account",
            user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        env.plex.submitPlexPIN("2468")
        await drain()
        XCTAssertNotNil(env.plex.pendingPlexPINRequest)
        XCTAssertNil(env.plex.discoverToken(for: "account"))
        XCTAssertNil(try house.startup.load())
    }

    func testDeletedLastUsedProfileCannotUnlockFallbackProfile() throws {
        let house = try household(provider: .jellyfin)
        let env = launch(house)
        var fallback = env.profiles.activeProfile
        fallback.replaceLock(with: ProfileLock.make(pin: "1357", iterations: 1))
        env.profiles.update(fallback)
        let other = env.profiles.add(name: "Other", avatarSymbol: "person", colorIndex: 1)
        env.flow.switchProfile(to: other.id)
        env.flow.setAutomaticallySignIn(true)
        env.profiles.remove(other.id)
        let next = launch(house)
        next.flow.prepareLaunchPicker()
        XCTAssertTrue(next.flow.isChoosingProfile)
        XCTAssertTrue(next.flow.activeProfileAwaitsUnlock)
        XCTAssertNil(try house.startup.load())
    }

    private struct UnwritableStore: SecureStoring {
        enum Failure: Error { case unavailable }
        let backing: InMemorySecureStore
        func string(for key: String) -> String? { backing.string(for: key) }
        func readString(for key: String) throws -> String? { backing.string(for: key) }
        func setString(_ value: String, for key: String) throws { throw Failure.unavailable }
        func removeValue(for key: String) throws { throw Failure.unavailable }
    }

    func testFailedKeychainWriteDoesNotEnableAutomaticSignIn() throws {
        let house = try household(provider: .jellyfin)
        let broken = AutomaticSignInStore(
            defaults: house.defaults, secureStore: UnwritableStore(backing: house.secrets)
        )
        let env = launch(house, startup: broken)
        env.flow.setAutomaticallySignIn(true)
        XCTAssertFalse(env.plex.automaticallySignIn)
        XCTAssertNotNil(env.plex.automaticSignInError)
        XCTAssertNil(try house.startup.load())
    }

    func testFailedKeychainDeletionStillDisablesRestoration() throws {
        let house = try household(provider: .jellyfin)
        launch(house).flow.setAutomaticallySignIn(true)
        let broken = AutomaticSignInStore(
            defaults: house.defaults, secureStore: UnwritableStore(backing: house.secrets)
        )
        let env = launch(house, startup: broken)
        env.flow.setAutomaticallySignIn(false)
        XCTAssertFalse(env.plex.automaticallySignIn)
        XCTAssertNotNil(env.plex.automaticSignInError)
        XCTAssertNotNil(house.secrets.string(for: "startupSession"))
        XCTAssertFalse(launch(house).plex.restoreAutomaticSignInAtLaunch())
    }

    func testFailedInvalidationOnSwitchCannotResurrectOldTrust() throws {
        let house = try household(provider: .jellyfin)
        launch(house).flow.setAutomaticallySignIn(true)
        let broken = AutomaticSignInStore(
            defaults: house.defaults, secureStore: UnwritableStore(backing: house.secrets)
        )
        let env = launch(house, startup: broken)
        env.flow.switchProfile(to: env.profiles.activeProfileID)
        XCTAssertFalse(env.plex.automaticallySignIn)
        XCTAssertNotNil(env.plex.automaticSignInError)
        XCTAssertFalse(launch(house).plex.restoreAutomaticSignInAtLaunch())
    }

    func testLegacyPickerPreferenceCannotSkipSelectionOrGrantPINTrust() throws {
        for legacyValue in ["true", "false"] {
            let house = try household(provider: .jellyfin)
            house.defaults.set(
                Data(legacyValue.utf8), forKey: "com.plozz.profiles.askOnStartup"
            )
            let env = launch(house)
            let other = env.profiles.add(name: "Other", avatarSymbol: "person", colorIndex: 1)
            env.profiles.select(other.id)
            let next = launch(house)
            next.flow.prepareLaunchPicker()
            XCTAssertTrue(next.flow.isChoosingProfile)
            XCTAssertFalse(next.plex.automaticallySignIn)
        }
    }

    func testDisablingTheOnlyStartupSettingRestoresProfileSelection() throws {
        let house = try household(provider: .jellyfin)
        let env = launch(house)
        let other = env.profiles.add(name: "Other", avatarSymbol: "person", colorIndex: 1)
        env.flow.switchProfile(to: other.id)
        env.flow.setAutomaticallySignIn(true)
        let next = launch(house)
        next.flow.prepareLaunchPicker()
        XCTAssertFalse(next.flow.isChoosingProfile)
        next.flow.setAutomaticallySignIn(false)
        let disabled = launch(house)
        disabled.flow.prepareLaunchPicker()
        XCTAssertTrue(disabled.flow.isChoosingProfile)
        XCTAssertFalse(disabled.flow.isProfileSelectionCancelable)
    }

    func testSettingsOmitPINExplanationForUnlockedProfiles() throws {
        let house = try household()
        let env = launch(house)
        let settings = AutomaticSignInSettings(
            isEnabled: .constant(false), profile: env.profiles.activeProfile,
            accounts: env.hub.accounts
        )
        XCTAssertNil(settings.explanation)
        XCTAssertNil(settings.error)
    }

    func testSettingsExplainStartupPINBypassForLocalAndPlexLocks() throws {
        let house = try household()
        let env = launch(house)
        var locallyLocked = env.profiles.activeProfile
        locallyLocked.replaceLock(with: ProfileLock.make(pin: "1357", iterations: 1))
        let plexLocked = env.profiles.activeProfile.settingHomeUserBinding(
            .init(homeUserID: "parent", name: "Parent", requiresPIN: true),
            forPlexAccount: "account"
        )
        for profile in [locallyLocked, plexLocked] {
            let settings = AutomaticSignInSettings(
                isEnabled: .constant(false), profile: profile,
                accounts: env.hub.accounts
            )
            XCTAssertEqual(
                String(localized: try XCTUnwrap(settings.explanation)),
                "Skip the PIN at startup on this device."
            )
        }
        let removedAccount = AutomaticSignInSettings(
            isEnabled: .constant(false), profile: plexLocked, accounts: []
        )
        XCTAssertNil(removedAccount.explanation)
    }

    func testSettingsStillSurfaceErrorsWithoutPINHelp() throws {
        let env = launch(try household(provider: .jellyfin))
        let settings = AutomaticSignInSettings(
            isEnabled: .constant(false), profile: env.profiles.activeProfile,
            accounts: env.hub.accounts, error: "Couldn’t update automatic sign-in on this device. Try again."
        )
        XCTAssertNil(settings.explanation)
        XCTAssertNotNil(settings.error)
    }
}
