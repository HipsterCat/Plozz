import CoreModels
import Foundation

/// A `MediaProvider` that answers from the bundled kino.pub catalogue.
///
/// Exists so the tvOS UI can be judged on real Russian titles and real artwork
/// without a server, an account, or a network round-trip for anything but the
/// images. Playback is deliberately unimplemented — this demo is about how the
/// app looks, and a fake stream would only produce a player that fails oddly.
public struct KinoPubDemoProvider: MediaProvider {
    public let kind: ProviderKind = .jellyfin
    public let session: UserSession

    private let accountID: String
    private let catalog = KinoPubDemoCatalog.bundled

    public init(session: UserSession, accountID: String) {
        self.session = session
        self.accountID = accountID
    }

    // MARK: Lookup

    private func item(_ raw: KinoPubDemoCatalog.Item) -> MediaItem {
        raw.mediaItem(accountID: accountID, resume: catalog.resume[raw.id])
    }

    private var all: [MediaItem] { catalog.items.map(item) }

    private func items(forRow id: String) -> [MediaItem] {
        guard let row = catalog.rows.first(where: { $0.id == id }) else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: catalog.items.map { ($0.id, $0) })
        return row.itemIDs.compactMap { byID[$0] }.map(item)
    }

    private func containerKind(for libraryID: String) -> MediaItemKind {
        libraryID == KinoPubDemoLibrary.series ? .series : .movie
    }

    // MARK: MediaProvider

    public func libraries() async throws -> [MediaLibrary] {
        [
            MediaLibrary(id: KinoPubDemoLibrary.movies, title: "Фильмы", kind: .movie,
                         sourceAccountID: accountID),
            MediaLibrary(id: KinoPubDemoLibrary.series, title: "Сериалы", kind: .series,
                         sourceAccountID: accountID),
        ]
    }

    public func continueWatching(limit: Int) async throws -> [MediaItem] {
        Array(items(forRow: "continue").prefix(limit))
    }

    public func latest(limit: Int) async throws -> [MediaItem] {
        Array(items(forRow: "latest").prefix(limit))
    }

    public func item(id: String) async throws -> MediaItem {
        guard let raw = catalog.items.first(where: { $0.id == id }) else {
            throw KinoPubDemoError.notFound(id)
        }
        return item(raw)
    }

    /// Series get synthesised seasons and episodes: the catalogue carries a
    /// season count and nothing below it, and a series detail page with no
    /// children would render as a dead end rather than as a design to judge.
    public func children(of itemID: String) async throws -> [MediaItem] {
        guard let raw = catalog.items.first(where: { $0.id == itemID }),
              raw.mediaKind == .series
        else { return [] }

        if raw.id.hasPrefix("season-") { return [] }
        let seasons = raw.seasonCount ?? 1
        return (1...seasons).map { number in
            MediaItem(
                id: "season-\(raw.id)-\(number)",
                title: "Сезон \(number)",
                kind: .season,
                parentTitle: raw.title,
                seasonNumber: number,
                productionYear: raw.year.map { $0 + number - 1 },
                seriesID: raw.id,
                posterURL: raw.posterURL,
                backdropURL: raw.backdropURL,
                sourceAccountID: accountID,
                libraryID: KinoPubDemoLibrary.series
            )
        }
    }

    public func items(
        in containerID: String,
        kind: MediaItemKind,
        page: PageRequest
    ) async throws -> MediaPage {
        let pool: [MediaItem]
        switch containerID {
        case KinoPubDemoLibrary.movies, KinoPubDemoLibrary.series:
            pool = all.filter { $0.kind == containerKind(for: containerID) }
        default:
            pool = all
        }
        let start = min(page.startIndex, pool.count)
        let end = min(start + page.limit, pool.count)
        return MediaPage(items: Array(pool[start..<end]), startIndex: start, totalCount: pool.count)
    }

    public func libraryHubs(
        libraryID: String,
        kind: MediaItemKind,
        limit: Int
    ) async throws -> [LibrarySection] {
        // Each library shows only its own half of a genre, so "Драма" under
        // Фильмы and under Сериалы are different shelves rather than the same
        // one printed twice.
        let wanted: MediaItemKind = containerKind(for: libraryID)
        return catalog.rows
            .filter { $0.id.hasPrefix("genre-") }
            .map { row in
                LibrarySection(
                    id: "\(libraryID)-\(row.id)",
                    title: row.title.capitalized,
                    style: .poster,
                    items: Array(
                        items(forRow: row.id).filter { $0.kind == wanted }.prefix(limit)
                    )
                )
            }
            .filter { $0.items.count >= 4 }
    }

    public func search(query: String, limit: Int) async throws -> [MediaItem] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || ($0.originalTitle?.localizedCaseInsensitiveContains(needle) ?? false)
                || $0.genres.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
        .prefix(limit)
        .map { $0 }
    }

    public func playbackInfo(for itemID: String) async throws -> PlaybackRequest {
        throw KinoPubDemoError.playbackUnavailable
    }

    public func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}

    /// Artwork URLs are already absolute in the catalogue, so there is nothing
    /// to build here; callers that ask by id get the poster they already hold.
    public func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? {
        guard let raw = catalog.items.first(where: { $0.id == itemID }) else { return nil }
        switch kind {
        case .backdrop: return raw.backdropURL ?? raw.posterWideURL
        case .logo: return raw.logoURL
        default: return raw.posterURL
        }
    }
}

public enum KinoPubDemoError: LocalizedError {
    case notFound(String)
    case playbackUnavailable

    public var errorDescription: String? {
        switch self {
        case .notFound(let id): "Нет такой позиции в демо-каталоге (\(id))"
        case .playbackUnavailable: "Демо без плеера — здесь только внешний вид"
        }
    }
}
