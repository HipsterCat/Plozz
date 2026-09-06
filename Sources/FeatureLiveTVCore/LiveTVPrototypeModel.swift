#if DEBUG
import Foundation
import Observation

public enum LiveTVPrototypeSource: String, CaseIterable, Identifiable, Sendable {
    case iptv
    case jellyfin
    case plex
    case emby
    case plozz

    public var id: String { rawValue }
}

public enum LiveTVPrototypeScenario: String, CaseIterable, Identifiable, Sendable {
    case noGuide
    case mixedGuide
    case fullGuide
    case staleGuide
    case failedGuide

    public var id: String { rawValue }
}

public enum LiveTVPrototypeSort: String, CaseIterable, Identifiable, Sendable {
    case channelNumber
    case name

    public var id: String { rawValue }
}

public struct LiveTVPrototypeChannel: Identifiable, Equatable, Sendable {
    public let id: String
    public let number: Int
    public let name: String
    public let category: String
    public let symbol: String
    public let accent: Int
    public let source: LiveTVPrototypeSource
    public let tagline: String
    public let logoURL: URL?
    public let streamURL: URL?
    public let logoNeedsDarkBackground: Bool

    public init(
        id: String,
        number: Int,
        name: String,
        category: String,
        symbol: String,
        accent: Int,
        source: LiveTVPrototypeSource,
        tagline: String,
        logoURL: URL? = nil,
        streamURL: URL? = nil,
        logoNeedsDarkBackground: Bool = false
    ) {
        precondition((0...5).contains(accent), "Live TV fixture accent must be between 0 and 5.")
        self.id = id
        self.number = number
        self.name = name
        self.category = category
        self.symbol = symbol
        self.accent = accent
        self.source = source
        self.tagline = tagline
        self.logoURL = logoURL
        self.streamURL = streamURL
        self.logoNeedsDarkBackground = logoNeedsDarkBackground
    }
}

public struct LiveTVPrototypeProgram: Identifiable, Equatable, Sendable {
    public let id: String
    public let channelID: String
    public let title: String
    public let subtitle: String
    public let start: Date
    public let end: Date

    public init(
        id: String,
        channelID: String,
        title: String,
        subtitle: String,
        start: Date,
        end: Date
    ) {
        self.id = id
        self.channelID = channelID
        self.title = title
        self.subtitle = subtitle
        self.start = start
        self.end = end
    }

    public func progress(at date: Date) -> Double {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return date < start ? 0 : 1 }
        return min(max(date.timeIntervalSince(start) / duration, 0), 1)
    }
}

@MainActor
@Observable
public final class LiveTVPrototypeModel {
    public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            refreshVisibleChannels()
        }
    }

    public var category: String? {
        didSet {
            guard category != oldValue else { return }
            refreshVisibleChannels()
        }
    }

    public var source: LiveTVPrototypeSource? {
        didSet {
            guard source != oldValue else { return }
            refreshVisibleChannels()
        }
    }

    public var favoritesOnly = false {
        didSet {
            guard favoritesOnly != oldValue else { return }
            refreshVisibleChannels()
        }
    }

    public var sort: LiveTVPrototypeSort = .channelNumber {
        didSet {
            guard sort != oldValue else { return }
            refreshVisibleChannels()
        }
    }

    public var scenario: LiveTVPrototypeScenario

    public var isLargeCatalog: Bool {
        didSet {
            guard isLargeCatalog != oldValue else { return }
            rebuildCatalog()
        }
    }

    public private(set) var visibleChannels: [LiveTVPrototypeChannel] = []
    public private(set) var channels: [LiveTVPrototypeChannel] = []
    public private(set) var favoriteIDs: Set<String>
    public private(set) var now: Date
    public private(set) var categories: [String] = []

    public private(set) var playingChannelID: String?
    public private(set) var previousChannelID: String?
    public private(set) var isPaused = false
    public private(set) var behindLiveSeconds: TimeInterval = 0
    public var simulateTunerBusy = false
    public private(set) var tuneFailed = false

    @ObservationIgnored private var channelsByID: [String: LiveTVPrototypeChannel] = [:]
    @ObservationIgnored private var channelOrdinalsByID: [String: Int] = [:]
    @ObservationIgnored private var isBatchingFilterChanges = false
    @ObservationIgnored private let suppliedChannels: [LiveTVPrototypeChannel]?

    public var usesPublicStreams: Bool { suppliedChannels != nil }

    public init(
        now: Date = Date(timeIntervalSince1970: 1_788_719_400),
        scenario: LiveTVPrototypeScenario = .mixedGuide,
        isLargeCatalog: Bool = false,
        channels: [LiveTVPrototypeChannel]? = nil
    ) {
        self.now = now
        self.scenario = scenario
        self.isLargeCatalog = isLargeCatalog
        suppliedChannels = channels
        favoriteIDs = channels.map { Set($0.prefix(5).map(\.id)) }
            ?? Set((1...5).map(Self.channelID))
        rebuildCatalog()
    }

    public func channel(id: String) -> LiveTVPrototypeChannel? {
        channelsByID[id]
    }

    public func toggleFavorite(_ id: String) {
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        if favoritesOnly {
            refreshVisibleChannels()
        }
    }

    public func resetFilters() {
        isBatchingFilterChanges = true
        query = ""
        category = nil
        source = nil
        favoritesOnly = false
        isBatchingFilterChanges = false
        refreshVisibleChannels()
    }

    public func currentProgram(for channelID: String) -> LiveTVPrototypeProgram? {
        programs(for: channelID, from: now, hours: 1).first {
            $0.start <= now && now < $0.end
        }
    }

    public func programs(
        for channelID: String,
        from date: Date,
        hours: Int = 3
    ) -> [LiveTVPrototypeProgram] {
        guard hours > 0,
              let channel = channelsByID[channelID],
              hasGuide(for: channel)
        else { return [] }

        let boundedHours = min(hours, 24)
        let duration = programDuration(for: channelID)
        let requestedEnd = date.addingTimeInterval(TimeInterval(boundedHours) * 3_600)
        var slotStartSeconds = floor(date.timeIntervalSince1970 / duration) * duration
        var result: [LiveTVPrototypeProgram] = []
        result.reserveCapacity(
            Int(ceil((requestedEnd.timeIntervalSince1970 - slotStartSeconds) / duration))
        )

        while slotStartSeconds < requestedEnd.timeIntervalSince1970 {
            let start = Date(timeIntervalSince1970: slotStartSeconds)
            let end = start.addingTimeInterval(duration)
            result.append(program(for: channel, start: start, end: end))
            slotStartSeconds += duration
        }
        return result
    }

    public func advanceClock(by interval: TimeInterval) {
        precondition(interval.isFinite && interval >= 0, "Live TV prototype clock only advances forward.")
        now = now.addingTimeInterval(interval)
        if isPaused, playingChannelID != nil {
            behindLiveSeconds += interval
        }
    }

    /// Invalid fixture IDs and simulated tuner contention report through
    /// `tuneFailed`; neither condition changes the current stream.
    public func tune(_ id: String) {
        guard channelsByID[id] != nil else {
            tuneFailed = true
            return
        }
        if playingChannelID == id {
            tuneFailed = false
            return
        }
        guard !simulateTunerBusy else {
            tuneFailed = true
            return
        }

        previousChannelID = playingChannelID
        playingChannelID = id
        isPaused = false
        behindLiveSeconds = 0
        tuneFailed = false
    }

    public func stop() {
        playingChannelID = nil
        previousChannelID = nil
        isPaused = false
        behindLiveSeconds = 0
        tuneFailed = false
    }

    public func togglePause() {
        guard playingChannelID != nil else { return }
        isPaused.toggle()
    }

    public func goLive() {
        guard playingChannelID != nil else { return }
        isPaused = false
        behindLiveSeconds = 0
    }

    public func tunePrevious() {
        guard let previousChannelID else { return }
        tune(previousChannelID)
    }

    public func clearTuneFailure() {
        tuneFailed = false
    }

    private func rebuildCatalog() {
        if let suppliedChannels {
            let count = suppliedChannels.isEmpty ? 0 : (isLargeCatalog ? 5_000 : suppliedChannels.count)
            channels = (0..<count).map { index in
                let channel = suppliedChannels[index % suppliedChannels.count]
                let copy = index / suppliedChannels.count
                guard copy > 0 else { return channel }
                return LiveTVPrototypeChannel(
                    id: "\(channel.id)-copy-\(copy)", number: index + 1,
                    name: "\(channel.name) (copy \(copy + 1))", category: channel.category,
                    symbol: channel.symbol, accent: channel.accent, source: channel.source,
                    tagline: channel.tagline, logoURL: channel.logoURL, streamURL: channel.streamURL,
                    logoNeedsDarkBackground: channel.logoNeedsDarkBackground
                )
            }
        } else {
            let count = isLargeCatalog ? 5_000 : Self.baseStations.count
            channels = (1...count).map(Self.makeChannel)
        }
        channelsByID = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        channelOrdinalsByID = Dictionary(
            uniqueKeysWithValues: channels.enumerated().map { ($0.element.id, $0.offset + 1) }
        )
        categories = Set(channels.map(\.category)).sorted {
            Self.normalized($0) < Self.normalized($1)
        }
        if let playingChannelID, channelsByID[playingChannelID] == nil {
            stop()
        } else if let previousChannelID, channelsByID[previousChannelID] == nil {
            self.previousChannelID = nil
        }
        refreshVisibleChannels()
    }

    private func refreshVisibleChannels() {
        guard !isBatchingFilterChanges else { return }
        let normalizedQuery = Self.normalized(query)
        let selectedCategory = category.map(Self.normalized)

        visibleChannels = channels.compactMap { channel -> (LiveTVPrototypeChannel, Int)? in
            guard selectedCategory == nil || Self.normalized(channel.category) == selectedCategory,
                  source == nil || channel.source == source,
                  !favoritesOnly || favoriteIDs.contains(channel.id)
            else { return nil }

            guard !normalizedQuery.isEmpty else { return (channel, 0) }
            let number = String(channel.number)
            if number == normalizedQuery {
                return (channel, 0)
            }
            let fields = [
                Self.normalized(channel.name),
                number,
                Self.normalized(channel.category),
                Self.normalized(channel.source.rawValue)
            ]
            if fields.contains(where: { $0.hasPrefix(normalizedQuery) }) {
                return (channel, 1)
            }
            if fields.contains(where: { $0.contains(normalizedQuery) }) {
                return (channel, 2)
            }
            return nil
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 < rhs.1
            }
            return channelsAreOrdered(lhs.0, before: rhs.0)
        }
        .map(\.0)
    }

    private func channelsAreOrdered(
        _ lhs: LiveTVPrototypeChannel,
        before rhs: LiveTVPrototypeChannel
    ) -> Bool {
        switch sort {
        case .channelNumber:
            if lhs.number != rhs.number {
                return lhs.number < rhs.number
            }
        case .name:
            let lhsName = Self.normalized(lhs.name)
            let rhsName = Self.normalized(rhs.name)
            if lhsName != rhsName {
                return lhsName < rhsName
            }
        }
        return lhs.id < rhs.id
    }

    private func hasGuide(for channel: LiveTVPrototypeChannel) -> Bool {
        // Real streams never inherit synthetic schedules from the layout fixtures.
        guard !usesPublicStreams else { return false }
        switch scenario {
        case .noGuide, .failedGuide:
            return false
        case .fullGuide, .staleGuide:
            return true
        case .mixedGuide:
            let ordinal = channelOrdinalsByID[channel.id] ?? 0
            return channel.source == .plozz || ordinal.isMultiple(of: 3)
        }
    }

    private func programDuration(for channelID: String) -> TimeInterval {
        let ordinal = channelOrdinalsByID[channelID] ?? 1
        return ordinal.isMultiple(of: 4) ? 3_600 : 1_800
    }

    private func program(
        for channel: LiveTVPrototypeChannel,
        start: Date,
        end: Date
    ) -> LiveTVPrototypeProgram {
        let duration = end.timeIntervalSince(start)
        let slot = Int(start.timeIntervalSince1970 / duration)
        let ordinal = channelOrdinalsByID[channel.id] ?? 1
        let fixture = Self.programFixtures[Self.positiveModulo(slot + ordinal, Self.programFixtures.count)]
        let startSeconds = Int(start.timeIntervalSince1970)
        return LiveTVPrototypeProgram(
            id: "\(channel.id)-\(startSeconds)-\(Int(duration))",
            channelID: channel.id,
            title: fixture.title,
            subtitle: fixture.subtitle,
            start: start,
            end: end
        )
    }

    private static func makeChannel(ordinal: Int) -> LiveTVPrototypeChannel {
        let baseIndex = (ordinal - 1) % baseStations.count
        let variant = (ordinal - 1) / baseStations.count + 1
        let station = baseStations[baseIndex]
        let name = variant == 1 ? station.name : "\(station.name) \(variant)"
        let tagline = variant == 1
            ? station.tagline
            : "\(station.tagline) Catalog variant \(variant)."
        return LiveTVPrototypeChannel(
            id: channelID(ordinal),
            number: ordinal,
            name: name,
            category: station.category,
            symbol: station.symbol,
            accent: (station.accent + variant - 1) % 6,
            source: station.source,
            tagline: tagline
        )
    }

    private static func channelID(_ ordinal: Int) -> String {
        String(format: "live-tv-%04d", ordinal)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private struct StationFixture {
        let name: String
        let category: String
        let symbol: String
        let accent: Int
        let source: LiveTVPrototypeSource
        let tagline: String
    }

    private static let baseStations: [StationFixture] = [
        .init(name: "World Desk", category: "News", symbol: "globe", accent: 0, source: .iptv, tagline: "Headlines from a fictional global newsroom."),
        .init(name: "Cinema Club", category: "Movies", symbol: "film", accent: 1, source: .jellyfin, tagline: "Made-up movies and friendly introductions."),
        .init(name: "Comedy Hour", category: "Comedy", symbol: "theatermasks", accent: 2, source: .plex, tagline: "Sketches, stand-up, and improvised mishaps."),
        .init(name: "Wild Earth", category: "Nature", symbol: "leaf", accent: 3, source: .emby, tagline: "Quiet journeys through imaginary habitats."),
        .init(name: "Arena Central", category: "Sports", symbol: "sportscourt", accent: 4, source: .plozz, tagline: "Fixture matches, recaps, and studio analysis."),
        .init(name: "Café Society", category: "Culture", symbol: "paintpalette", accent: 5, source: .iptv, tagline: "Artists and ideas meet over a fictional cup."),
        .init(name: "Storybook", category: "Kids", symbol: "book.closed", accent: 0, source: .jellyfin, tagline: "Gentle animated tales for young viewers."),
        .init(name: "Neighborhood Live", category: "Community", symbol: "person.3", accent: 1, source: .plex, tagline: "Local events from an entirely invented town."),
        .init(name: "Science Window", category: "Science", symbol: "atom", accent: 2, source: .emby, tagline: "Simple experiments and curious questions."),
        .init(name: "Retro Rewind", category: "Classics", symbol: "clock.arrow.circlepath", accent: 3, source: .plozz, tagline: "Freshly fictional favorites from decades past."),
        .init(name: "Kitchen Table", category: "Food", symbol: "fork.knife", accent: 4, source: .iptv, tagline: "Comfort cooking with pantry-sized challenges."),
        .init(name: "Road Atlas", category: "Travel", symbol: "map", accent: 5, source: .jellyfin, tagline: "Scenic routes through places that never existed."),
        .init(name: "Night Signals", category: "Music", symbol: "music.note", accent: 0, source: .plex, tagline: "Late sets from original imaginary performers."),
        .init(name: "Market Brief", category: "Business", symbol: "chart.line.uptrend.xyaxis", accent: 1, source: .emby, tagline: "Demo markets, explainers, and fictional figures."),
        .init(name: "Weather Watch", category: "Weather", symbol: "cloud.sun", accent: 2, source: .plozz, tagline: "Forecasts for the prototype coast."),
        .init(name: "Open Stage", category: "Culture", symbol: "music.mic", accent: 3, source: .iptv, tagline: "New plays and performances from a demo venue."),
        .init(name: "Game Day Extra", category: "Sports", symbol: "trophy", accent: 4, source: .jellyfin, tagline: "More fictional fixtures and postgame conversation."),
        .init(name: "Documentary Room", category: "Documentary", symbol: "doc.text.image", accent: 5, source: .plex, tagline: "Original short documentaries about imagined subjects."),
        .init(name: "Morning Mix", category: "Lifestyle", symbol: "sun.max", accent: 0, source: .emby, tagline: "A bright fixture blend of guests and ideas."),
        .init(name: "Pixel Play", category: "Gaming", symbol: "gamecontroller", accent: 1, source: .plozz, tagline: "Invented tournaments and relaxed game talk."),
        .init(name: "History Vault", category: "History", symbol: "building.columns", accent: 2, source: .iptv, tagline: "Stories recovered from a fictional archive."),
        .init(name: "Makers Workshop", category: "Education", symbol: "hammer", accent: 3, source: .jellyfin, tagline: "Small builds demonstrated one careful step at a time."),
        .init(name: "Cozy Mysteries", category: "Drama", symbol: "sparkles.tv", accent: 4, source: .plex, tagline: "Low-stakes cases in a made-up village."),
        .init(name: "Late Night Shorts", category: "Comedy", symbol: "rectangle.stack", accent: 5, source: .emby, tagline: "Compact comedies made for this fixture."),
        .init(name: "Ocean View", category: "Nature", symbol: "water.waves", accent: 0, source: .plozz, tagline: "Calm expeditions across imaginary seas."),
        .init(name: "Festival Screen", category: "Movies", symbol: "ticket", accent: 1, source: .iptv, tagline: "Original festival selections and filmmaker chats."),
        .init(name: "Junior Lab", category: "Kids", symbol: "testtube.2", accent: 2, source: .jellyfin, tagline: "Safe science puzzles for curious young minds."),
        .init(name: "City Council", category: "Civic", symbol: "building.2", accent: 3, source: .plex, tagline: "Proceedings from a purely fictional municipality."),
        .init(name: "Quiet Channel", category: "Uncategorized", symbol: "questionmark.square", accent: 4, source: .emby, tagline: "A useful home for uncategorized demo programming."),
        .init(name: "Plozz Preview", category: "Entertainment", symbol: "play.tv", accent: 5, source: .plozz, tagline: "Prototype highlights from across the fixture lineup.")
    ]

    private static let programFixtures: [(title: String, subtitle: String)] = [
        ("First Edition", "A concise start to the next block."),
        ("Open Window", "Stories gathered from around the demo schedule."),
        ("The Long Route", "A thoughtful trip with an unexpected turn."),
        ("Studio Session", "Original guests share work and process."),
        ("Field Notes", "Small observations from a fictional expedition."),
        ("Half-Time Table", "Friendly analysis without real-world results."),
        ("Picture House", "A short feature from the prototype archive."),
        ("Bright Ideas", "Curious questions meet practical demonstrations."),
        ("Local Color", "People and places from an invented community."),
        ("Night Shift", "A calm late block of stories and conversation."),
        ("Second Look", "Another angle on the day's fixture topics."),
        ("Next Stop", "A compact journey to a newly imagined destination.")
    ]
}
#endif
