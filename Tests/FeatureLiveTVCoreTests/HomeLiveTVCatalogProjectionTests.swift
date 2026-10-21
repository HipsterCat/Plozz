import CoreModels
import XCTest
@testable import FeatureLiveTVCore

@MainActor
final class HomeLiveTVCatalogProjectionTests: XCTestCase {
    func testPublishedIPTVCardsNeedNoPlaylistGuideOrNetworkRead() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let loader = HomeNoLoadSource()
        let source = LiveTVPlaylistSource(
            id: "playlist", name: "Playlist", playlistURL: URL(string: "https://example.test/list.m3u")!
        )
        let config = LiveTVSourcesConfiguration(playlists: [source])
        let auth = try fixture.authorization(config)
        let channels = (0..<5_000).map { index in
            LiveTVPrototypeChannel(
                id: "channel-\(index)", number: index, name: "Channel \(index)",
                category: "TV", symbol: "tv", accent: 0, source: .iptv, tagline: "",
                logoURL: URL(string: "https://example.test/logo?token=artwork-credential"),
                streamURL: URL(string: "https://example.test/stream?password=must-not-reach-home"),
                configuredSourceID: source.id
            )
        }
        let model = LiveTVPrototypeModel(channels: channels, preferencesStore: HomePreferences(
            value: .init(favoriteIDs: ["channel-4000"], recentChannelIDs: ["channel-4500"])
        ))
        let imports = LiveTVPrototypeImportModel(configuration: config, loader: loader)
        var resolverCalls = 0
        func snapshot() -> HomeLiveTVSnapshot {
            HomeLiveTVCatalogProjection.snapshot(
                model: model, imports: imports, profileID: fixture.profile.id, authorization: auth,
                serverAuthorizationID: "current",
                serverProvider: { _ in resolverCalls += 1; return nil }
            )
        }
        let result = snapshot()
        XCTAssertEqual(result.recentChannels.map(\.name), ["Channel 4500"])
        XCTAssertEqual(result.channels.first?.name, "Channel 4000")
        XCTAssertEqual(result.channels.count, 8)
        for _ in 0..<100 { XCTAssertEqual(snapshot(), result) }
        XCTAssertEqual(resolverCalls, 0)
        let reads = await loader.reads
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(imports.playlistPhase, .idle)
        XCTAssertEqual(model.recentChannelIDs, ["channel-4500"], "Home does not record viewing.")
        XCTAssertEqual(result.channels.first?.logoURL, channels[4_000].logoURL)
        let encoded = try JSONEncoder().encode(result.channels)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("streamURL"))

        let route = try XCTUnwrap(result.channels.first?.route)
        XCTAssertTrue(HomeLiveTVCatalogProjection.accepts(
            route, model: model, imports: imports, profileID: fixture.profile.id,
            authorization: auth, serverAuthorizationID: "current", serverProvider: { _ in nil }
        ))
        model.setScanHiddenChannelIDs([route.channelID])
        XCTAssertFalse(HomeLiveTVCatalogProjection.accepts(
            route, model: model, imports: imports, profileID: fixture.profile.id,
            authorization: auth, serverAuthorizationID: "current", serverProvider: { _ in nil }
        ))
        XCTAssertFalse(snapshot().channels.contains { $0.route == route })
    }

    func testServerBackedIPTVUsesAuthorizedReferencesWithoutOpeningATuner() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let provider = HomeServerProvider()
        let source = LiveTVServerSource(id: "server-iptv", name: "IPTV account", accountID: "account")
        let config = LiveTVSourcesConfiguration(servers: [source])
        let auth = try fixture.authorization(config)
        let context = LiveTVAuthorizedServerProvider(
            accountID: source.accountID, authorizationID: "provider-auth", kind: .iptv, provider: provider
        )
        let imports = LiveTVPrototypeImportModel(
            configuration: config, loader: HomeNoLoadSource(), serverProviderResolver: { _ in context }
        )
        let model = LiveTVPrototypeModel(channels: [])
        // Normal Live TV usage populates its authorized server catalog.
        await imports.reload(into: model)
        let before = await provider.calls
        let snapshot = HomeLiveTVCatalogProjection.snapshot(
            model: model, imports: imports, profileID: fixture.profile.id, authorization: auth,
            serverAuthorizationID: "servers", serverProvider: { _ in context }
        )
        let card = try XCTUnwrap(snapshot.channels.first)
        XCTAssertEqual(card.name, "Channel")
        XCTAssertEqual(card.route.accountID, source.accountID)
        XCTAssertTrue(HomeLiveTVCatalogProjection.accepts(
            card.route, model: model, imports: imports, profileID: fixture.profile.id,
            authorization: auth, serverAuthorizationID: "servers", serverProvider: { _ in context }
        ))
        XCTAssertFalse(HomeLiveTVCatalogProjection.accepts(
            card.route, model: model, imports: imports, profileID: "other-profile",
            authorization: auth, serverAuthorizationID: "servers", serverProvider: { _ in context }
        ))
        XCTAssertFalse(HomeLiveTVCatalogProjection.accepts(
            card.route, model: model, imports: imports, profileID: fixture.profile.id,
            authorization: auth, serverAuthorizationID: "servers", serverProvider: { _ in nil }
        ))
        XCTAssertFalse(HomeLiveTVCatalogProjection.accepts(
            card.route, model: model, imports: imports, profileID: fixture.profile.id,
            authorization: auth, serverAuthorizationID: "rotated", serverProvider: { _ in context }
        ))
        let after = await provider.calls
        XCTAssertEqual(before, after)
        let opens = await provider.opens
        XCTAssertEqual(opens, 0, "Even validating a press must not directly open a tuner.")
        XCTAssertTrue(model.recentChannelIDs.isEmpty)
    }
}

private struct Fixture {
    let suite = "HomeLiveTVProjection-\(UUID().uuidString)"
    let defaults: UserDefaults
    let profile = Profile(id: "profile", name: "Profile")
    init() throws { defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) }
    func authorization(_ config: LiveTVSourcesConfiguration) throws -> LiveTVSourceAuthorization {
        try LiveTVSourceApprovalStore(defaults: defaults, profileID: profile.id).authorization(
            context: .init(profile: profile, parentalPIN: nil, activeAccountIDs: ["account"]),
            configuration: config
        )
    }
    func clean() { defaults.removePersistentDomain(forName: suite) }
}

private struct HomePreferences: LiveTVPreferencesStoring {
    let value: LiveTVPreferences
    func load() throws -> LiveTVPreferences { value }
    func save(_ preferences: LiveTVPreferences) throws {}
}

private actor HomeNoLoadSource: LiveTVSourceLoading {
    private(set) var reads = 0
    func loadPlaylist(from url: URL) async throws -> LiveTVPlaylistImport {
        reads += 1
        throw CancellationError()
    }
    func loadGuide(from url: URL, channels: [LiveTVPrototypeChannel], now: Date) async throws -> LiveTVGuideImport {
        reads += 1
        throw CancellationError()
    }
}

private actor HomeServerProvider: ServerLiveTVProviding {
    private(set) var calls = 0
    private(set) var opens = 0
    func liveTVAvailability() async throws -> ServerLiveTVAvailability {
        calls += 1
        return .init(status: .available, channelCount: 1)
    }
    func liveTVChannels() async throws -> [ServerLiveTVChannel] {
        calls += 1
        return [.init(id: "native", name: "Channel")]
    }
    func liveTVGuide(channelIDs: [String], from: Date, to: Date) async throws -> [ServerLiveTVProgramme] {
        calls += 1
        return []
    }
    func openLiveTVChannel(id: String) async throws -> any LiveTVStreamLease {
        calls += 1
        opens += 1
        throw ServerLiveTVError.unsupportedPlaybackMode
    }
}
