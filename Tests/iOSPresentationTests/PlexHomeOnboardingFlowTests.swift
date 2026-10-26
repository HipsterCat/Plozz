#if os(iOS)
import CoreModels
import FeatureAuth
import XCTest
@testable import AppRuntime
@testable import AppShelliOS

@MainActor
final class PlexHomeOnboardingFlowTests: XCTestCase {
    func testImportAllContinuesThroughLibrariesProfileAndAppearance() async throws {
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
        app.selectPlexUserDuringOnboarding(users[0], addAllProfiles: true)
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
        app.finishFirstRunThemeSelection()
        XCTAssertNil(app.pendingFirstRunStep)
        XCTAssertTrue(app.profiles.firstRunProfileSetupComplete)
        await app.plexHomeUsers.waitForPlexPINRequirementCheck()
        XCTAssertEqual(app.plexHomeUsers.plexPINEntryAvailability, .available)
        XCTAssertEqual(app.plexHomeUsers.pendingPlexPINRequest?.homeUserID, "parent")
    }
}
#endif
