import XCTest
@testable import CoreModels

final class ProfileLockPresentationTests: XCTestCase {
    func testPickerLockOnlyIncludesEnabledPlexSourcesButAlwaysIncludesLocalLock() {
        var profile = Profile(name: "Viewer").settingHomeUserBinding(
            .init(homeUserID: "viewer", name: "Viewer", requiresPIN: true), forPlexAccount: "plex"
        )
        XCTAssertTrue(profile.showsPINLock, "Setup summaries retain configured protection.")
        XCTAssertFalse(profile.showsPINLock(activePlexAccountIDs: []))
        XCTAssertFalse(profile.showsPINLock(activePlexAccountIDs: ["other-plex"]))
        XCTAssertTrue(profile.showsPINLock(activePlexAccountIDs: ["plex"]))
        profile = profile.settingHomeUserBinding(
            .init(homeUserID: "other", name: "Other", requiresPIN: false), forPlexAccount: "other-plex"
        )
        XCTAssertFalse(profile.showsPINLock(activePlexAccountIDs: ["other-plex"]))
        profile.lock = ProfileLock.make(pin: "1234", matchesPlexPIN: true, iterations: 1)
        XCTAssertTrue(profile.showsPINLock(activePlexAccountIDs: []))
    }

    func testLocalPlexCombinedAndUnprotectedLockHints() {
        var profile = Profile(name: "Viewer")
        XCTAssertFalse(profile.showsPINLock)
        profile.lock = ProfileLock.make(pin: "1234", iterations: 1)
        XCTAssertTrue(profile.showsPINLock)
        profile = profile.settingHomeUserBinding(
            .init(homeUserID: "viewer", name: "Viewer", requiresPIN: true), forPlexAccount: "plex"
        )
        XCTAssertTrue(profile.showsPINLock)
        profile.lock = nil
        XCTAssertFalse(profile.isLocked, "The presentation hint must not create a separate Plozz PIN gate.")
        XCTAssertTrue(profile.showsPINLock)
        profile = profile.settingHomeUserBinding(
            .init(homeUserID: "viewer", name: "Viewer", requiresPIN: false), forPlexAccount: "plex"
        )
        XCTAssertFalse(profile.showsPINLock)
    }

    func testLegacyBindingsRemainSupportedAndAuthoritativeBindingsWin() {
        var profile = Profile(
            name: "Viewer", plexHomeUserID: "viewer", plexHomeUserAccountID: "plex",
            plexHomeUserRequiresPIN: true
        )
        XCTAssertTrue(profile.showsPINLock)
        profile.plexHomeUserBindings = [
            "plex": .init(homeUserID: "viewer", name: "Viewer", requiresPIN: false)
        ]
        XCTAssertFalse(profile.showsPINLock, "The authoritative binding overrides stale legacy protection.")
    }
}
