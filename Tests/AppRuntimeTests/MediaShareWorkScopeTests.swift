import CoreModels
import Foundation
import Observation
import XCTest
@testable import AppRuntime

@MainActor
final class MediaShareWorkScopeTests: XCTestCase {
    private func account(
        id: String = "share",
        provider: ProviderKind = .mediaShare,
        configuration: MediaShareLibraryConfiguration? = .init(name: "Movies", contentType: .movies)
    ) -> Account {
        Account(
            id: id,
            server: MediaServer(
                id: id, name: id, baseURL: URL(string: "smb://nas.invalid/Media")!,
                provider: provider, mediaShareLibraryConfiguration: configuration
            ),
            userID: "fixture", userName: "Fixture", deviceID: "device"
        )
    }

    func testOnlyAuthorizedActiveMediaSharesWithEnabledLibrariesAreEligible() {
        let accounts = [account(), account(id: "disabled"), account(id: "plex", provider: .plex)]
        var visibility = HomeLibraryVisibility()
        func resolve(_ authorized: Bool = true, active: Set<String> = ["share", "plex"]) -> MediaShareWorkScope {
            .resolve(profileID: "profile", isProfileAuthorized: authorized,
                     activeAccountIDs: active, accounts: accounts, visibility: visibility)
        }
        XCTAssertEqual(resolve().accountKeys, ["share"])
        XCTAssertTrue(resolve(false).accountKeys.isEmpty)
        XCTAssertTrue(resolve(active: []).accountKeys.isEmpty)
        visibility.setEnabled(false, for: "share:share:lib:movies")
        XCTAssertTrue(resolve().accountKeys.isEmpty)
        visibility.setEnabled(true, for: "share:share:lib:movies")
        visibility.disabledGlobalHomeRows = Set(HomeGlobalRow.allCases.map(\.rawValue))
        visibility.mergeLibrariesOnHome = false
        XCTAssertEqual(resolve().accountKeys, ["share"], "Hiding Home rows is not disabling a library.")
    }

    func testConfiguredTelevisionAnimeAndPersonalRootsUseTheirActualLibraryPolicy() {
        for (type, anime, key) in [
            (MediaShareLibraryConfiguration.ContentType.tvShows, false, "share:lib:tv"),
            (.tvShows, true, "share:lib:anime"),
            (.movies, true, "share:lib:movies")
        ] {
            let source = account(configuration: .init(name: "Library", contentType: type, isAnime: anime))
            var visibility = HomeLibraryVisibility()
            visibility.setEnabled(false, for: "share:\(key)")
            let scope = MediaShareWorkScope.resolve(
                profileID: "profile", isProfileAuthorized: true, activeAccountIDs: ["share"],
                accounts: [source], visibility: visibility
            )
            XCTAssertTrue(scope.accountKeys.isEmpty, key)
        }
        let personal = account(configuration: .init(name: "Personal", contentType: .personalVideos))
        XCTAssertTrue(MediaShareWorkScope.resolve(
            profileID: "profile", isProfileAuthorized: true, activeAccountIDs: ["share"],
            accounts: [personal], visibility: .default
        ).accountKeys.isEmpty)
    }

    func testMixedRootPausesOnlyWhenEveryIndexedCategoryIsDisabled() {
        var visibility = HomeLibraryVisibility()
        let source = account(configuration: nil)
        func scope() -> MediaShareWorkScope {
            .resolve(profileID: "profile", isProfileAuthorized: true, activeAccountIDs: ["share"],
                     accounts: [source], visibility: visibility)
        }
        visibility.setEnabled(false, for: "share:share:lib:movies")
        XCTAssertEqual(scope().accountKeys, ["share"])
        visibility.setEnabled(false, for: "share:share:lib:tv")
        visibility.setEnabled(false, for: "share:share:lib:anime")
        XCTAssertTrue(scope().accountKeys.isEmpty, "Raw-file browsing must not keep automatic metadata work alive.")
    }

    @Observable
    final class Settings {
        var visibility = HomeLibraryVisibility()
    }

    @Observable
    final class State {
        var profileID = "first"
        var authorized = true
        var active: Set<String> = ["share"]
        var settings = Settings()
    }

    private actor Recorder {
        var scopes: [MediaShareWorkScope] = []
        var revisions: [UInt64] = []
        func record(_ scope: MediaShareWorkScope, _ revision: UInt64) {
            scopes.append(scope)
            revisions.append(revision)
        }
        func waitForCount(_ count: Int) async -> Bool {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while scopes.count < count, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(2))
            }
            return scopes.count == count
        }
    }

    func testControllerTracksMembershipAdmissionAndReplacedProfileSettings() async {
        let state = State()
        let recorder = Recorder()
        let source = account()
        let controller = MediaShareWorkScopeController(
            snapshot: {
                .resolve(profileID: state.profileID, isProfileAuthorized: state.authorized,
                         activeAccountIDs: state.active, accounts: [source],
                         visibility: state.settings.visibility)
            },
            apply: { await recorder.record($0, $1) }
        )
        controller.start()
        controller.start()
        var arrived = await recorder.waitForCount(1)
        XCTAssertTrue(arrived)
        state.settings.visibility.setEnabled(false, for: "share:share:lib:movies")
        arrived = await recorder.waitForCount(2)
        XCTAssertTrue(arrived)
        state.profileID = "second"
        state.settings = Settings()
        arrived = await recorder.waitForCount(3)
        XCTAssertTrue(arrived)
        state.active = []
        arrived = await recorder.waitForCount(4)
        XCTAssertTrue(arrived)
        state.active = ["share"]
        state.authorized = false
        // Membership changed, but the locked profile still has no eligible work.
        for _ in 0..<100 { await Task.yield() }
        state.authorized = true
        arrived = await recorder.waitForCount(5)
        XCTAssertTrue(arrived)
        let scopes = await recorder.scopes
        XCTAssertEqual(scopes.map(\.accountKeys), [["share"], [], ["share"], [], ["share"]])
        XCTAssertEqual(scopes[2].profileID, "second")
        let revisions = await recorder.revisions
        XCTAssertEqual(revisions, [1, 2, 3, 4, 5])
    }
}
