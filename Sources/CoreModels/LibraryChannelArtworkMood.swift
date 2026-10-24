import Foundation

/// A presentation hint derived from channel rules, never its editable or translated name.
public enum LibraryChannelArtworkMood: String, Codable, CaseIterable, Sendable {
    case neutral, cinematic, playful, calm, warm, intense, mysterious, imaginative

    public init(automaticKey: String?, recipe: LibraryChannelRecipe) {
        switch automaticKey {
        case "v1/movies": self = .cinematic
        case "v1/tv": self = .neutral
        case "v1/animation", "v1/kids", "v1/family": self = .playful
        case let key? where key.hasPrefix("v1/genre/"):
            self = Self.genreMood(String(key.dropFirst("v1/genre/".count))) ?? .neutral
        case let key? where key.hasPrefix("v1/decade/"):
            self = .warm
        case let key? where key.hasPrefix("v1/studio/") || key.hasPrefix("v1/director/"):
            self = .cinematic
        default:
            let moods = Set(recipe.genres.compactMap(Self.genreMood))
            if moods.count == 1, let mood = moods.first {
                self = mood
            } else {
                self = recipe.genres.isEmpty && recipe.includesMovies && !recipe.includesEpisodes
                    ? .cinematic : .neutral
            }
        }
    }

    private static func genreMood(_ genre: String) -> Self? {
        let key = genre.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        switch key {
        case "animation", "animated", "anime", "comedy", "family", "kids", "children": return .playful
        case "documentary", "nature", "history", "travel": return .calm
        case "romance", "drama", "western", "classics": return .warm
        case "action", "adventure", "action & adventure", "war", "sport", "sports": return .intense
        case "horror", "thriller", "crime", "mystery": return .mysterious
        case "science fiction", "science-fiction", "sci-fi", "scifi", "fantasy", "sci-fi & fantasy":
            return .imaginative
        default: return nil
        }
    }
}
