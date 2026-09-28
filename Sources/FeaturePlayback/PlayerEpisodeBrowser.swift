import CoreModels
import Foundation
import Observation

public struct PlayerEpisodeEntry: Identifiable, Sendable {
    public struct ID: Hashable, Sendable {
        public let seasonID: String?
        public let episodeID: String
    }

    public let item: MediaItem
    public let seasonID: String?
    public let seasonNumber: Int?

    public var id: ID { ID(seasonID: seasonID, episodeID: item.id) }

    public var badge: String? {
        guard let episode = item.episodeNumber else { return nil }
        if let season = item.seasonNumber ?? seasonNumber {
            return "S\(season) · E\(episode)"
        }
        return "E\(episode)"
    }
}

/// Browses episodes across seasons without fetching an entire long-running show.
/// The loaded range remains contiguous and expands only when its edges are seen.
@MainActor
@Observable
public final class PlayerEpisodeBrowser {
    public private(set) var seasons: [MediaItem] = []
    public private(set) var episodes: [PlayerEpisodeEntry] = []
    public private(set) var loadError: AppError?
    public private(set) var previousLoadError: AppError?
    public private(set) var nextLoadError: AppError?
    public private(set) var isLoading = false
    public private(set) var isLoadingPrevious = false
    public private(set) var isLoadingNext = false
    public private(set) var previousSeasonIndex: Int?
    public private(set) var nextSeasonIndex: Int?
    public private(set) var prependAnchorID: PlayerEpisodeEntry.ID?

    private let provider: any MediaProvider
    private let seriesID: String
    private let initialSeasonID: String?
    private let initialEpisodeID: String
    private let accountID: String?
    @ObservationIgnored private var didLoad = false

    public init(item: MediaItem, provider: any MediaProvider) {
        self.provider = provider
        seriesID = item.seriesID ?? ""
        initialSeasonID = item.seasonID
        initialEpisodeID = item.id
        accountID = item.sourceAccountID
    }

    public var initialEntryID: PlayerEpisodeEntry.ID? {
        episodes.first {
            $0.item.id == initialEpisodeID
                && (initialSeasonID == nil || $0.seasonID == initialSeasonID)
        }?.id
    }

    public func loadIfNeeded() async {
        guard !Task.isCancelled, !didLoad, !isLoading else { return }
        isLoading = true
        loadError = nil
        do {
            let all = try await provider.children(of: seriesID)
            try Task.checkCancellation()
            seasons = all.filter { $0.kind == .season }
            if seasons.isEmpty {
                episodes = all.filter { $0.kind == .episode }.map {
                    entry(for: $0, season: nil)
                }
            } else {
                let seed = seasons.firstIndex { $0.id == initialSeasonID } ?? 0
                previousSeasonIndex = seed > 0 ? seed - 1 : nil
                nextSeasonIndex = seed + 1 < seasons.count ? seed + 1 : nil
                episodes = try await entries(in: seed)
                try Task.checkCancellation()
                if episodes.isEmpty {
                    try await findFirstEpisodes()
                }
            }
            didLoad = true
            isLoading = false
        } catch where Self.isCancellation(error) {
            isLoading = false
        } catch {
            loadError = error as? AppError ?? .invalidResponse
            isLoading = false
        }
    }

    public func loadPrevious() async {
        guard !Task.isCancelled, didLoad, let start = previousSeasonIndex,
              !isLoadingPrevious, previousLoadError == nil else { return }
        isLoadingPrevious = true
        do {
            for index in stride(from: start, through: 0, by: -1) {
                let fetched = try await entries(in: index)
                try Task.checkCancellation()
                previousSeasonIndex = index > 0 ? index - 1 : nil
                if !fetched.isEmpty {
                    let anchor = episodes.first?.id
                    episodes.insert(contentsOf: fetched, at: 0)
                    prependAnchorID = anchor
                    break
                }
            }
            isLoadingPrevious = false
        } catch where Self.isCancellation(error) {
            isLoadingPrevious = false
        } catch {
            previousLoadError = error as? AppError ?? .invalidResponse
            isLoadingPrevious = false
        }
    }

    public func loadNext() async {
        guard !Task.isCancelled, didLoad, let start = nextSeasonIndex,
              !isLoadingNext, nextLoadError == nil else { return }
        isLoadingNext = true
        do {
            for index in start..<seasons.count {
                let fetched = try await entries(in: index)
                try Task.checkCancellation()
                nextSeasonIndex = index + 1 < seasons.count ? index + 1 : nil
                if !fetched.isEmpty {
                    episodes.append(contentsOf: fetched)
                    break
                }
            }
            isLoadingNext = false
        } catch where Self.isCancellation(error) {
            isLoadingNext = false
        } catch {
            nextLoadError = error as? AppError ?? .invalidResponse
            isLoadingNext = false
        }
    }

    public func retryPrevious() async {
        previousLoadError = nil
        await loadPrevious()
    }

    public func retryNext() async {
        nextLoadError = nil
        await loadNext()
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        Task.isCancelled || error is CancellationError || error as? AppError == .cancelled
            || (error as? URLError)?.code == .cancelled
    }

    private func findFirstEpisodes() async throws {
        while let index = nextSeasonIndex, episodes.isEmpty {
            episodes = try await entries(in: index)
            try Task.checkCancellation()
            nextSeasonIndex = index + 1 < seasons.count ? index + 1 : nil
        }
        while let index = previousSeasonIndex, episodes.isEmpty {
            episodes = try await entries(in: index)
            try Task.checkCancellation()
            previousSeasonIndex = index > 0 ? index - 1 : nil
        }
    }

    private func entries(in index: Int) async throws -> [PlayerEpisodeEntry] {
        let season = seasons[index]
        let members = try await provider.children(of: season.id)
        try Task.checkCancellation()
        return members.filter { $0.kind == .episode }.map {
            entry(for: $0, season: season)
        }
    }

    private func entry(for item: MediaItem, season: MediaItem?) -> PlayerEpisodeEntry {
        PlayerEpisodeEntry(
            item: accountID.map { item.taggingSource($0) } ?? item,
            seasonID: season?.id,
            seasonNumber: season?.seasonNumber
        )
    }
}
