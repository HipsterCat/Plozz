/// The numbering system explicitly reported by a server for a series or episode.
/// Missing metadata stays nil; an unrecognized reported order is `unknown`.
public enum EpisodeOrdering: String, Codable, Hashable, Sendable {
    case tvdbDefault
    case aired
    case dvd
    case absolute
    case alternate
    case regional
    case tmdb
    case unknown
}
