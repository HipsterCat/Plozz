import CoreModels
import Foundation
import XCTest
@testable import FeatureLiveTVCore

final class LibraryChannelArtworkIdentityTests: XCTestCase {
    @MainActor
    func testRenamingAChannelPreservesItsMood() throws {
        let channel = makeChannel(source: .plozz, mood: .calm)
        let model = LiveTVPrototypeModel(now: Date(), channels: [channel])
        XCTAssertTrue(model.setMetadataOverride(.init(name: "Horror"), channelID: channel.id))
        let renamed = try XCTUnwrap(model.channel(id: channel.id))
        XCTAssertEqual(renamed.name, "Horror")
        XCTAssertEqual(renamed.plozzChannelMood, .calm)
        XCTAssertEqual(renamed.playerItem(program: nil).plozzChannelMood, .calm)
    }

    func testMoodSurvivesGuidePersistenceAndPlayerHandoff() throws {
        let channel = makeChannel(source: .plozz, mood: .calm)
        let restored = try JSONDecoder().decode(
            LiveTVPrototypeChannel.self, from: JSONEncoder().encode(channel)
        )
        XCTAssertEqual(restored.plozzChannelMood, .calm)
        XCTAssertEqual(restored.playerItem(program: nil).plozzChannelMood, .calm)
        XCTAssertEqual(restored.playerItem(program: nil).plozzChannelID, channel.id)
    }

    func testOlderGuideCachesDecodeWithoutAnArtworkMood() throws {
        let data = try JSONEncoder().encode(makeChannel(source: .plozz))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["plozzChannelMood"])
        let restored = try JSONDecoder().decode(LiveTVPrototypeChannel.self, from: data)
        XCTAssertNil(restored.plozzChannelMood)
        XCTAssertNotNil(restored.playerItem(program: nil).plozzChannelID)
    }

    func testExternalChannelsNeverAcquirePlozzBrandingFromAMood() {
        for source in LiveTVPrototypeSource.allCases where source != .plozz {
            let item = makeChannel(source: source, mood: .playful).playerItem(program: nil)
            XCTAssertNil(item.plozzChannelID)
            XCTAssertNil(item.plozzChannelMood)
        }
    }

    private func makeChannel(
        source: LiveTVPrototypeSource, mood: LibraryChannelArtworkMood? = nil
    ) -> LiveTVPrototypeChannel {
        .init(id: "channel", number: 1, name: "Renamed", category: "Plozz", symbol: "tv",
              accent: 0, source: source, tagline: "", plozzChannelMood: mood)
    }
}
