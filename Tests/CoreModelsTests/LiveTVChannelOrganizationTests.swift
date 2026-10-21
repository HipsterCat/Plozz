import Foundation
import XCTest
@testable import CoreModels

final class LiveTVChannelOrganizationTests: XCTestCase {
    func testLegacyPreferencesDefaultToNoOrganizationRules() throws {
        let legacy = Data(#"{"favoriteIDs":["favorite"],"recentChannelIDs":["recent"]}"#.utf8)
        let decoded = try JSONDecoder().decode(LiveTVPreferences.self, from: legacy)
        XCTAssertEqual(decoded.organization, .init())
        XCTAssertEqual(decoded.favoriteIDs, ["favorite"])
    }

    func testOrganizationPersistsWithinItsProfileAndSurvivesCopyHelpers() throws {
        let suite = "LiveTVOrganization-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let primary = LiveTVPreferencesStore(defaults: defaults)
        let secondary = LiveTVPreferencesStore(defaults: defaults, namespace: "second")
        var organization = LiveTVChannelOrganization()
        organization.setCategory(.init(sourceID: "one", name: "US News", visibility: .hidden, isFavorite: true))
        organization.region = .init(isEnabled: true, countries: ["US"], languages: ["en"])
        var value = LiveTVPreferences(favoriteIDs: ["favorite"], organization: organization)
        value = value.hidingChannel(id: "hidden", name: "Hidden")
        try primary.save(value)
        XCTAssertEqual(try primary.load(), value)
        XCTAssertEqual(try secondary.load(), .empty)
        let restored = value.restoringChannel(id: "hidden")
        XCTAssertTrue(restored.hiddenChannelIDs.isEmpty)
        XCTAssertEqual(restored.organization.categories, organization.categories)
        XCTAssertEqual(restored.organization.shownChannelIDs, ["hidden"])
        XCTAssertEqual(value.restoringAllChannels().organization.shownChannelIDs, ["hidden"])
        XCTAssertEqual(value.migratingChannelIDs(["hidden": "new"]).organization.categories, organization.categories)
    }

    func testCategoryIdentityNormalizesNamesButNeverConflatesSources() {
        XCTAssertEqual(
            LiveTVCategoryRule.identifier(sourceID: "one", name: " NÉWS "),
            LiveTVCategoryRule.identifier(sourceID: "one", name: "news")
        )
        XCTAssertNotEqual(
            LiveTVCategoryRule.identifier(sourceID: "one", name: "News"),
            LiveTVCategoryRule.identifier(sourceID: "two", name: "News")
        )
    }

    func testNormalizationDoesNotInferRegionFromCategoryOrStationName() {
        var organization = LiveTVChannelOrganization()
        organization.region = .init(isEnabled: true, countries: ["US"], languages: ["English"])
        let metadata = LiveTVChannelOrganizationMetadata(
            sourceID: "source", categories: ["US English News"], countries: [], languages: []
        )
        XCTAssertEqual(organization.hiddenReason(channelID: "US English News", metadata: metadata), .missingMetadata)
        XCTAssertEqual(LiveTVRegionMetadata.country("USA"), "us")
        XCTAssertEqual(LiveTVRegionMetadata.language("eng"), "en")
        XCTAssertEqual(LiveTVRegionMetadata.country("United States"), "us")
    }
}
