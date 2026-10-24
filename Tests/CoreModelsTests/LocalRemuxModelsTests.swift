import XCTest
@testable import CoreModels

final class LocalRemuxModelsTests: XCTestCase {
    private func descriptor(video: MediaSourceMetadata.VideoStream) throws -> LocalRemuxSourceDescriptor {
        LocalRemuxSourceDescriptor(
            itemID: "item", provider: .jellyfin,
            originalSource: .publicURL(try SecretFreeURLSource(url: URL(string: "https://example.test/movie.mkv")!)),
            sourceMetadata: .init(container: "mkv", video: video)
        )
    }

    func testExplicitProfileWinsOverRangeLabel() throws {
        XCTAssertEqual(try descriptor(video: .init(
            codec: "hevc", videoRangeType: "DOVIWithHDR10", dolbyVisionProfile: 7
        )).normalizedDolbyVisionProfile, 7)
    }

    func testSpecificProviderRangeTypesNormalizeWithoutMakingRoutingDecisions() throws {
        for range in ["DOVIWithHDR10", "DOVIWithHLG", "DOVIWithSDR"] {
            XCTAssertEqual(try descriptor(video: .init(codec: "hevc", videoRangeType: range)).normalizedDolbyVisionProfile, 8)
        }
        XCTAssertEqual(try descriptor(video: .init(codec: "hevc", videoRangeType: "DOVI")).normalizedDolbyVisionProfile, 5)
        XCTAssertNil(try descriptor(video: .init(codec: "hevc", videoRange: "DOVI")).normalizedDolbyVisionProfile)
    }
}
