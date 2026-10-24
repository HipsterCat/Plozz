import CoreModels
import XCTest
@testable import FeatureLiveTV

final class LiveTVSourceProviderIconTests: XCTestCase {
    @MainActor
    func testServerSourcesSelectTheSharedProviderBrand() {
        XCTAssertEqual(LiveTVSourceProviderIcon(source: .plex).provider, .plex)
        XCTAssertEqual(LiveTVSourceProviderIcon(source: .jellyfin).provider, .jellyfin)
        XCTAssertEqual(LiveTVSourceProviderIcon(source: .emby).provider, .emby)
        XCTAssertEqual(LiveTVSourceProviderIcon(source: .iptv).provider, .iptv)
    }

    @MainActor
    func testUnavailableMetadataDoesNotInventAProviderIdentity() {
        XCTAssertNil(LiveTVSourceProviderIcon(source: nil).provider)
        XCTAssertNil(LiveTVSourceProviderIcon(source: .plozz).provider)
    }
}
