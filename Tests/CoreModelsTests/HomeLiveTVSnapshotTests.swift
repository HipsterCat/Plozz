import CoreModels
import XCTest

final class HomeLiveTVSnapshotTests: XCTestCase {
    private func channel(_ id: String, profile: String = "profile") -> HomeLiveTVChannel {
        HomeLiveTVChannel(
            route: .init(
                profileID: profile, channelID: id, sourceID: "source",
                sourceAuthorizationID: "approval", serverAuthorizationID: "servers"
            ),
            name: id, sourceName: "Source", number: 1
        )
    }

    func testRecentOrderAndFavoritesFirstRowAreIndependentlyBounded() {
        let result = HomeLiveTVSnapshot.build(
            recentIDs: ["recent-3", "recent-2", "recent-1", "ignored"],
            favoriteIDs: ["favorite-2", "favorite-1", "recent-2"],
            fallbackIDs: (0..<100).map { "channel-\($0)" },
            channel: { self.channel($0) }
        )
        XCTAssertEqual(result.recentChannels.map(\.name), ["recent-3", "recent-2", "recent-1"])
        XCTAssertEqual(result.channels.map(\.name), [
            "favorite-2", "favorite-1", "recent-2", "recent-3", "recent-1",
            "channel-0", "channel-1", "channel-2"
        ])
    }

    func testMissingFavoritesCannotCauseAnUnboundedCatalogWalk() {
        var reads: [String] = []
        let result = HomeLiveTVSnapshot.build(
            recentIDs: ["watched", "watched"],
            favoriteIDs: (0..<5_000).map { "missing-\($0)" },
            fallbackIDs: (0..<5_000).map { "channel-\($0)" }
        ) { id in
            reads.append(id)
            return id == "watched" ? self.channel(id) : nil
        }
        XCTAssertEqual(reads.count, HomeLiveTVSnapshot.maximumCandidateCount)
        XCTAssertEqual(Set(reads).count, reads.count)
        XCTAssertEqual(result.recentChannels.map(\.name), ["watched"])
        XCTAssertEqual(result.channels.map(\.name), ["watched"])
    }

    @MainActor
    func testSelectionIsProfileScopedExplicitAndConsumedOnce() throws {
        let model = HomeLiveTVModel(profileID: "profile")
        let card = channel("one")
        let snapshot = HomeLiveTVSnapshot(recentChannels: [card], channels: [card])
        model.publish(snapshot)
        XCTAssertNil(model.pendingRequest, "Painting cached cards is not a tune request.")
        XCTAssertFalse(model.request(channel("other", profile: "other-profile").route, in: snapshot))
        XCTAssertFalse(model.request(card.route, in: .empty), "A hidden card cannot route.")
        XCTAssertTrue(model.request(card.route, in: snapshot))
        let old = try XCTUnwrap(model.pendingRequest)
        XCTAssertTrue(model.request(card.route, in: snapshot))
        let latest = try XCTUnwrap(model.pendingRequest)
        XCTAssertFalse(model.consume(old), "A late destination cannot consume a newer press.")
        XCTAssertTrue(model.consume(latest))
        XCTAssertFalse(model.consume(latest))
        XCTAssertNil(model.pendingRequest)

        let other = HomeLiveTVModel(profileID: "other-profile")
        other.publish(snapshot)
        XCTAssertTrue(other.snapshot.isEmpty)
        XCTAssertNil(other.pendingRequest)
    }
}
