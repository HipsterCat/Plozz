#if DEBUG
import Foundation
import Observation

public protocol LiveTVSourceLoading: Sendable {
    func loadPlaylist(from url: URL) async throws -> LiveTVPlaylistImport
    func loadGuide(
        from url: URL, channels: [LiveTVPrototypeChannel], now: Date
    ) async throws -> LiveTVGuideImport
}

extension LiveTVSourceLoader: LiveTVSourceLoading {}

public enum LiveTVImportPhase: Equatable, Sendable {
    case idle, loading, loaded, failed
}

public struct LiveTVGuideSourceStatus: Identifiable, Equatable, Sendable {
    public let source: LiveTVGuideSource
    public var id: String { source.id }
    public fileprivate(set) var phase: LiveTVImportPhase = .idle
    public fileprivate(set) var failure: LiveTVSourceImportError?
    public fileprivate(set) var matchedChannelCount = 0
    public fileprivate(set) var programCount = 0
    public fileprivate(set) var lastRefresh: Date?
}

public enum LiveTVGuideGapState: Equatable, Sendable {
    case loading, disabled, failed, unmatched, noListings

    public var title: LocalizedStringResource {
        switch self {
        case .loading: "Loading guide..."
        case .disabled: "No guide sources enabled"
        case .failed: "Guide update failed"
        case .unmatched: "No matching program guide"
        case .noListings: "No listings for this time"
        }
    }
}

@MainActor
@Observable
public final class LiveTVPrototypeImportModel {
    public let playlistURL: URL
    public private(set) var guideSources: [LiveTVGuideSourceStatus]
    public private(set) var enabledSourceIDs: Set<String>
    public private(set) var selectedSourceByChannel: [String: String] = [:]
    public private(set) var playlistPhase: LiveTVImportPhase = .idle
    public private(set) var guidePhase: LiveTVImportPhase = .idle
    public private(set) var playlistFailure: LiveTVSourceImportError?
    public private(set) var guideFailure: LiveTVSourceImportError?
    public private(set) var entryCount = 0
    public private(set) var skippedEntryCount = 0
    public private(set) var guideChannelCount = 0
    public private(set) var matchedChannelCount = 0
    public private(set) var programCount = 0
    public private(set) var coverageStart: Date?
    public private(set) var coverageEnd: Date?
    public private(set) var lastGuideRefresh: Date?

    @ObservationIgnored private let loader: any LiveTVSourceLoading
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var cachedGuides: [String: LiveTVGuideImport] = [:]
    @ObservationIgnored private var sourceChannels: [LiveTVPrototypeChannel] = []

    public var isLoading: Bool { playlistPhase == .loading || guidePhase == .loading }
    public var failedSourceCount: Int {
        guideSources.filter { enabledSourceIDs.contains($0.id) && $0.phase == .failed }.count
    }
    public var completedSourceCount: Int {
        guideSources.filter {
            enabledSourceIDs.contains($0.id) && ($0.phase == .loaded || $0.phase == .failed)
        }.count
    }

    public init(
        playlistURL: URL = URL(string: "https://iptv-org.github.io/iptv/countries/us.m3u")!,
        guideURL: URL? = nil,
        sources: [LiveTVGuideSource] = LiveTVGuideSource.defaults,
        loader: any LiveTVSourceLoading = LiveTVSourceLoader()
    ) {
        self.playlistURL = playlistURL
        let sources = guideURL.map {
            [LiveTVGuideSource(id: "guide", name: "XMLTV", url: $0, provider: LiveTVGuideSource.provider(for: $0))]
        } ?? sources
        precondition(Set(sources.map(\.id)).count == sources.count, "Guide source IDs must be unique.")
        guideSources = sources.map { LiveTVGuideSourceStatus(source: $0) }
        enabledSourceIDs = Set(sources.map(\.id))
        self.loader = loader
    }

    public func setSourceEnabled(_ sourceID: String, enabled: Bool, into model: LiveTVPrototypeModel) throws {
        guard guideSources.contains(where: { $0.id == sourceID }) else {
            throw LiveTVSourceImportError.invalidGuide
        }
        guard enabledSourceIDs.contains(sourceID) != enabled else { return }
        if enabled { enabledSourceIDs.insert(sourceID) }
        else {
            enabledSourceIDs.remove(sourceID)
            cachedGuides.removeValue(forKey: sourceID)
        }
        // Fence in-flight results immediately, before SwiftUI starts the replacement task.
        revision += 1
        for index in guideSources.indices where guideSources[index].phase == .loading {
            guideSources[index].phase = .idle
        }
        guidePhase = enabledSourceIDs.isEmpty ? .idle : .loading
        try publishGuides(into: model)
    }

    public func gapState(for channel: LiveTVPrototypeChannel) -> LiveTVGuideGapState {
        if enabledSourceIDs.isEmpty { return .disabled }
        if selectedSourceByChannel[channel.id] != nil { return .noListings }
        if playlistPhase == .idle || playlistPhase == .loading || guidePhase == .loading { return .loading }
        let provider = LiveTVStreamIdentity(url: channel.streamURL).provider
        let relevant = guideSources.filter {
            enabledSourceIDs.contains($0.id) && $0.source.provider == provider
        }
        if relevant.contains(where: { $0.phase == .failed }) { return .failed }
        return .unmatched
    }

    public func reload(into model: LiveTVPrototypeModel) async {
        revision += 1
        let request = revision
        guidePhase = enabledSourceIDs.isEmpty ? .idle : .loading
        for index in guideSources.indices where guideSources[index].phase == .loading {
            guideSources[index].phase = .idle
        }
        playlistPhase = .loading
        playlistFailure = nil
        do {
            let playlist = try await loader.loadPlaylist(from: playlistURL)
            try Task.checkCancellation()
            guard revision == request else { return }
            try model.replaceChannels(playlist.channels)
            sourceChannels = playlist.channels
            entryCount = playlist.entryCount
            skippedEntryCount = playlist.skippedEntryCount
            playlistPhase = .loaded
            try publishGuides(into: model)
        } catch {
            guard revision == request else { return }
            let cancelled = Task.isCancelled || error is CancellationError
                || (error as? LiveTVSourceImportError) == .cancelled
            playlistFailure = cancelled ? nil : error as? LiveTVSourceImportError ?? .invalidPlaylist
            playlistPhase = cancelled ? .idle : .failed
            guidePhase = cachedGuides.isEmpty ? .idle : .loaded
            return
        }

        guideFailure = nil
        for index in guideSources.indices {
            guideSources[index].phase = .idle
            guideSources[index].failure = nil
        }
        let now = Date()
        for index in guideSources.indices where enabledSourceIDs.contains(guideSources[index].id) {
            guard revision == request else { return }
            let source = guideSources[index].source
            guideSources[index].phase = .loading
            do {
                let guide = try await loader.loadGuide(from: source.url, channels: sourceChannels, now: now)
                try Task.checkCancellation()
                guard revision == request else { return }
                let previous = cachedGuides[source.id]
                cachedGuides[source.id] = guide
                do {
                    try validateCacheBudget()
                    try publishGuides(into: model)
                } catch {
                    cachedGuides[source.id] = previous
                    throw error
                }
                guideSources[index].matchedChannelCount = guide.matchedChannelCount
                guideSources[index].programCount = guide.programCount
                guideSources[index].lastRefresh = Date()
                guideSources[index].phase = .loaded
                lastGuideRefresh = guideSources[index].lastRefresh
            } catch {
                guard revision == request else { return }
                if Task.isCancelled || error is CancellationError
                    || (error as? LiveTVSourceImportError) == .cancelled {
                    guideSources[index].phase = .idle
                    guidePhase = .idle
                    return
                }
                let failure = error as? LiveTVSourceImportError ?? .invalidGuide
                guideSources[index].failure = failure
                guideSources[index].phase = .failed
                guideFailure = failure
            }
        }
        if enabledSourceIDs.isEmpty { guidePhase = .idle }
        else {
            guidePhase = failedSourceCount == enabledSourceIDs.count ? .failed : .loaded
        }
    }

    private func publishGuides(into model: LiveTVPrototypeModel) throws {
        let channelIDs = Set(sourceChannels.map(\.id))
        var chosen: [String: (
            sourceID: String, method: LiveTVGuideMatchMethod,
            programs: [LiveTVPrototypeProgram], hasUpcomingListings: Bool
        )] = [:]
        var channelCount = 0
        for status in guideSources where enabledSourceIDs.contains(status.id) {
            guard let guide = cachedGuides[status.id] else { continue }
            channelCount += guide.guideChannelCount
            let grouped = Dictionary(grouping: guide.programs, by: \.channelID)
            let matchedIDs = Set(guide.matches.keys).union(grouped.keys).intersection(channelIDs)
            for channelID in matchedIDs {
                let method = guide.matches[channelID]?.method ?? .displayName
                let programs = grouped[channelID] ?? []
                let upcoming = programs.contains { $0.end > model.now }
                // Never blend providers' schedules. Prefer usable listings when identity confidence ties.
                if let existing = chosen[channelID] {
                    if existing.method > method { continue }
                    if existing.method == method, existing.hasUpcomingListings || !upcoming { continue }
                }
                chosen[channelID] = (status.id, method, programs, upcoming)
            }
        }
        let programs = chosen.values.flatMap(\.programs)
        try model.replacePrograms(programs)
        selectedSourceByChannel = chosen.mapValues(\.sourceID)
        guideChannelCount = channelCount
        matchedChannelCount = chosen.count
        programCount = programs.count
        coverageStart = programs.map(\.start).min()
        coverageEnd = programs.map(\.end).max()
    }

    private func validateCacheBudget() throws {
        var count = 0
        var textBytes = 0
        for guide in cachedGuides.values {
            count += guide.programs.count
            guard count <= LiveTVXMLTVParser.maximumRetainedPrograms else {
                throw LiveTVSourceImportError.guideTooLarge
            }
            for program in guide.programs {
                textBytes += program.title.utf8.count + program.subtitle.utf8.count
                guard textBytes <= LiveTVXMLTVParser.maximumRetainedTextBytes else {
                    throw LiveTVSourceImportError.guideTooLarge
                }
            }
        }
    }
}
#endif
