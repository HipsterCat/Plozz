import XCTest
@testable import CoreModels

final class AppVersionIdentityTests: XCTestCase {
    func testDistributedReleaseUsesPublicLabelAndRetainsAppleIdentity() {
        let identity = AppVersionIdentity(infoDictionary: [
            "CFBundleShortVersionString": "2026.9.25",
            "CFBundleVersion": "45",
            "PlozzReleaseID": "release/045",
            "PlozzReleaseVersion": "2026.9.29"
        ])

        XCTAssertEqual(identity.displayVersion, "2026.9.29")
        XCTAssertEqual(identity.marketingVersion, "2026.9.25")
        XCTAssertEqual(identity.build, "45")
    }

    func testSameDayReleasesDifferByBuildNotDateSuffix() {
        for build in ["45", "46"] {
            let identity = AppVersionIdentity(infoDictionary: [
                "CFBundleShortVersionString": "2026.9.25",
                "CFBundleVersion": build,
                "PlozzReleaseID": "release/0\(build)",
                "PlozzReleaseVersion": "2026.9.29"
            ])
            XCTAssertEqual("\(identity.displayVersion) (\(identity.build))", "2026.9.29 (\(build))")
            XCTAssertEqual(identity.marketingVersion, "2026.9.25")
        }
    }

    func testLocalAndLegacyBundlesFallBackWithoutClaimingANewRelease() {
        for releaseID in ["", "$(PLOZZ_RELEASE_ID)"] {
            let identity = AppVersionIdentity(infoDictionary: [
                "CFBundleShortVersionString": "2026.9.25",
                "CFBundleVersion": "4056.1",
                "PlozzReleaseID": releaseID,
                "PlozzReleaseVersion": "2026.9.29"
            ])
            XCTAssertEqual(identity.displayVersion, "2026.9.25")
            XCTAssertNil(identity.releaseVersion)
        }
        for releaseVersion in ["", " \n", "$(PLOZZ_RELEASE_VERSION)"] {
            let identity = AppVersionIdentity(infoDictionary: [
                "CFBundleShortVersionString": "2026.9.25",
                "PlozzReleaseID": "release/044",
                "PlozzReleaseVersion": releaseVersion
            ])
            XCTAssertEqual(identity.displayVersion, "2026.9.25")
            XCTAssertNil(identity.releaseVersion)
        }
    }

    func testLegacyDistributedBundleHasNoCustomVersionRequirement() {
        let identity = AppVersionIdentity(infoDictionary: [
            "CFBundleShortVersionString": "2026.9.25",
            "CFBundleVersion": "44",
            "PlozzReleaseID": "release/044"
        ])
        XCTAssertEqual(identity.displayVersion, "2026.9.25")
        XCTAssertEqual(identity.build, "44")
        XCTAssertNil(identity.releaseVersion)
    }
}
