import Foundation
import Observation

/// A Home card is an entry into Live TV, never a resumable movie or episode.
public struct HomeLiveTVRoute: Codable, Hashable, Sendable {
    public let profileID: String
    public let channelID: String
    public let sourceID: String
    public let accountID: String?
    public let sourceAuthorizationID: String
    public let serverAuthorizationID: String

    public init(
        profileID: String, channelID: String, sourceID: String, accountID: String? = nil,
        sourceAuthorizationID: String, serverAuthorizationID: String
    ) {
        self.profileID = profileID
        self.channelID = channelID
        self.sourceID = sourceID
        self.accountID = accountID
        self.sourceAuthorizationID = sourceAuthorizationID
        self.serverAuthorizationID = serverAuthorizationID
    }
}

/// No stream URL, provider item, progress, or playback input. Artwork URLs may
/// contain credentials and require encrypted persistence in the local Home cache.
public struct HomeLiveTVChannel: Codable, Identifiable, Equatable, Sendable {
    public let route: HomeLiveTVRoute
    public let name: String
    public let sourceName: String
    public let number: Int
    public let logoURL: URL?
    public let organizationMetadata: LiveTVChannelOrganizationMetadata?
    public var id: HomeLiveTVRoute { route }

    public init(
        route: HomeLiveTVRoute, name: String, sourceName: String, number: Int, logoURL: URL? = nil,
        organizationMetadata: LiveTVChannelOrganizationMetadata? = nil
    ) {
        self.route = route
        self.name = String(name.prefix(160))
        self.sourceName = String(sourceName.prefix(160))
        self.number = number
        self.logoURL = logoURL
        self.organizationMetadata = organizationMetadata
    }
}

public struct HomeLiveTVSnapshot: Equatable, Sendable {
    public static let maximumRecentCount = 3
    public static let maximumRowCount = 8
    /// Bounds even unsuccessful/missing favorite lookups, not just output size.
    public static let maximumCandidateCount = 24
    public static let empty = HomeLiveTVSnapshot()
    public let recentChannels: [HomeLiveTVChannel]
    public let channels: [HomeLiveTVChannel]
    public var isEmpty: Bool { recentChannels.isEmpty && channels.isEmpty }

    public init(recentChannels: [HomeLiveTVChannel] = [], channels: [HomeLiveTVChannel] = []) {
        func unique(_ cards: [HomeLiveTVChannel], limit: Int) -> [HomeLiveTVChannel] {
            var seen = Set<HomeLiveTVRoute>()
            return Array(cards.prefix(Self.maximumCandidateCount).filter {
                seen.insert($0.id).inserted
            }.prefix(limit))
        }
        self.recentChannels = unique(recentChannels, limit: Self.maximumRecentCount)
        self.channels = unique(channels, limit: Self.maximumRowCount)
    }

    /// Only the Live TV catalog owner supplies this lookup; Home never loads a
    /// catalog. Recent IDs, favorites and the fallback prefix all have hard caps.
    public static func build(
        recentIDs: [String], favoriteIDs: [String], fallbackIDs: [String],
        channel: (String) -> HomeLiveTVChannel?
    ) -> Self {
        var resolved: [String: HomeLiveTVChannel] = [:]
        var visited = Set<String>()
        let recent = Array(recentIDs.prefix(maximumRecentCount))
        let favorites = Array(favoriteIDs.prefix(maximumCandidateCount))
        let fallback = Array(fallbackIDs.prefix(maximumCandidateCount))
        for id in recent + favorites + fallback {
            guard visited.count < maximumCandidateCount else { break }
            guard visited.insert(id).inserted else { continue }
            resolved[id] = channel(id)
        }
        return Self(
            recentChannels: recent.compactMap { resolved[$0] },
            channels: (favorites + recent + fallback).compactMap { resolved[$0] }
        )
    }

    public func filtering(_ allowed: (HomeLiveTVChannel) -> Bool) -> Self {
        Self(recentChannels: recentChannels.filter(allowed), channels: channels.filter(allowed))
    }
}

/// One profile's bounded metadata cache and one-shot explicit selection. Loaded
/// cards are candidates only: the runtime revalidates authority before display.
/// There is no timer, provider, disk catalog, tuner or refresh dependency here.
@MainActor @Observable
public final class HomeLiveTVModel {
    public struct Request: Equatable, Sendable {
        public let id: UUID
        public let route: HomeLiveTVRoute
    }

    public let profileID: String
    public private(set) var snapshot: HomeLiveTVSnapshot = .empty
    public private(set) var pendingRequest: Request?
    @ObservationIgnored private let store: (any HomeLiveTVSnapshotStoring)?

    public init(profileID: String, store: (any HomeLiveTVSnapshotStoring)? = nil) {
        self.profileID = profileID
        self.store = store
        self.snapshot = (store?.load() ?? .empty).filtering { $0.route.profileID == profileID }
    }

    public func publish(_ snapshot: HomeLiveTVSnapshot) {
        let scoped = snapshot.filtering { $0.route.profileID == profileID }
        if self.snapshot != scoped {
            self.snapshot = scoped
            store?.save(scoped)
        }
    }

    @discardableResult
    public func request(_ route: HomeLiveTVRoute, in visible: HomeLiveTVSnapshot) -> Bool {
        guard route.profileID == profileID,
              (visible.recentChannels + visible.channels).contains(where: { $0.route == route }) else {
            return false
        }
        pendingRequest = Request(id: UUID(), route: route)
        return true
    }

    /// Returns once only. A delayed destination cannot consume a newer press.
    @discardableResult
    public func consume(_ request: Request) -> Bool {
        guard pendingRequest == request else { return false }
        pendingRequest = nil
        return true
    }

    public func cancelRequest() { pendingRequest = nil }
}
