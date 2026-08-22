import CoreModels
import Foundation

/// The offline kino.pub catalogue bundled with this module.
///
/// Real titles, real artwork URLs, real synopses — pulled once from the local
/// kino.pub snapshot by `tools/kinopub-demo/build_catalog.py` and frozen into
/// JSON. Nothing here talks to kino.pub at runtime; only the CDNs that serve the
/// images are hit, and only by the image loader.
struct KinoPubDemoCatalog: Decodable, Sendable {
    struct Person: Decodable, Sendable {
        let name: String
        let role: String?
        let kind: String?
        let imageURL: URL?
    }

    struct Item: Decodable, Sendable {
        let id: String
        let kind: String
        let title: String
        let originalTitle: String?
        let year: Int?
        let overview: String?
        let tagline: String?
        let genres: [String]
        let runtimeMinutes: Int?
        let officialRating: String?
        let imdbRating: Double?
        let kinopoiskRating: Double?
        let posterURL: URL?
        let posterWideURL: URL?
        let backdropURL: URL?
        let logoURL: URL?
        let people: [Person]
        let seasonCount: Int?
    }

    struct Row: Decodable, Sendable {
        let id: String
        let title: String
        let itemIDs: [String]
    }

    let items: [Item]
    let rows: [Row]
    /// Seconds already watched, for the Continue Watching row.
    let resume: [String: Double]

    /// Built once, off the single bundled instance. Home asks for nine rows on
    /// every refresh, and rebuilding a 140-entry dictionary per row is work
    /// nobody needs — there is only ever one catalogue in a process.
    private static let index: [String: Item] =
        Dictionary(uniqueKeysWithValues: bundled.items.map { ($0.id, $0) })

    func item(id: String) -> Item? { Self.index[id] }

    func items(inRow id: String) -> [Item] {
        guard let row = rows.first(where: { $0.id == id }) else { return [] }
        return row.itemIDs.compactMap { Self.index[$0] }
    }

    static let bundled: KinoPubDemoCatalog = {
        guard let url = Bundle.module.url(forResource: "KinoPubDemoCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(KinoPubDemoCatalog.self, from: data)
        else {
            // A demo build with no catalogue is a broken build, not a degraded
            // one — an empty Home would look like a provider bug.
            preconditionFailure("KinoPubDemoCatalog.json missing or unreadable")
        }
        return catalog
    }()
}

// MARK: - Mapping to Plozz's model

extension KinoPubDemoCatalog.Item {
    var mediaKind: MediaItemKind {
        kind == "series" ? .series : .movie
    }

    /// kino.pub reports an age gate as `age18`; Plozz shows `officialRating` verbatim.
    var displayRating: String? {
        guard let officialRating, officialRating.hasPrefix("age") else { return officialRating }
        return String(officialRating.dropFirst(3)) + "+"
    }

    var ratings: [ExternalRating] {
        var result: [ExternalRating] = []
        if let imdbRating {
            result.append(ExternalRating(source: .imdb, value: imdbRating, scale: .outOfTen))
        }
        if let kinopoiskRating {
            // Plozz has no `kinopoisk` source and adding one would ripple
            // through every ratings surface. `.community` renders as a generic
            // audience score on the same 0–10 scale, which is what this is.
            result.append(ExternalRating(source: .community, value: kinopoiskRating, scale: .outOfTen))
        }
        return result
    }

    func mediaItem(accountID: String, resume: Double?) -> MediaItem {
        let runtime = runtimeMinutes.map { TimeInterval($0) * 60 }
        return MediaItem(
            id: id,
            title: title,
            originalTitle: originalTitle,
            kind: mediaKind,
            overview: overview,
            productionYear: year,
            officialRating: displayRating,
            genres: genres,
            people: people.enumerated().map { index, person in
                MediaPerson(
                    id: "\(id)-p\(index)",
                    name: person.name,
                    role: person.role,
                    kind: person.kind,
                    imageURL: person.imageURL
                )
            },
            taglines: tagline.map { [$0] } ?? [],
            runtime: runtime,
            resumePosition: resume,
            playedPercentage: resume.flatMap { position in
                runtime.map { min(100, position / $0 * 100) }
            },
            posterURL: posterURL,
            backdropURL: backdropURL ?? posterWideURL,
            heroBackdropURL: backdropURL,
            fallbackArtworkURL: posterWideURL,
            logoURL: logoURL,
            ratings: ratings,
            sourceAccountID: accountID,
            libraryID: mediaKind == .series ? KinoPubDemoLibrary.series : KinoPubDemoLibrary.movies
        )
    }
}

enum KinoPubDemoLibrary {
    static let movies = "kinopub-movies"
    static let series = "kinopub-series"
}
