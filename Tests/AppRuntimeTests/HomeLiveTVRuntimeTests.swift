import CoreModels
import XCTest
@testable import AppRuntime

@MainActor
final class HomeLiveTVRuntimeTests: XCTestCase {
    func testCachedHomeRespectsRegionalVisibilityAndIndividualRecovery() throws {
        let suite = "HomeLiveTVRegions-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = Profile(id: "profile", name: "Profile")
        let configuration = LiveTVSourcesConfiguration(playlists: [
            .init(id: "source", name: "Playlist", playlistURL: URL(string: "https://example.test/list.m3u")!)
        ])
        let authorization = try LiveTVSourceApprovalStore(defaults: defaults, profileID: profile.id).authorization(
            context: .init(profile: profile, parentalPIN: nil, activeAccountIDs: []), configuration: configuration
        )
        let card = HomeLiveTVChannel(
            route: .init(profileID: profile.id, channelID: "unknown", sourceID: "source",
                         sourceAuthorizationID: authorization.identity, serverAuthorizationID: "server"),
            name: "Unknown", sourceName: "Playlist", number: 1,
            organizationMetadata: .init(sourceID: "source", categories: ["News"], countries: [], languages: [])
        )
        var preferences = LiveTVPreferences()
        preferences.organization.region = .init(isEnabled: true, languages: ["en"])
        func visible() -> HomeLiveTVSnapshot {
            HomeLiveTVRuntime.visibleSnapshot(
                cached: .init(channels: [card]), profileID: profile.id, serverAuthorizationID: "server",
                configuration: configuration, authorization: authorization, preferences: preferences
            )
        }
        XCTAssertTrue(visible().isEmpty)
        preferences.organization.shownChannelIDs.insert("unknown")
        XCTAssertEqual(visible().channels.map(\.name), ["Unknown"])
    }

    func testColdHomeDoesNotInitializeTheCatalogCache() {
        let profileID = UUID().uuidString
        XCTAssertNil(LiveTVCatalogStorage.existingCache(profileID: profileID))
        let model = HomeLiveTVRuntime.model(profileID: profileID)
        for _ in 0..<100 {
            XCTAssertTrue(model.snapshot.isEmpty)
            XCTAssertNil(model.pendingRequest)
        }
        XCTAssertNil(LiveTVCatalogStorage.existingCache(profileID: profileID))
        XCTAssertFalse(model === HomeLiveTVRuntime.model(profileID: UUID().uuidString))
    }

    func testHiddenDisabledRemovedAndUnauthorizedSourcesFailClosed() throws {
        let suite = "HomeLiveTVRuntimeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = Profile(id: "profile", name: "Profile")
        let approvals = LiveTVSourceApprovalStore(defaults: defaults, profileID: profile.id)
        let context = LiveTVSourceApprovalContext(profile: profile, parentalPIN: nil, activeAccountIDs: ["account"])
        let configuration = LiveTVSourcesConfiguration(
            playlists: [.init(id: "playlist", name: "Playlist", playlistURL: URL(string: "https://example.test/list.m3u")!)],
            servers: [.init(id: "server", name: "Server", accountID: "account")]
        )
        let authorization = try approvals.authorization(context: context, configuration: configuration)
        func card(_ id: String, sourceID: String, accountID: String? = nil) -> HomeLiveTVChannel {
            .init(
                route: .init(
                    profileID: profile.id, channelID: id, sourceID: sourceID, accountID: accountID,
                    sourceAuthorizationID: authorization.identity, serverAuthorizationID: "current"
                ), name: id, sourceName: sourceID, number: 1
            )
        }
        let playlist = card("iptv", sourceID: "playlist")
        let server = card("native", sourceID: "server", accountID: "account")
        let cached = HomeLiveTVSnapshot(recentChannels: [server, playlist], channels: [playlist, server])
        func visible(
            _ config: LiveTVSourcesConfiguration? = nil,
            profileID: String = "profile", serverID: String = "current",
            preferences: LiveTVPreferences = .init(recentChannelIDs: ["native", "iptv"])
        ) -> HomeLiveTVSnapshot {
            HomeLiveTVRuntime.visibleSnapshot(
                cached: cached, profileID: profileID, serverAuthorizationID: serverID,
                configuration: config ?? configuration, authorization: authorization, preferences: preferences
            )
        }
        XCTAssertEqual(visible().recentChannels.map(\.name), ["native", "iptv"])
        XCTAssertTrue(visible(profileID: "other").isEmpty)
        XCTAssertTrue(visible(serverID: "new-Plex-user-or-credential").isEmpty)
        XCTAssertTrue(visible(.empty).isEmpty)
        var disabled = configuration
        disabled.playlists[0].isEnabled = false
        disabled.servers[0].isEnabled = false
        XCTAssertTrue(visible(disabled).isEmpty)
        XCTAssertTrue(visible(preferences: .init(hiddenChannels: [
            .init(id: "native", name: "Native"), .init(id: "iptv", name: "IPTV")
        ])).isEmpty)
        var rebound = configuration
        rebound.servers[0].accountID = "different-user"
        XCTAssertEqual(visible(rebound).channels.map(\.name), ["iptv"])

        var kid = profile
        kid.isKids = true
        let denied = try approvals.authorization(
            context: .init(profile: kid, parentalPIN: nil, activeAccountIDs: ["account"]),
            configuration: configuration
        )
        XCTAssertTrue(HomeLiveTVRuntime.visibleSnapshot(
            cached: cached, profileID: profile.id, serverAuthorizationID: "current",
            configuration: configuration, authorization: denied, preferences: .empty
        ).isEmpty)
    }

    func testCurrentFavoriteAndRecentOrderUsesOnlyPublishedCards() throws {
        let suite = "HomeLiveTVOrdering-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = Profile(id: "profile", name: "Profile")
        let config = LiveTVSourcesConfiguration(servers: [.init(id: "source", name: "Server", accountID: "account")])
        let auth = try LiveTVSourceApprovalStore(defaults: defaults, profileID: profile.id).authorization(
            context: .init(profile: profile, parentalPIN: nil, activeAccountIDs: ["account"]), configuration: config
        )
        let cards = (1...8).map { number in
            HomeLiveTVChannel(
                route: .init(
                    profileID: profile.id, channelID: String(number), sourceID: "source", accountID: "account",
                    sourceAuthorizationID: auth.identity, serverAuthorizationID: "current"
                ), name: String(number), sourceName: "Server", number: number
            )
        }
        let visible = HomeLiveTVRuntime.visibleSnapshot(
            cached: .init(channels: cards), profileID: profile.id, serverAuthorizationID: "current",
            configuration: config, authorization: auth,
            preferences: .init(favoriteIDs: ["7", "3"], recentChannelIDs: ["8", "2"], favoriteOrder: ["7", "3"])
        )
        XCTAssertEqual(visible.recentChannels.map(\.name), ["8", "2"])
        XCTAssertEqual(visible.channels.prefix(4).map(\.name), ["7", "3", "8", "2"])
    }
}
