import CoreModels
import CoreUI
import SwiftUI
import UIKit
@testable import FeaturePlayback

struct EpisodeRowRemoteFixture: View {
    @State private var player: PlayerViewModel
    @State private var focusTrace: [Int] = []
    @State private var peakCellCount = 0
    @FocusState private var focus: PlayerControls.FocusSlot?

    init() {
        let long = ProcessInfo.processInfo.arguments.contains("--long-season")
        let single = long || ProcessInfo.processInfo.arguments.contains("--single-season")
        let provider = EpisodeRemoteProvider(singleSeason: single, episodeCount: long ? 1000 : 24)
        let episode = EpisodeRemoteProvider.episode(season: single ? 1 : 2, number: long ? 500 : (single ? 1 : 12))
        _player = State(initialValue: PlayerViewModel(
            provider: provider, itemID: episode.id, episodeItem: episode
        ))
    }

    var body: some View {
        VStack(spacing: 40) {
            Button("Browse episodes") {}
                .focused($focus, equals: .button(.episodes))
                .frame(maxWidth: .infinity)
                .focusSection()
            PlayerSequencePanel(player: player, source: .episodes, focus: $focus)
                .frame(width: 1400)
            Text(verbatim: player.episodeBrowser?.hasLoaded == true ? "Ready" : "Loading")
                .accessibilityIdentifier("episode-row-ready")
            Text(verbatim: String(player.episodeBrowser?.episodes.count ?? 0))
                .accessibilityIdentifier("episode-row-count")
            Text(verbatim: focusTrace.map(String.init).joined(separator: ","))
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 1000, height: 25)
                .accessibilityIdentifier("episode-row-trace")
            Text(verbatim: String(peakCellCount))
                .accessibilityIdentifier("episode-row-peak-cells")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .environment(\.plozzCardFocusStyle, .system)
        .environment(\.layoutDirection, ProcessInfo.processInfo.arguments.contains("--rtl") ? .rightToLeft : .leftToRight)
        .onAppear { focus = .button(.episodes) }
        .onReceive(NotificationCenter.default.publisher(for: UIFocusSystem.didUpdateNotification)) { notification in
            guard let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
                  let cell = context.nextFocusedView as? PlayerEpisodeNativeCell,
                  let title = cell.accessibilityLabel, title.hasPrefix("Episode "),
                  let episode = Int(title.dropFirst("Episode ".count)) else { return }
            if focusTrace.last != episode { focusTrace.append(episode) }
        }
        .task {
            await prepareArtwork()
            while !Task.isCancelled {
                let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
                peakCellCount = max(peakCellCount, windows.map(countCells).max() ?? 0)
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }

    private func countCells(in view: UIView) -> Int {
        (view is PlayerEpisodeNativeCell ? 1 : 0) + view.subviews.map(countCells).reduce(0, +)
    }

    @MainActor
    private func prepareArtwork() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image {
            UIColor.systemBlue.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            UIColor.systemOrange.setFill()
            $0.fill(CGRect(x: 25, y: 20, width: 75, height: 140))
        }
        let url = ArtworkImageVariant.landscapeCard.requestURL(for: EpisodeRemoteProvider.artworkURL)
        guard let cache = ArtworkSession.shared.configuration.urlCache, let data = image.pngData(),
              let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "image/png", "Cache-Control": "max-age=3600"]
              ) else { preconditionFailure("Episode fixture requires its isolated artwork cache") }
        cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: URLRequest(url: url))
        guard await ArtworkImageCache.shared.image(
            for: EpisodeRemoteProvider.artworkURL, variant: .landscapeCard
        ) != nil else { preconditionFailure("Episode fixture artwork must decode") }
    }
}

private actor EpisodeRemoteProvider: MediaProvider {
    nonisolated static let artworkURL = URL(string: "https://episode-row-fixture.example.test/artwork.png")!
    nonisolated let kind = ProviderKind.jellyfin
    nonisolated let session = UserSession(
        server: MediaServer(id: "fixture", name: "Fixture", baseURL: URL(string: "https://fixture.test")!, provider: .jellyfin),
        userID: "viewer", userName: "Viewer", deviceID: "fixture", accessToken: "fixture"
    )
    let singleSeason: Bool
    let episodeCount: Int
    init(singleSeason: Bool, episodeCount: Int) {
        self.singleSeason = singleSeason
        self.episodeCount = episodeCount
    }

    nonisolated static func episode(season: Int, number: Int) -> MediaItem {
        MediaItem(
            id: "\(season)-\(number)", title: "Episode \((season - 1) * 24 + number)", kind: .episode,
            seasonNumber: season, episodeNumber: number, seriesID: "series", seasonID: "season-\(season)",
            posterURL: artworkURL, backdropURL: artworkURL
        )
    }

    func children(of itemID: String) async throws -> [MediaItem] {
        try await Task.sleep(for: .milliseconds(180))
        if itemID == "series" {
            return (1...(singleSeason ? 1 : 3)).map { (number: Int) in
                MediaItem(id: "season-\(number)", title: "Season \(number)", kind: .season, seasonNumber: number)
            }
        }
        guard let season = Int(itemID.replacingOccurrences(of: "season-", with: "")) else {
            throw AppError.notFound
        }
        return (1...episodeCount).map { Self.episode(season: season, number: $0) }
    }
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: page.startIndex, totalCount: 0)
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    nonisolated func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
