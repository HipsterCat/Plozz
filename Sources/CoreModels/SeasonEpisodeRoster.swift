import Foundation

/// Canonical episode metadata, never a playable or downloadable library item.
public struct SeasonEpisodeMetadata: Equatable, Sendable {
    public let id: Int
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let title: String?
    public let airDate: Date?
    public let stillURL: URL?

    public init(
        id: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        title: String? = nil,
        airDate: Date? = nil,
        stillURL: URL? = nil
    ) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.airDate = airDate
        self.stillURL = stillURL
    }
}

/// A complete metadata response for one season, not a capped upcoming schedule.
public struct SeasonEpisodeRoster: Equatable, Sendable {
    public let seriesTMDbID: Int
    public let seasonNumber: Int
    public let episodes: [SeasonEpisodeMetadata]

    public init(seriesTMDbID: Int, seasonNumber: Int, episodes: [SeasonEpisodeMetadata]) {
        self.seriesTMDbID = seriesTMDbID
        self.seasonNumber = seasonNumber
        self.episodes = episodes
    }
}

public enum SeasonEpisodeRosterResult: Equatable, Sendable {
    case loaded(SeasonEpisodeRoster)
    case unavailable
    case failed
}

public enum SeasonEpisodeRosterLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded(SeasonEpisodeRoster)
    case unavailable
    case failed

    public var roster: SeasonEpisodeRoster? {
        guard case .loaded(let roster) = self else { return nil }
        return roster
    }
}
