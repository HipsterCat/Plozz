import Foundation

/// A single season identity, with independent library content and request state.
public struct SeriesDownloadSeason: Identifiable, Equatable, Sendable {
    public let id: String
    public let number: Int?
    public fileprivate(set) var librarySeasons: [MediaItem] = []
    public fileprivate(set) var looseEpisodes: [MediaItem] = []
    public fileprivate(set) var requestState: MediaSeasonRequestState?

    public var hasLibraryContent: Bool {
        !librarySeasons.isEmpty || !looseEpisodes.isEmpty
    }

    public var canRequest: Bool {
        !hasLibraryContent && requestState?.isRequestable == true
    }

    public var title: LocalizedStringResource {
        if let title = librarySeasons.first?.title ?? requestState?.title {
            return "\(title)"
        }
        if number == 0 { return "Specials" }
        if let number { return "Season \(number)" }
        return "Season"
    }

    public var statusTitle: LocalizedStringResource {
        if canRequest { return "Missing" }
        guard let requestState else { return "In Library" }
        if requestState.status == .available {
            return hasLibraryContent ? "In Library" : "Available on Server"
        }
        if requestState.status == .partiallyAvailable {
            switch requestState.effectiveRequestStatus {
            case .pending:
                return hasLibraryContent
                    ? "Partially in Library · Requested"
                    : "Partially Available on Server · Requested"
            case .processing:
                return hasLibraryContent
                    ? "Partially in Library · Processing"
                    : "Partially Available on Server · Processing"
            case .failed:
                return hasLibraryContent
                    ? "Partially in Library · Request Failed"
                    : "Partially Available on Server · Request Failed"
            case .declined:
                return hasLibraryContent
                    ? "Partially in Library · Request Declined"
                    : "Partially Available on Server · Request Declined"
            case .completed, nil:
                return hasLibraryContent ? "Partially in Library" : "Partially Available on Server"
            }
        }
        return requestState.statusTitle
    }

    public var statusSystemImage: String {
        requestState?.statusSystemImage ?? "play.rectangle"
    }
}

/// Joins by season number, not by provider-local IDs or translated season names.
/// Unnumbered library entries remain distinct rather than being guessed away.
public struct SeriesDownloadSeasons: Equatable, Sendable {
    public let rows: [SeriesDownloadSeason]
    public let unassignedEpisodes: [MediaItem]
    public let requestAvailability: MediaRequestAvailability?

    public var requestableSeasonNumbers: [Int] {
        rows.filter(\.canRequest).compactMap(\.number)
    }

    public init(
        librarySeasons: [MediaItem],
        looseEpisodes: [MediaItem],
        requestAvailability: MediaRequestAvailability?
    ) {
        var byID: [String: SeriesDownloadSeason] = [:]
        var seenLibraryIDs = Set<String>()
        for season in librarySeasons where season.kind == .season {
            guard seenLibraryIDs.insert(season.stablePresentationID).inserted else { continue }
            let number = season.seasonNumber.flatMap { $0 >= 0 ? $0 : nil }
            let id = number.map { "season:\($0)" } ?? "library:\(season.stablePresentationID)"
            var row = byID[id] ?? SeriesDownloadSeason(id: id, number: number)
            row.librarySeasons.append(season)
            byID[id] = row
        }

        var unassigned: [MediaItem] = []
        var seenEpisodeIDs = Set<String>()
        for episode in looseEpisodes where episode.kind == .episode {
            guard seenEpisodeIDs.insert(episode.stablePresentationID).inserted else { continue }
            guard let number = episode.seasonNumber, number >= 0 else {
                unassigned.append(episode)
                continue
            }
            let id = "season:\(number)"
            var row = byID[id] ?? SeriesDownloadSeason(id: id, number: number)
            row.looseEpisodes.append(episode)
            byID[id] = row
        }

        var normalized = requestAvailability?.markingPresentInLibrary(
            byID.values.compactMap(\.number)
        )
        for state in normalized?.canonicalNumberedSeasons ?? [] {
            let id = "season:\(state.number)"
            var row = byID[id] ?? SeriesDownloadSeason(id: id, number: state.number)
            var displayState = state
            if row.hasLibraryContent,
               state.status == .pending || state.status == .processing {
                displayState.requestStatus = state.effectiveRequestStatus
                displayState.status = .partiallyAvailable
            }
            row.requestState = displayState
            byID[id] = row
        }

        rows = byID.values.sorted {
            let left = $0.number ?? Int.max
            let right = $1.number ?? Int.max
            return left == right ? $0.id < $1.id : left < right
        }
        normalized?.seasons = rows.compactMap(\.requestState)
        self.requestAvailability = normalized
        unassignedEpisodes = unassigned
    }
}
