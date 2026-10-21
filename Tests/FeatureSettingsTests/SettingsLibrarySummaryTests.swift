#if os(tvOS)
import CoreModels
import XCTest
@testable import FeatureSettings

@MainActor
final class SettingsLibrarySummaryTests: XCTestCase {
    func testStripShowsAddedSourceNamesGroupedByServerAndFilteredByProfile() {
        let accounts = [
            account("plex-owner", name: "Family Plex", provider: .plex, url: "https://plex.example"),
            account("plex-viewer", name: "Family Plex", provider: .plex, url: "https://plex.example"),
            account("jellyfin", name: "Cinema Server", provider: .jellyfin, url: "https://jellyfin.example"),
            account("excluded", name: "Another profile's server", provider: .silo, url: "https://silo.example")
        ]
        let included: Set<String> = ["plex-viewer", "jellyfin"]
        let groups = SettingsLibrariesRow.watchedServerGroups(in: accounts) { included.contains($0) }
        XCTAssertEqual(groups.map(\.serverName), ["Family Plex", "Cinema Server"])
        XCTAssertEqual(groups.map(\.providerKind), [.plex, .jellyfin])
        XCTAssertEqual(SettingsLibrariesRow.watchedServerGroups(in: accounts) { $0 == "excluded" }
            .map(\.serverName), ["Another profile's server"])
        XCTAssertTrue(SettingsLibrariesRow.watchedServerGroups(in: accounts) { _ in false }.isEmpty)
        XCTAssertTrue(SettingsLibrariesRow.watchedServerGroups(in: []) { _ in true }.isEmpty)
    }

    func testStripPreservesDistinctSharesAndTheirTransportIcons() {
        let accounts = [
            account("smb", name: "NAS", provider: .mediaShare, url: "smb://nas.example/Media"),
            account("dav", name: "NAS", provider: .mediaShare, url: "https://nas.example/Media")
        ]
        let groups = SettingsLibrariesRow.watchedServerGroups(in: accounts) { _ in true }
        XCTAssertEqual(groups.map(\.serverName), ["NAS", "NAS"])
        XCTAssertEqual(groups.map(\.transportKind), [.smb, .webDAV])
        XCTAssertNotEqual(groups[0].serverKey, groups[1].serverKey)
    }

    private func account(_ id: String, name: String, provider: ProviderKind, url: String) -> Account {
        Account(
            id: id, server: MediaServer(id: id, name: name, baseURL: URL(string: url)!, provider: provider),
            userID: id, userName: id, deviceID: "test"
        )
    }
}
#endif
