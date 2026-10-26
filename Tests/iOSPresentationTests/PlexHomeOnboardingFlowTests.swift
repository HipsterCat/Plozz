#if os(iOS)
import CoreModels
import CoreUI
import FeatureAuth
import XCTest
@testable import AppRuntime
@testable import AppShelliOS

@MainActor
final class PlexHomeOnboardingFlowTests: XCTestCase {
    func testImportedSelectionRetargetsTheExistingSetupOwner() throws {
        let suite = "PlexHomeOnboardingOwnership.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProfileStore(defaults: defaults)
        store.setFirstRunProfileSetupComplete(true)
        let app = PlozziOSAppModel(
            accountStore: AccountStore(secureStore: InMemorySecureStore()), profileStore: store
        )
        let previous = app.profiles.add(name: "Previous", isAwaitingSetup: true)
        app.selectProfile(previous.id)
        app.resumeProfileOnboardingIfNeeded()
        XCTAssertEqual(app.profileOnboardingID, previous.id)
        let selected = app.profiles.add(name: "Imported", isAwaitingSetup: true)
        app.selectProfileForPlexOnboarding(selected.id) {}
        XCTAssertEqual(app.profileOnboardingID, selected.id)
        XCTAssertEqual(app.profileOnboardingStep, .libraries)
        app.advanceProfileOnboarding()
        XCTAssertEqual(app.profileBeingOnboarded?.id, selected.id)
        XCTAssertEqual(app.profileOnboardingStep, .seerr)
        XCTAssertTrue(app.profiles.profiles.first { $0.id == previous.id }?.needsSetup == true)
        XCTAssertFalse(app.profiles.activeProfile.needsSetup)
    }

    func testImportAllContinuesThroughLibrariesProfileAndAppearance() async throws {
        try await verifyImportAll(selectedIndex: 0)
        try await verifyImportAll(selectedIndex: 1)
    }

    private func verifyImportAll(selectedIndex: Int) async throws {
        let suite = "PlexHomeOnboardingFlow.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = PlozziOSAppModel(
            accountStore: AccountStore(secureStore: InMemorySecureStore()),
            profileStore: ProfileStore(defaults: defaults)
        )
        let users = [
            PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true, isAdmin: true),
            PlexHomeUser(id: "child", name: "Child", requiresPIN: false, isRestricted: true)
        ]
        app.plexHomeUsers.plexHomeUsersFetch = { _, _ in users }
        let authentication = AuthenticationGate()
        app.plexHomeUsers.plexHomeUserSwitch = { _, _, _, _ in await authentication.token() }
        app.plexHomeUsers.plexServerTokenResolve = { _, _, _ in "fixture-server" }
        let sessions = ["a", "b"].map {
            UserSession(
                server: MediaServer(
                    id: $0, name: $0, baseURL: URL(string: "https://\($0).example.invalid")!, provider: .plex
                ), userID: "owner", userName: "Owner", deviceID: "fixture", accessToken: "fixture-\($0)"
            )
        }
        XCTAssertTrue(app.persist(sessions))
        for _ in 0..<200 {
            if app.plexHomeUsers.pendingPlexUserSelection != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(app.plexHomeUsers.pendingPlexUserSelection)
        XCTAssertEqual(app.importPlexHomeProfilesDuringOnboarding(), .added)
        XCTAssertEqual(app.profiles.profiles.count, 2, "Import precedes the viewer's choice.")
        let selectedID = try XCTUnwrap(app.plexHomeUsers.importedOnboardingProfileID(for: users[selectedIndex]))
        app.selectPlexUserDuringOnboarding(users[selectedIndex], addAllProfiles: true)
        XCTAssertEqual(app.profiles.activeProfileID, selectedID)
        XCTAssertEqual(app.profiles.profiles.first?.name, "Parent")
        for _ in 0..<200 {
            if app.pendingLibrarySelection != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(app.pendingLibrarySelection)
        XCTAssertEqual(app.profiles.profiles.count, 2)
        XCTAssertFalse(app.profiles.firstRunProfileSetupComplete)
        app.completeLibrarySelection()
        XCTAssertEqual(app.pendingFirstRunStep, .confirmProfile)
        app.confirmFirstRunProfile()
        XCTAssertEqual(app.pendingFirstRunStep, .seerr)
        app.completeFirstRunSeerrSetup()
        XCTAssertEqual(app.pendingFirstRunStep, .theme)
        XCTAssertEqual(authentication.calls, 0, "Import and selection must not authenticate every Home user.")
        authentication.permits = true
        app.finishFirstRunThemeSelection()
        XCTAssertNil(app.pendingFirstRunStep)
        XCTAssertTrue(app.profiles.firstRunProfileSetupComplete)
        XCTAssertFalse(app.profiles.activeProfile.needsSetup)
        if selectedIndex == 1 {
            XCTAssertEqual(app.profiles.activeNamespace, selectedID)
            XCTAssertTrue(try XCTUnwrap(app.profiles.profiles.first).needsSetup)
        }
        await app.plexHomeUsers.waitForPlexPINRequirementCheck()
        await app.plexHomeUsers.waitForPlexPINRequirementCheck()
        if selectedIndex == 0 {
            XCTAssertEqual(app.plexHomeUsers.plexPINEntryAvailability, .available)
            XCTAssertEqual(app.plexHomeUsers.pendingPlexPINRequest?.homeUserID, "parent")
        } else {
            XCTAssertNil(app.plexHomeUsers.pendingPlexPINRequest)
            XCTAssertGreaterThan(authentication.calls, 0)
        }
    }
}

@MainActor
private final class AuthenticationGate {
    var permits = false
    var calls = 0
    func token() -> String {
        XCTAssertTrue(permits, "Only the chosen viewer authenticates after setup.")
        calls += 1
        return "fixture-cloud"
    }
}
#endif
