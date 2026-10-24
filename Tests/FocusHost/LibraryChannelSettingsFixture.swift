import CoreModels
import CoreSecureStore
import PlozzCoreUI
import FeatureLiveTV
import FeatureLiveTVCore
import SwiftUI

struct LibraryChannelSettingsFixture: View {
    @State private var fixture: Fixture?
    @State private var issue: String?
    @State private var enabled = true
    @State private var navigation = SettingsPageNavigation<String>()

    var body: some View {
        Group {
            if let fixture {
                SettingsPageStack(navigation: navigation, pageWidth: 960, onRootBack: {}) {
                    LibraryChannelManagementView(
                        service: fixture.service, history: fixture.history,
                        automaticChannels: .init(
                            enabled: enabled, isWorking: false, issue: nil,
                            channelCount: fixture.service.channels.count, skippedItemCount: 0,
                            setEnabled: { enabled = $0 }, retry: {}
                        )
                    )
                } destination: { _ in EmptyView() }
                .environment(fixture.profiles)
                .environment(\.settingsInWorkspace, true)
            } else if let issue {
                Text(verbatim: issue).accessibilityIdentifier("channel-settings-fixture-error")
            } else {
                ProgressView()
            }
        }
        .environment(\.themePalette, .dark)
        .environment(\.colorScheme, .dark)
        .background { SettingsPageBackground() }
        .task {
            guard fixture == nil else { return }
            do {
                let prepared = Fixture()
                try await prepared.service.load()
                _ = try await prepared.service.refreshAutomaticChannels()
                fixture = prepared
            } catch {
                issue = String(describing: error)
            }
        }
    }

    @MainActor
    private final class Fixture {
        let profiles: ProfilesModel
        let service: LibraryChannelService
        let history: LibraryChannelHistorySettings

        init() {
            let namespace = "ChannelSettings.\(UUID())"
            let defaults = UserDefaults(suiteName: namespace)!
            profiles = ProfilesModel(store: ProfileStore(defaults: defaults))
            profiles.select(profiles.add(name: "Channel settings").id)
            history = LibraryChannelHistorySettings(defaults: defaults, namespace: namespace)
            service = LibraryChannelService(
                profileID: profiles.activeProfileID,
                store: LibraryChannelDefinitionStore(secureStore: InMemorySecureStore(), namespace: namespace),
                snapshotStore: LibraryChannelSnapshotStore(databaseURL: nil)
            )
            service.setContexts([ProviderKind.jellyfin, .plex].map { kind in
                .init(
                    accountID: kind.rawValue, authorizationID: "fixture",
                    provider: ChannelSettingsProvider(kind: kind), allowedLibraryIDs: ["movies"]
                )
            })
        }
    }
}

private struct ChannelSettingsProvider: LibraryChannelCatalogProviding {
    let kind: ProviderKind
    var session: UserSession {
        .init(
            server: .init(id: kind.rawValue, name: "\(kind.rawValue.capitalized) fixture",
                          baseURL: URL(string: "https://fixture.invalid")!, provider: kind),
            userID: "fixture", userName: "Fixture", deviceID: "fixture", accessToken: "fixture"
        )
    }

    func libraries() async throws -> [MediaLibrary] {
        [.init(id: "movies", title: "Movies", kind: .movie)]
    }

    func libraryChannelItems(in libraryID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        let genres = [
            "Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary",
            "Drama", "Family", "Fantasy", "Mystery", "Romance", "Science Fiction"
        ]
        let items: [MediaItem] = kind == .movie ? (0..<(genres.count * 4)).map { index in
            var item = MediaItem(id: "movie-\(index)", title: "Movie \(index)", kind: .movie, runtime: 3_600)
            item.libraryID = libraryID
            item.genres = [genres[index / 4]]
            return item
        } : []
        return MediaPage(items: items, startIndex: page.startIndex, totalCount: items.count)
    }

    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        throw AppError.notFound
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
