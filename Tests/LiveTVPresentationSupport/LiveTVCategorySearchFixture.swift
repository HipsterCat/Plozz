import CoreModels
import PlozzCoreUI
import FeatureLiveTV
import FeatureLiveTVCore
import FeatureProfiles
import SwiftUI

struct LiveTVCategorySearchFixture: View {
    @State private var profiles: ProfilesModel
    @State private var showsProfile = false
    private let namespace = "CategorySearch.\(UUID().uuidString)"

    init() {
        let defaults = UserDefaults(suiteName: "CategorySearchProfiles.\(UUID().uuidString)")!
        _profiles = State(initialValue: ProfilesModel(store: ProfileStore(defaults: defaults)))
    }

    var body: some View {
        NavigationStack {
            LiveTVPrototypeView(
                preferencesStore: CategorySearchPreferences(),
                viewSettingsStore: CategorySearchSettings(),
                sourceStore: CategorySearchSources(),
                sourceLoader: CategorySearchLoader(),
                preferencesNamespace: namespace,
                sourceApprovalContext: { [profiles] in LiveTVSourceApprovalContext(profiles: profiles) },
                topBarAccessory: profileAction
            ) { playback in
                Color.black
                    .accessibilityIdentifier("category-search-playback")
                    .accessibilityLabel(Text(playback.channel.name))
                    .accessibilityValue(Text(verbatim: playback.isExpanded ? "Fullscreen" : "Preview"))
            }
        }
        .environment(profiles)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.themePalette, .dark)
        .environment(\.colorScheme, .dark)
        .background { AppBackground(palette: .dark) }
        #if os(iOS)
        .environment(\.plozzMetrics, .touch(density: .standard))
        .sheet(isPresented: $showsProfile) {
            Text("Profile settings").accessibilityIdentifier("category-search-profile-settings")
        }
        #endif
    }

    private var profileAction: AnyView? {
        #if os(iOS)
        AnyView(
            Button { showsProfile = true } label: {
                ProfileAvatarView(profile: profiles.activeProfile, size: 36, rendersAsImage: true)
            }
            .buttonBorderShape(.circle)
            .accessibilityLabel("Profile settings")
            .accessibilityIdentifier("live-tv-profile")
        )
        #else
        nil
        #endif
    }
}

private final class CategorySearchPreferences: LiveTVPreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var preferences = LiveTVPreferences()

    func load() throws -> LiveTVPreferences { lock.withLock { preferences } }
    func save(_ preferences: LiveTVPreferences) throws { lock.withLock { self.preferences = preferences } }
}

private struct CategorySearchSettings: LiveTVViewSettingsStoring {
    func load() -> LiveTVViewSettings {
        .init(autoPreview: false, hasChosenAutoPreview: true,
              startsWithCategories: !ProcessInfo.processInfo.arguments.contains("--category-search-guide-first"))
    }
    func save(_ settings: LiveTVViewSettings) {}
}

private struct CategorySearchSources: LiveTVSourcesStoring {
    func load() throws -> LiveTVSourcesConfiguration {
        .init(playlists: [
            .init(id: "category-search", name: "Sample TV",
                  playlistURL: URL(string: "https://fixture.invalid/channels.m3u")!,
                  guideURLs: [URL(string: "https://fixture.invalid/guide.xml")!])
        ])
    }

    func save(_ configuration: LiveTVSourcesConfiguration) throws {}
}

private struct CategorySearchLoader: LiveTVSourceLoading {
    func loadPlaylist(from url: URL) async throws -> LiveTVPlaylistImport {
        if ProcessInfo.processInfo.arguments.contains("--category-search-failure") {
            throw URLError(.cannotConnectToHost)
        }
        return try LiveTVPlaylistParser(baseURL: url).parse("""
        #EXTM3U
        #EXTINF:-1 tvg-id="arena" group-title="Sports",Arena One
        https://fixture.invalid/arena.m3u8
        #EXTINF:-1 tvg-id="stadium" group-title="Sports",Stadium Live
        https://fixture.invalid/stadium.m3u8
        #EXTINF:-1 tvg-id="world" group-title="International Sports",World Arena
        https://fixture.invalid/world.m3u8
        #EXTINF:-1 tvg-id="report" group-title="Entertainment",Sports Report
        https://fixture.invalid/report.m3u8
        #EXTINF:-1 tvg-id="news" group-title="News",Daily News
        https://fixture.invalid/news.m3u8
        """)
    }

    func loadGuide(
        from url: URL, channels: [LiveTVPrototypeChannel], now: Date
    ) async throws -> LiveTVGuideImport {
        let start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 1_800) * 1_800)
        let titles = ["Matchday Live", "Championship Highlights", "World Sports", "The Sports Review", "News Today"]
        let programs = channels.enumerated().flatMap { index, channel in
            (0..<4).map { slot in
                LiveTVPrototypeProgram(
                    id: "\(channel.id)-\(slot)", channelID: channel.id,
                    title: slot.isMultiple(of: 2) ? titles[index % titles.count] : "Weekend Highlights",
                    subtitle: "", start: start.addingTimeInterval(Double(slot) * 1_800),
                    end: start.addingTimeInterval(Double(slot + 1) * 1_800)
                )
            }
        }
        return .init(
            programs: programs, matchedChannelCount: channels.count,
            guideChannelCount: channels.count, programCount: programs.count,
            coverageStart: start, coverageEnd: start.addingTimeInterval(7_200)
        )
    }
}
