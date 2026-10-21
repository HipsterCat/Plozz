import CoreModels
import CoreTrackerAuth
import Foundation

struct WetrakrDeviceCode: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: String
    let expiresIn: TimeInterval
    let interval: TimeInterval

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code", userCode = "user_code"
        case verificationURL = "verification_url", expiresIn = "expires_in", interval
    }
}

struct WetrakrTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token"
        case expiresIn = "expires_in", tokenType = "token_type"
    }

    func tokens(now: Date) throws -> TrackerTokens {
        guard !accessToken.isEmpty, !refreshToken.isEmpty,
              tokenType.lowercased() == "bearer", expiresIn.isFinite, expiresIn > 0
        else { throw AppError.invalidResponse }
        return TrackerTokens(
            accessToken: accessToken, refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(expiresIn)
        )
    }
}

struct WetrakrUser: Decodable, Sendable {
    struct Info: Decodable, Sendable { let username: String }
    let id: Int
    let info: Info
}

struct WetrakrIDs: Codable, Sendable, Equatable {
    var imdb: String?
    var tmdb: Int?
    var tvdb: Int?
    var trakt: Int?
    var anilist: Int?
    var myanimelist: Int?
    var anidb: Int?

    var externalIDs: [WatchlistExternalID] {
        [
            imdb.flatMap { WatchlistExternalID(namespace: .imdb, value: $0) },
            tmdb.flatMap { WatchlistExternalID(namespace: .tmdb, value: String($0)) },
            tvdb.flatMap { WatchlistExternalID(namespace: .tvdb, value: String($0)) },
            trakt.flatMap { WatchlistExternalID(namespace: .trakt, value: String($0)) },
            anilist.flatMap { WatchlistExternalID(namespace: .aniList, value: String($0)) },
            myanimelist.flatMap { WatchlistExternalID(namespace: .myAnimeList, value: String($0)) },
            anidb.flatMap { WatchlistExternalID(namespace: .aniDB, value: String($0)) },
        ].compactMap { $0 }.sorted()
    }

    static func from(_ providerIDs: [String: String], series: Bool = false) -> Self {
        var value = Self()
        for (key, raw) in providerIDs {
            let name = key.lowercased()
            let prefix = series ? "series" : ""
            guard name.hasPrefix(prefix) else { continue }
            let nameWithoutPrefix = String(name.dropFirst(prefix.count))
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = Int(text).flatMap { $0 > 0 ? $0 : nil }
            switch nameWithoutPrefix {
            case "imdb":
                if text.hasPrefix("tt"), text.count > 2, text.dropFirst(2).allSatisfy(\.isNumber) {
                    value.imdb = text
                }
            case "tmdb": value.tmdb = number
            case "tvdb": value.tvdb = number
            case "trakt": value.trakt = number
            case "anilist": value.anilist = number
            case "myanimelist", "mal": value.myanimelist = number
            case "anidb": value.anidb = number
            default: break
            }
        }
        return value
    }
}

struct WetrakrMedia: Codable, Sendable {
    let id: Int
    let type: String
    let ids: WetrakrIDs?
    let title: String? // l10n:content — provider media title
    var kind: MediaItemKind? {
        switch type {
        case "movie": .movie
        case "show": .series
        default: nil
        }
    }
}

struct WetrakrActivities: Decodable, Sendable {
    let all: String?
    let journalVisibleUntil: String?
    enum CodingKeys: String, CodingKey {
        case all, journalVisibleUntil = "journal_visible_until"
    }
}

struct WetrakrJournal: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let entryID: String
        let category: String
        let status: String
        let actionAt: String
        let type: String
        let id: Int
        let ids: WetrakrIDs?
        let title: String? // l10n:content — provider media title
        enum CodingKeys: String, CodingKey {
            case entryID = "entry_id", actionAt = "action_at"
            case category, status, type, id, ids, title
        }
        var media: WetrakrMedia { .init(id: id, type: type, ids: ids, title: title) }
    }
    let visibleUntil: String
    let journal: [Entry]
    enum CodingKeys: String, CodingKey { case visibleUntil = "visible_until", journal }
}

struct WetrakrScrobbleBody: Encodable, Sendable {
    struct Media: Encodable, Sendable {
        var id: Int?
        var ids: WetrakrIDs?
    }
    struct Episode: Encodable, Sendable {
        var id: Int?
        var season: Int?
        var number: Int?
    }
    var movie: Media?
    var show: Media?
    var episode: Episode?
    var progress: Double
}

struct WetrakrScrobbleResponse: Decodable, Sendable {
    let action: String?
    let ignored: Bool?
    let success: Bool?
}

enum WetrakrError: Error, Equatable {
    case authorizationPending
    case clientRejected
    case browserAuthorizationFailed
    case authorizationCodeRejected
    case invalidTokenResponse
    case requestBlocked
    case accessDenied
    case journalExpired
    case itemRejected
    case unsupportedIdentity
}

enum WetrakrDate {
    static func parse(_ value: String) throws -> Date {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }
        throw AppError.invalidResponse
    }
    static func string(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
}
