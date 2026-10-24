#if os(iOS)
import CoreModels
import FeatureAuth
import XCTest
@testable import AppRuntime
@testable import AppShelliOS

@MainActor
final class ProfileSelectionPerformanceTests: XCTestCase {
    func testPerformanceLocalPINHandoff() async throws {
        try PerformanceProbe.requireEnabled()
        let lock = try XCTUnwrap(ProfileLock.make(pin: "1357"))
        let suite = "ProfilePINPerformance.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = PlozziOSAppModel(
            accountStore: AccountStore(secureStore: InMemorySecureStore()),
            profileStore: ProfileStore(defaults: defaults)
        )
        let original = app.profiles.activeProfileID
        let targets = (0..<15).map { index in
            app.profiles.add(name: "Viewer \(index)", avatarSymbol: "person.fill", colorIndex: index % 5)
        }
        defer { removeOwnedProfileSettings(targets.map(\.id)) }
        var target = targets[0]
        target.lock = lock
        app.profiles.update(target)
        // Measure switching within one household, not fresh-profile migrations
        // and app construction on every sample.
        try await Task.sleep(for: .milliseconds(200))
        try await PerformanceProbe.measure(self, scenario: "mobile-profile-pin-handoff") {
            app.selectProfile(original)
            app.selectProfile(target.id)
            XCTAssertEqual(app.lockedSwitch?.target.id, target.id)
            XCTAssertFalse(app.isUnlockedThisRun(target.id))

            var maxGap = Duration.zero
            let heartbeat = Task { @MainActor in
                var previous = ContinuousClock.now
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(2)) } catch { return }
                    let now = ContinuousClock.now
                    maxGap = max(maxGap, previous.duration(to: now))
                    previous = now
                }
            }
            defer { heartbeat.cancel() }
            try await Task.sleep(for: .milliseconds(10))
            let start = ContinuousClock.now
            let accepted = await app.submitProfileLockPIN("1357")
            let elapsed = start.duration(to: .now)
            try await Task.sleep(for: .milliseconds(10))
            XCTAssertTrue(accepted)
            XCTAssertNil(app.lockedSwitch)
            XCTAssertEqual(app.profiles.activeProfileID, target.id)
            XCTAssertFalse(app.activeProfileNeedsUnlock)
            func microseconds(_ duration: Duration) -> Int {
                let parts = duration.components
                return Int(parts.seconds) * 1_000_000 + Int(parts.attoseconds / 1_000_000_000_000)
            }
            return [
                "profiles": app.profiles.profiles.count,
                "verifierIterations": lock.iterations,
                "verificationMicroseconds": microseconds(elapsed),
                "maxMainActorGapMicroseconds": microseconds(maxGap)
            ]
        }
    }

    func testPerformanceProfileSelection() async throws {
        try PerformanceProbe.requireEnabled()
        let suite = "ProfileSelectionPerformance.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProfileStore(defaults: defaults)
        let profiles = ProfilesModel(store: store)
        let accounts = AccountStore(secureStore: InMemorySecureStore())
        try accounts.add(Account(
            id: "profile-performance-plex",
            server: MediaServer(
                id: "fixture", name: "Fixture",
                baseURL: URL(string: "https://plex.example")!, provider: .plex
            ), userID: "owner", userName: "Owner", deviceID: "fixture"
        ), token: "FIXTURE-OWNER")
        let binding = PlexHomeUserBinding(
            homeUserID: "protected", name: "Protected", requiresPIN: true, pinRequirementVerified: true
        )
        let targets = (0..<16).map { index in
            var profile = profiles.add(name: "Viewer \(index)", avatarSymbol: "person.fill", colorIndex: index % 5)
            profile = profile.settingHomeUserBinding(binding, forPlexAccount: "profile-performance-plex")
            profiles.update(profile)
            profiles.setActiveAccountIDs(["profile-performance-plex"], for: profile.id)
            return profile.id
        }
        defer { removeOwnedProfileSettings(targets) }
        let app = PlozziOSAppModel(accountStore: accounts, profileStore: store)
        app.plexHomeUsers.plexHomeUsersFetch = { _, _ in
            try await Task.sleep(for: .milliseconds(5))
            return [PlexHomeUser(id: "protected", name: "Protected", requiresPIN: true)]
        }
        app.plexHomeUsers.plexHomeUserSwitch = { _, _, _, _ in
            XCTFail("A selection may not authenticate without a PIN.")
            throw CancellationError()
        }
        try await PerformanceProbe.measure(self, scenario: "mobile-profile-selection") {
            var selectionMicroseconds = 0
            var maxSelectionMicroseconds = 0
            for id in targets {
                let start = ContinuousClock.now
                app.selectProfile(id)
                let elapsed = start.duration(to: .now).components
                let microseconds = Int(elapsed.seconds) * 1_000_000 + Int(elapsed.attoseconds / 1_000_000_000_000)
                selectionMicroseconds += microseconds
                maxSelectionMicroseconds = max(maxSelectionMicroseconds, microseconds)
                XCTAssertEqual(app.profiles.activeProfileID, id)
                XCTAssertNotNil(app.plexHomeUsers.pendingPlexPINRequest)
                await app.plexHomeUsers.waitForPlexPINRequirementCheck()
                XCTAssertEqual(app.plexHomeUsers.plexPINEntryAvailability, .available)
                XCTAssertNil(app.accountsProviders.tokenResolver("profile-performance-plex"))
            }
            return [
                "selections": targets.count, "selectionMicroseconds": selectionMicroseconds,
                "maxSelectionMicroseconds": maxSelectionMicroseconds
            ]
        }
    }

    private func removeOwnedProfileSettings(_ profileIDs: [String]) {
        let owned = Set(profileIDs)
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.components(separatedBy: ".").contains(where: owned.contains) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
#endif
