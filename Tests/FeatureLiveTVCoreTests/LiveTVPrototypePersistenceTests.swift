import CoreModels
import Foundation
import XCTest
@testable import FeatureLiveTVCore

@MainActor
final class LiveTVPrototypePersistenceTests: XCTestCase {
    func testSavedPreferencesSurviveAnInitiallyEmptyOrTemporarilyUnavailableCatalog() throws {
        let store = PreferencesFixtureStore()
        store.value = LiveTVPreferences(favoriteIDs: ["1"], recentChannelIDs: ["2", "1"])
        let model = LiveTVPrototypeModel(channels: [], preferencesStore: store)
        XCTAssertEqual(model.favoriteIDs, ["1"])
        XCTAssertEqual(model.recentChannelIDs, ["2", "1"])
        XCTAssertTrue(model.guideChannels.isEmpty)
        try model.replaceChannels(channels)
        XCTAssertEqual(model.guideChannels.filter { $0.section == .recent }.map(\.channel.id), ["2", "1"])
        XCTAssertEqual(model.guideChannels.filter { $0.section == .favorites }.map(\.channel.id), ["1"])
        try model.replaceChannels([])
        XCTAssertEqual(model.recentChannelIDs, ["2", "1"])
        XCTAssertEqual(model.favoriteIDs, ["1"])
        XCTAssertEqual(store.saves, 0)
    }

    func testMutationsAreRestoredByANewModel() {
        let store = PreferencesFixtureStore()
        let model = LiveTVPrototypeModel(channels: channels, preferencesStore: store)
        model.toggleFavorite("1")
        for id in ["0", "1", "2", "3", "1"] {
            model.tune(id)
            XCTAssertTrue(model.recordWatched(id))
        }
        let reopened = LiveTVPrototypeModel(channels: channels, preferencesStore: store)
        XCTAssertEqual(reopened.favoriteIDs, ["1"])
        XCTAssertEqual(reopened.recentChannelIDs, ["1", "3", "2"])
        XCTAssertEqual(reopened.guideChannels.filter { $0.channel.id == "1" }.map(\.section), [.recent, .favorites, .channels])
        reopened.toggleFavorite("1")
        XCTAssertTrue(LiveTVPrototypeModel(channels: channels, preferencesStore: store).favoriteIDs.isEmpty)
    }

    func testPreviewAndFailedOrStaleConfirmationDoNotPersistHistory() throws {
        let store = PreferencesFixtureStore()
        let model = LiveTVPrototypeModel(channels: channels, preferencesStore: store)
        let preview = LiveTVPreviewController(model: model)
        preview.focus("0")
        XCTAssertTrue(preview.commitPreview(try XCTUnwrap(preview.pendingRequest)))
        XCTAssertEqual(store.saves, 0)
        model.simulateTunerBusy = true
        preview.watch("1")
        XCTAssertFalse(model.recordWatched("1"))
        model.stop()
        XCTAssertFalse(model.recordWatched("0"))
        XCTAssertEqual(store.saves, 0)
        XCTAssertTrue(store.value.recentChannelIDs.isEmpty)
    }

    func testUnreadablePreferencesAreNotOverwrittenWithEmptyState() {
        let store = PreferencesFixtureStore()
        store.value = LiveTVPreferences(favoriteIDs: ["1"], recentChannelIDs: ["2"])
        store.failLoad = true
        let model = LiveTVPrototypeModel(channels: channels, preferencesStore: store)
        XCTAssertEqual(model.preferencesIssue, .loadFailed)
        model.dismissPreferencesIssue()
        model.toggleFavorite("0")
        model.tune("3")
        XCTAssertFalse(model.recordWatched("3"))
        XCTAssertEqual(model.preferencesIssue, .loadFailed)
        XCTAssertEqual(store.saves, 0)
        XCTAssertEqual(store.value.favoriteIDs, ["1"])
        XCTAssertEqual(store.value.recentChannelIDs, ["2"])
        store.failLoad = false
        model.retryPreferences()
        XCTAssertNil(model.preferencesIssue)
        XCTAssertEqual(model.favoriteIDs, ["1"])
        XCTAssertEqual(model.recentChannelIDs, ["2"])
        model.toggleFavorite("0")
        XCTAssertEqual(store.value.favoriteIDs, ["0", "1"])
    }

    func testFailedSaveIsVisibleAndRetryCommitsTheOriginalMutation() {
        let store = PreferencesFixtureStore()
        let model = LiveTVPrototypeModel(channels: channels, preferencesStore: store)
        store.failSave = true
        model.toggleFavorite("1")
        XCTAssertEqual(model.preferencesIssue, .saveFailed)
        XCTAssertTrue(model.favoriteIDs.isEmpty)
        XCTAssertTrue(store.value.favoriteIDs.isEmpty)
        model.dismissPreferencesIssue()
        store.failSave = false
        model.retryPreferences()
        XCTAssertNil(model.preferencesIssue)
        XCTAssertEqual(model.favoriteIDs, ["1"])
        XCTAssertEqual(store.value.favoriteIDs, ["1"])
    }

    func testEachModelKeepsItsInjectedProfileStoreWhenAnotherProfileOpens() {
        let firstStore = PreferencesFixtureStore()
        let secondStore = PreferencesFixtureStore()
        let first = LiveTVPrototypeModel(channels: channels, preferencesStore: firstStore)
        let second = LiveTVPrototypeModel(channels: channels, preferencesStore: secondStore)
        first.toggleFavorite("0")
        first.tune("1")
        first.recordWatched("1")
        second.toggleFavorite("2")
        second.tune("3")
        second.recordWatched("3")
        XCTAssertEqual(firstStore.value.favoriteIDs, ["0"])
        XCTAssertEqual(firstStore.value.recentChannelIDs, ["1"])
        XCTAssertEqual(secondStore.value.favoriteIDs, ["2"])
        XCTAssertEqual(secondStore.value.recentChannelIDs, ["3"])
    }

    private var channels: [LiveTVPrototypeChannel] {
        (0..<4).map {
            LiveTVPrototypeChannel(
                id: "\($0)", number: $0, name: "Channel \($0)", category: "News",
                symbol: "tv", accent: 0, source: .iptv, tagline: ""
            )
        }
    }
}

private final class PreferencesFixtureStore: LiveTVPreferencesStoring, @unchecked Sendable {
    enum Failure: Error { case unavailable }
    var value = LiveTVPreferences(favoriteIDs: [], recentChannelIDs: [])
    var failLoad = false
    var failSave = false
    var saves = 0

    func load() throws -> LiveTVPreferences {
        if failLoad { throw Failure.unavailable }
        return value
    }

    func save(_ preferences: LiveTVPreferences) throws {
        if failSave { throw Failure.unavailable }
        value = preferences
        saves += 1
    }
}
