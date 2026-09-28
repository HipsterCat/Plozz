import CoreModels
import Foundation
import Observation

/// Discovers seasons once, then loads just the selected season's episodes.
/// Switching seasons never enumerates an entire series at player startup.
@MainActor
@Observable
public final class PlayerEpisodeBrowser {
    public private(set) var seasons: [MediaItem] = []
    public private(set) var selectedSeasonID: String?
    public private(set) var episodes: [MediaItem] = []
    public private(set) var loadError: AppError?
    public private(set) var isLoading = false

    private let provider: any MediaProvider
    private let seriesID: String
    private let initialSeasonID: String?
    private let accountID: String?
    @ObservationIgnored private var seasonCache: [String: [MediaItem]] = [:]
    @ObservationIgnored private var generation = 0

    public init(item: MediaItem, provider: any MediaProvider) {
        self.provider = provider
        seriesID = item.seriesID ?? ""
        initialSeasonID = item.seasonID
        accountID = item.sourceAccountID
    }

    public func loadIfNeeded() async {
        guard seasons.isEmpty, selectedSeasonID == nil, !isLoading else { return }
        isLoading = true
        do {
            let all = try await provider.children(of: seriesID)
            try Task.checkCancellation()
            seasons = all.filter { $0.kind == .season }
            let selected = seasons.first(where: { $0.id == initialSeasonID })?.id
                ?? initialSeasonID ?? seasons.first?.id
            isLoading = false
            if let selected { await selectSeason(selected) }
        } catch is CancellationError {
            isLoading = false
        } catch {
            loadError = error as? AppError ?? .invalidResponse
            isLoading = false
        }
    }

    public func selectSeason(_ id: String) async {
        generation &+= 1
        let expected = generation
        selectedSeasonID = id
        loadError = nil
        if let cached = seasonCache[id] {
            episodes = cached
            return
        }
        episodes = []
        isLoading = true
        do {
            let members = try await provider.children(of: id)
            try Task.checkCancellation()
            guard generation == expected else { return }
            let tagged = members.filter { $0.kind == .episode }.map { item in
                accountID.map { item.taggingSource($0) } ?? item
            }
            seasonCache[id] = tagged
            episodes = tagged
            isLoading = false
        } catch is CancellationError {
            if generation == expected { isLoading = false }
        } catch {
            guard generation == expected else { return }
            loadError = error as? AppError ?? .invalidResponse
            isLoading = false
        }
    }
}
