import CoreModels
import Foundation
import XCTest
@testable import FeatureLiveTVCore

@MainActor
final class LiveTVChannelOrganizationTests: XCTestCase {
    func testCountryOrLanguageAndMissingMetadataRemainRecoverable() {
        let channels = [
            channel("us", country: "US", language: "es"),
            channel("english", country: "GB", language: "English"),
            channel("other", country: "FR", language: "fr"),
            channel("unknown"),
            channel("server", source: .plex)
        ]
        let model = LiveTVPrototypeModel(channels: channels)
        XCTAssertTrue(model.setRegionalFilter(.init(isEnabled: true, countries: ["United States"], languages: ["eng"])))
        XCTAssertEqual(model.visibleChannels.map(\.id), ["english", "server", "us"])
        XCTAssertEqual(model.unhiddenCatalogChannels.map(\.id), ["us", "english", "server"])
        XCTAssertEqual(model.programmeSearchChannelIDs, ["us", "english", "server"])
        XCTAssertEqual(model.hiddenChannelEntries.first { $0.id == "unknown" }?.reason, .missingMetadata)
        XCTAssertEqual(model.hiddenChannelEntries.first { $0.id == "other" }?.reason, .region)
        XCTAssertTrue(model.showChannel("unknown"))
        XCTAssertTrue(model.visibleChannels.contains { $0.id == "unknown" })
        XCTAssertTrue(model.hideChannel(channels[3]))
        XCTAssertFalse(model.visibleChannels.contains { $0.id == "unknown" }, "Explicit Hide still wins")
        XCTAssertTrue(model.resetOrganizationVisibility())
        XCTAssertEqual(model.effectiveHiddenChannelIDs, ["unknown"])
    }

    func testCategoryRulesSurviveEmptyCatalogAndApplyOnlyToTheSelectedSource() throws {
        let store = OrganizationStore()
        let model = LiveTVPrototypeModel(channels: [channel("one"), channel("two", sourceID: "other")], preferencesStore: store)
        XCTAssertTrue(model.setCategoryRule(.init(sourceID: "source", name: "News", visibility: .hidden, isFavorite: true)))
        XCTAssertEqual(store.saves, 1)
        XCTAssertEqual(model.visibleChannels.map(\.id), ["two"])
        XCTAssertEqual(model.favoriteIDs, ["one"])
        XCTAssertTrue(store.value.favoriteIDs.isEmpty, "Category favorites are rules, not expanded catalog IDs")
        try model.replaceChannels([])
        XCTAssertEqual(model.categorySummaries.count, 1)
        let restored = LiveTVPrototypeModel(
            channels: [channel("new"), channel("two", sourceID: "other")], preferencesStore: store
        )
        XCTAssertEqual(restored.visibleChannels.map(\.id), ["two"])
        XCTAssertEqual(restored.favoriteIDs, ["new"])
        XCTAssertEqual(store.saves, 1, "Refresh must not save one preference per new channel")
        XCTAssertTrue(restored.setCategoryRule(.init(sourceID: "source", name: "News", visibility: .shown, isFavorite: true)))
        XCTAssertEqual(restored.visibleChannels.map(\.id), ["new", "two"])
    }

    func testRemovingCategoryFavoritePreservesIndividualFavoritesAndIndividualExclusions() throws {
        let store = OrganizationStore()
        let model = LiveTVPrototypeModel(channels: [channel("one"), channel("two")], preferencesStore: store)
        model.toggleFavorite("one")
        XCTAssertTrue(model.setCategoryRule(.init(sourceID: "source", name: "News", isFavorite: true)))
        XCTAssertEqual(model.favoriteIDs, ["one", "two"])
        XCTAssertEqual(model.guideChannels.filter { $0.section == .favorites }.map(\.channel.id), ["one", "two"])
        model.toggleFavorite("two")
        XCTAssertEqual(model.favoriteIDs, ["one"])
        try model.replaceChannels([channel("one"), channel("two"), channel("new")])
        XCTAssertEqual(model.favoriteIDs, ["one", "new"])
        XCTAssertTrue(model.setCategoryRule(.init(sourceID: "source", name: "News")))
        XCTAssertEqual(model.favoriteIDs, ["one"])
        XCTAssertTrue(model.setCategoryRule(.init(sourceID: "source", name: "News", isFavorite: true)))
        XCTAssertEqual(model.favoriteIDs, ["one", "new"])
        model.toggleFavorite("two")
        XCTAssertEqual(model.favoriteIDs, ["one", "two", "new"])
    }

    func testCategoryOverridesAndOverlapsDoNotOverrideManualOrScanHiding() {
        let one = channel("one", groups: ["News", "Sports"])
        let model = LiveTVPrototypeModel(channels: [one])
        XCTAssertTrue(model.setRegionalFilter(.init(isEnabled: true, countries: ["US"])))
        XCTAssertTrue(model.visibleChannels.isEmpty)
        XCTAssertTrue(model.setCategoryRule(.init(sourceID: "source", name: "News", visibility: .shown)))
        XCTAssertEqual(model.visibleChannels.map(\.id), ["one"])
        XCTAssertTrue(model.setCategoryRule(.init(sourceID: "source", name: "Sports", visibility: .hidden)))
        XCTAssertTrue(model.visibleChannels.isEmpty)
        XCTAssertTrue(model.showChannel("one"))
        XCTAssertEqual(model.visibleChannels.map(\.id), ["one"])
        model.setScanHiddenChannelIDs(["one"])
        XCTAssertTrue(model.visibleChannels.isEmpty)
        XCTAssertEqual(model.hiddenChannelEntries.first?.reason, .scan)
        XCTAssertFalse(model.showChannel("one"))
        model.setScanHiddenChannelIDs([])
        XCTAssertEqual(model.visibleChannels.map(\.id), ["one"])
    }

    func testFailedRuleSaveDoesNotFilterAndRetryPreservesOtherSavedRules() {
        let store = OrganizationStore()
        let model = LiveTVPrototypeModel(channels: [channel("one")], preferencesStore: store)
        store.failSave = true
        let rule = LiveTVCategoryRule(sourceID: "source", name: "News", visibility: .hidden)
        XCTAssertFalse(model.setCategoryRule(rule))
        XCTAssertEqual(model.preferencesIssue, .saveFailed)
        XCTAssertEqual(model.visibleChannels.map(\.id), ["one"])
        let other = LiveTVCategoryRule(sourceID: "other", name: "Sports", isFavorite: true)
        store.value.organization.setCategory(other)
        store.failSave = false
        model.retryPreferences()
        XCTAssertEqual(store.value.organization.categories.count, 2)
        XCTAssertTrue(model.visibleChannels.isEmpty)
        XCTAssertNil(model.preferencesIssue)
    }

    func testMetadataEditsAndIdentityMigrationReevaluateAndPreserveExceptions() throws {
        let store = OrganizationStore()
        let model = LiveTVPrototypeModel(channels: [channel("old")], preferencesStore: store)
        XCTAssertTrue(model.setRegionalFilter(.init(isEnabled: true, languages: ["en"])))
        XCTAssertTrue(model.visibleChannels.isEmpty)
        XCTAssertTrue(model.setMetadataOverride(.init(language: "English"), channelID: "old"))
        XCTAssertEqual(model.visibleChannels.map(\.id), ["old"])
        XCTAssertTrue(model.showChannel("old"))
        XCTAssertTrue(model.setCategoryRule(.init(sourceID: "source", name: "News", isFavorite: true)))
        model.toggleFavorite("old")
        XCTAssertTrue(model.migrateChannelIDs(["old": "new"]))
        XCTAssertEqual(store.value.organization.shownChannelIDs, ["new"])
        XCTAssertEqual(store.value.organization.excludedFavoriteIDs, ["new"])
    }

    func testLargeCategoryFavoritesUseOneRuleAndIncludeEveryChannel() throws {
        let store = OrganizationStore()
        let channels = (0..<10_000).map { channel(String($0)) }
        let model = LiveTVPrototypeModel(channels: channels, preferencesStore: store)
        XCTAssertTrue(model.setCategoryRule(.init(sourceID: "source", name: "News", isFavorite: true)))
        XCTAssertEqual(model.favoriteIDs.count, 10_000)
        XCTAssertEqual(model.guideChannels.filter { $0.section == .favorites }.count, 10_000)
        XCTAssertEqual(model.categorySummaries.first?.channelCount, 10_000)
        XCTAssertEqual(store.saves, 1)
        XCTAssertLessThan(try JSONEncoder().encode(store.value).count, 2_048)
        XCTAssertEqual(model.homeFavoriteChannelIDs.count, HomeLiveTVSnapshot.maximumCandidateCount)
    }

    private func channel(
        _ id: String, sourceID: String = "source", source: LiveTVPrototypeSource = .iptv,
        country: String? = nil, language: String? = nil, groups: [String]? = nil
    ) -> LiveTVPrototypeChannel {
        .init(
            id: id, number: 1, name: id, category: "News", symbol: "tv", accent: 0,
            source: source, tagline: "", configuredSourceID: sourceID,
            language: language, country: country, groups: groups
        )
    }
}

private final class OrganizationStore: LiveTVPreferencesStoring, @unchecked Sendable {
    var value = LiveTVPreferences()
    var failSave = false
    var saves = 0
    func load() throws -> LiveTVPreferences { value }
    func save(_ preferences: LiveTVPreferences) throws {
        if failSave { throw LiveTVPreferencesStoreError.encodingFailed }
        value = preferences
        saves += 1
    }
}
