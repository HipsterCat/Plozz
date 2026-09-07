import Foundation

public enum SeasonEpisodeAvailability: Equatable, Sendable {
    case inLibrary
    case missing
    case unaired
    case airingToday
    case recentlyReleased
    case releaseDateUnknown

    public var title: LocalizedStringResource {
        switch self {
        case .inLibrary: "In Library"
        case .missing: "Missing from Library"
        case .unaired: "Not Yet Released"
        case .airingToday: "Releases Today"
        case .recentlyReleased: "Recently Released"
        case .releaseDateUnknown: "Release Date Unknown"
        }
    }

    public var systemImage: String {
        switch self {
        case .inLibrary: "play.rectangle"
        case .missing: "minus.circle"
        case .unaired, .airingToday, .recentlyReleased: "calendar"
        case .releaseDateUnknown: "questionmark.circle"
        }
    }

    public static func scheduled(
        airDate: Date?,
        hasTime: Bool = false,
        calendarDayStoredInUTC: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Self {
        guard let airDate else { return .releaseDateUnknown }
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = calendar.timeZone
        let localDate: Date
        if !hasTime && calendarDayStoredInUTC {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = .gmt
            guard let date = localCalendar.date(from: utc.dateComponents([.year, .month, .day], from: airDate))
            else { return .releaseDateUnknown }
            localDate = date
        } else {
            localDate = airDate
        }
        if now < localDate { return .unaired }
        let threshold = EpisodeGraceConfig(calendar: localCalendar).missingThreshold(
            airDate: localDate, datePrecision: hasTime ? .dateAndTime : .dateOnly
        )
        return now < threshold ? (hasTime ? .recentlyReleased : .airingToday) : .missing
    }
}

public struct SeasonEpisodeRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let metadata: SeasonEpisodeMetadata?
    public let libraryEpisodes: [MediaItem]
    public let availability: SeasonEpisodeAvailability

    public var episodeNumber: Int? {
        metadata?.episodeNumber ?? libraryEpisodes.first?.episodeNumber
    }
}

public struct SeasonEpisodeCoverage: Equatable, Sendable {
    public let inLibrary: Int
    public let total: Int
    public let missing: Int
    public let unaired: Int

    public var hasUnavailableEpisodes: Bool { inLibrary < total }

    public var title: LocalizedStringResource {
        "\(inLibrary) of \(total) episodes in library"
    }
}

/// Matches an authoritative roster to one source's real library entries. A
/// numbering conflict falls back to the library list instead of inventing gaps.
public struct SeasonEpisodeList: Equatable, Sendable {
    public let rows: [SeasonEpisodeRow]
    public let coverage: SeasonEpisodeCoverage?
    public let hasNumberingConflict: Bool

    public static func downloadableEpisodes(from episodes: [MediaItem], for series: MediaItem) -> [MediaItem] {
        var seen = Set<String>()
        return EpisodeSequence.sorted(episodes.filter {
            $0.kind == .episode
                && $0.scheduledAirDate == nil
                && $0.locallyValidatedPlayableSource
                && (series.sourceAccountID == nil || $0.sourceAccountID == series.sourceAccountID)
                && ($0.seriesID == nil || $0.seriesID == series.id)
                && seen.insert($0.stablePresentationID).inserted
        })
    }

    public init(
        series: MediaItem,
        seasonNumber: Int?,
        libraryEpisodes: [MediaItem],
        roster: SeasonEpisodeRoster?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let library = Self.downloadableEpisodes(from: libraryEpisodes, for: series)
        let fallback = library.map {
            SeasonEpisodeRow(
                id: "library:\($0.stablePresentationID)",
                metadata: nil,
                libraryEpisodes: [$0],
                availability: .inLibrary
            )
        }
        guard let roster, !roster.episodes.isEmpty,
              roster.seriesTMDbID > 0,
              let seasonNumber,
              roster.seasonNumber == seasonNumber,
              series.providerID(.tmdb).flatMap(Int.init) == roster.seriesTMDbID
        else {
            rows = fallback
            coverage = nil
            hasNumberingConflict = false
            return
        }

        var byID: [Int: SeasonEpisodeMetadata] = [:]
        var byNumber: [Int: Int] = [:]
        var conflict = false
        for episode in roster.episodes {
            guard episode.id > 0, episode.episodeNumber > 0, episode.seasonNumber == seasonNumber,
                  byID[episode.id] == nil || byID[episode.id] == episode,
                  byNumber[episode.episodeNumber] == nil || byNumber[episode.episodeNumber] == episode.id
            else {
                conflict = true
                continue
            }
            byID[episode.id] = episode
            byNumber[episode.episodeNumber] = episode.id
        }
        var matched: [Int: [MediaItem]] = [:]
        for episode in library {
            let metadataID: Int?
            if let rawID = episode.providerID(.tmdb), let externalID = Int(rawID), externalID > 0 {
                metadataID = byID[externalID]?.id
            } else if episode.seasonNumber == seasonNumber, let number = episode.episodeNumber {
                metadataID = byNumber[number]
            } else {
                metadataID = nil
            }
            guard let metadataID, let metadata = byID[metadataID],
                  episode.seasonNumber == nil || episode.seasonNumber == metadata.seasonNumber,
                  episode.episodeNumber == nil || episode.episodeNumber == metadata.episodeNumber
            else {
                conflict = true
                continue
            }
            if let end = episode.episodeNumberEnd {
                guard let start = episode.episodeNumber, end >= start,
                      byNumber[end] != nil else {
                    conflict = true
                    continue
                }
                // Only an explicit server range can cover multiple episodes.
                // Iterate actual metadata entries, never synthesize numeric gaps.
                for (number, id) in byNumber where number >= start && number <= end {
                    matched[id, default: []].append(episode)
                }
            } else {
                matched[metadataID, default: []].append(episode)
            }
        }
        guard !conflict else {
            rows = fallback
            coverage = nil
            hasNumberingConflict = true
            return
        }

        let merged = byID.values.sorted { $0.episodeNumber < $1.episodeNumber }.map { metadata in
            let owned = matched[metadata.id] ?? []
            return SeasonEpisodeRow(
                id: "metadata:\(roster.seriesTMDbID):\(seasonNumber):\(metadata.id)",
                metadata: metadata,
                libraryEpisodes: owned,
                availability: owned.isEmpty
                    ? .scheduled(airDate: metadata.airDate, now: now, calendar: calendar)
                    : .inLibrary
            )
        }
        rows = merged
        coverage = SeasonEpisodeCoverage(
            inLibrary: merged.filter { !$0.libraryEpisodes.isEmpty }.count,
            total: merged.count,
            missing: merged.filter { $0.availability == .missing }.count,
            unaired: merged.filter { $0.availability == .unaired }.count
        )
        hasNumberingConflict = false
    }
}
