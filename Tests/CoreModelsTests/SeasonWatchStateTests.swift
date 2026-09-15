import XCTest
@testable import CoreModels

final class SeasonWatchStateTests: XCTestCase {
    func testSeasonMenuOffersBothStatesRegardlessOfContainerFlag() {
        for played in [false, true] {
            let season = MediaItem(id: "s2", title: "Season 2", kind: .season, isPlayed: played)
            let available = MediaItemActionCatalog.actions(for: season, supportsWatchState: true)
            XCTAssertEqual(
                MediaItemActionCatalog.seasonWatchActions(for: season, availableActions: available),
                [.markWatched, .markUnwatched]
            )
        }
    }

    func testSeasonMenuRequiresSeasonAndWatchCapability() {
        let season = MediaItem(id: "s2", title: "Season 2", kind: .season)
        let unavailable: [[MediaItemAction]] = [[], [.refreshMetadata], [.browseFiles]]
        for available in unavailable {
            XCTAssertTrue(MediaItemActionCatalog.seasonWatchActions(
                for: season, availableActions: available
            ).isEmpty)
        }
        let episode = MediaItem(id: "e1", title: "Episode", kind: .episode)
        XCTAssertTrue(MediaItemActionCatalog.seasonWatchActions(
            for: episode, availableActions: [.markWatched]
        ).isEmpty)
    }

    func testSeasonCascadeIsAccountAndParentScopedInBothDirections() {
        for played in [false, true] {
            let mutation = MediaItemMutation(
                itemIDs: ["s2"], scopedItemIDs: ["a:s2"],
                cascadesToSeasonEpisodes: true, played: played
            )
            let episode = MediaItem(
                id: "e1", title: "Episode", kind: .episode,
                seasonID: "s2", isPlayed: !played, sourceAccountID: "a",
                sources: [
                    MediaSourceRef(accountID: "a", itemID: "e1", isPlayed: !played),
                    MediaSourceRef(accountID: "b", itemID: "other", isPlayed: !played)
                ]
            )
            let updated = mutation.applied(to: episode)
            XCTAssertEqual(updated.isPlayed, played)
            XCTAssertEqual(updated.sources[0].isPlayed, played)
            XCTAssertEqual(updated.sources[1].isPlayed, !played)

            var earlierSeason = episode
            earlierSeason.seasonID = "s1"
            XCTAssertEqual(mutation.applied(to: earlierSeason), earlierSeason)
            var differentAccount = episode
            differentAccount.sourceAccountID = "b"
            XCTAssertFalse(mutation.targets(differentAccount))
            var untagged = episode
            untagged.sourceAccountID = nil
            XCTAssertFalse(mutation.targets(untagged))
            let series = MediaItem(id: "series", title: "Show", kind: .series, sourceAccountID: "a")
            XCTAssertFalse(mutation.targets(series))
        }
    }

    func testOrdinaryMutationsDoNotImplicitlyCascade() {
        let episode = MediaItem(id: "e1", title: "Episode", kind: .episode, seasonID: "s2")
        XCTAssertFalse(MediaItemMutation(itemIDs: ["s2"], played: true).targets(episode))
        XCTAssertFalse(MediaItemMutation(
            itemIDs: ["s2"], cascadesToSeasonEpisodes: true, favorite: true
        ).targets(episode))
    }

    func testSeasonCascadeSurvivesNotificationRoundTrip() {
        let mutation = MediaItemMutation(
            itemIDs: ["s2"], scopedItemIDs: ["a:s2"],
            cascadesToSeasonEpisodes: true, played: true, resumePosition: 0
        )
        let received = expectation(forNotification: .mediaItemDidMutate, object: nil) { note in
            XCTAssertEqual(MediaItemMutation.from(note), mutation)
            return true
        }
        mutation.post()
        wait(for: [received], timeout: 1)
    }

    func testDurableSeasonReplayUsesOriginalTargetsAndClearsCompletedResume() throws {
        var intent = WatchMutation(
            capturedAt: Date(), canonicalMediaID: "season",
            played: true, clearResume: true,
            targets: [WatchMutationTarget(accountID: "a", itemID: "s2")],
            kind: .season
        )
        intent.targets = []
        let decoded = try JSONDecoder().decode(WatchMutation.self, from: JSONEncoder().encode(intent))
        let mutation = try XCTUnwrap(MediaItemMutation(watchMutation: decoded))
        let episode = MediaItem(
            id: "e1", title: "Episode", kind: .episode, seasonID: "s2",
            resumePosition: 90, sourceAccountID: "a"
        )
        XCTAssertTrue(mutation.cascadesToSeasonEpisodes)
        XCTAssertTrue(mutation.applied(to: episode).isPlayed)
        XCTAssertNil(mutation.applied(to: episode).resumePosition)
    }
}
