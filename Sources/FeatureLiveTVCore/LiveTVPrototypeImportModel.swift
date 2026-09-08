#if DEBUG
import CoreModels
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
    public let playlistSourceID: String
    public var id: String { source.id }
    public fileprivate(set) var phase: LiveTVImportPhase = .idle
    public fileprivate(set) var failure: LiveTVSourceImportError?
    public fileprivate(set) var matchedChannelCount = 0
    public fileprivate(set) var programCount = 0
    public fileprivate(set) var lastRefresh: Date?
}

public struct LiveTVPlaylistSourceStatus: Identifiable, Equatable, Sendable {
    public let source: LiveTVPlaylistSource
    public var id: String { source.id }
    public fileprivate(set) var phase: LiveTVImportPhase = .idle
    public fileprivate(set) var failure: LiveTVSourceImportError?
    public fileprivate(set) var entryCount = 0
    public fileprivate(set) var skippedEntryCount = 0
    public fileprivate(set) var channelCount = 0
    public fileprivate(set) var lastRefresh: Date?
}

public enum LiveTVGuideGapState: Equatable, Sendable {
    case loading, disabled, failed, unmatched, noListings, unrequested

    public var title: LocalizedStringResource {
        switch self {
        case .loading: "Loading guide..."
        case .disabled: "No program guide available"
        case .failed: "Guide update failed"
        case .unmatched: "No matching program guide"
        case .noListings: "No listings for this time"
        case .unrequested: "Guide not loaded for this time"
        }
    }
}

@MainActor
@Observable
public final class LiveTVPrototypeImportModel {
    public private(set) var configuration: LiveTVSourcesConfiguration
    public private(set) var playlistSources: [LiveTVPlaylistSourceStatus]
    public internal(set) var serverSources: [LiveTVServerSourceStatus] = []
    public internal(set) var serverGuideWindows: [LiveTVServerGuideWindowStatus] = []
    public var playlistURL: URL? { configuration.playlists.first?.playlistURL }
    public private(set) var guideSources: [LiveTVGuideSourceStatus]
    public private(set) var enabledSourceIDs: Set<String>
    public private(set) var selectedSourceByChannel: [String: String] = [:]
    public private(set) var playlistSourceIDByChannel: [String: String] = [:]
    public private(set) var configuredSourceIDByChannel: [String: String] = [:]
    public private(set) var serverChannelReferences: [String: LiveTVServerChannelReference] = [:]
    public private(set) var playlistPhase: LiveTVImportPhase = .idle
    public private(set) var guidePhase: LiveTVImportPhase = .idle
    public private(set) var playlistFailure: LiveTVSourceImportError?
    public private(set) var guideFailure: LiveTVSourceImportError?
    public var entryCount: Int {
        playlistSources.filter(\.source.isEnabled).reduce(0) { $0 + $1.entryCount }
    }
    public var skippedEntryCount: Int {
        playlistSources.filter(\.source.isEnabled).reduce(0) { $0 + $1.skippedEntryCount }
    }
    public private(set) var guideChannelCount = 0
    public private(set) var matchedChannelCount = 0
    public private(set) var programCount = 0
    public private(set) var coverageStart: Date?
    public private(set) var coverageEnd: Date?
    public private(set) var lastGuideRefresh: Date?

    @ObservationIgnored private let loader: any LiveTVSourceLoading
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var cachedGuides: [String: LiveTVGuideImport] = [:]
    @ObservationIgnored private var cachedPlaylists: [String: LiveTVPlaylistImport] = [:]
    @ObservationIgnored private var disabledGuideIDs: Set<String> = []
    @ObservationIgnored private var legacySourceID: String?
    @ObservationIgnored private var sourceChannels: [LiveTVPrototypeChannel] = []
    @ObservationIgnored private var reloadGeneration = 0
    @ObservationIgnored var serverRevision = 0
    @ObservationIgnored var serverSourceRevisions: [String: Int] = [:]
    @ObservationIgnored var cachedServerCatalogs: [String: LiveTVServerCatalog] = [:]
    @ObservationIgnored var serverProviderResolver: LiveTVServerProviderResolver = { _ in nil }
    @ObservationIgnored var activeServerGuideRequests: Set<UUID> = []

    public var isLoading: Bool {
        playlistPhase == .loading || guidePhase == .loading
            || serverSources.contains { $0.phase == .loading || $0.guidePhase == .loading }
    }
    public var catalogPhase: LiveTVImportPhase {
        let phases = playlistSources.filter(\.source.isEnabled).map(\.phase)
            + serverSources.filter(\.source.isEnabled).map(\.phase)
        if phases.contains(.loading) { return .loading }
        if phases.contains(.loaded) { return .loaded }
        if phases.contains(.failed) { return .failed }
        return .idle
    }
    public var failedSourceCount: Int {
        guideSources.filter { enabledSourceIDs.contains($0.id) && $0.phase == .failed }.count
    }
    public var completedSourceCount: Int {
        guideSources.filter {
            enabledSourceIDs.contains($0.id) && ($0.phase == .loaded || $0.phase == .failed)
        }.count
    }

    public init(
        configuration: LiveTVSourcesConfiguration = .empty,
        loader: any LiveTVSourceLoading = LiveTVSourceLoader(),
        serverProviderResolver: @escaping LiveTVServerProviderResolver = { _ in nil }
    ) {
        self.configuration = configuration
        playlistSources = configuration.playlists.map { LiveTVPlaylistSourceStatus(source: $0) }
        serverSources = configuration.servers.map { LiveTVServerSourceStatus(source: $0) }
        let sources = configuration.playlists.flatMap { playlist in
            LiveTVConfiguredSources.guides(for: playlist).map {
                LiveTVGuideSourceStatus(source: $0, playlistSourceID: playlist.id)
            }
        }
        guideSources = sources
        let enabledPlaylists = Set(configuration.playlists.filter(\.isEnabled).map(\.id))
        enabledSourceIDs = Set(sources.filter { enabledPlaylists.contains($0.playlistSourceID) }.map(\.id))
        self.loader = loader
        self.serverProviderResolver = serverProviderResolver
    }

    /// Legacy fixture/prototype initializer. Production must pass explicit profile configuration.
    public init(
        playlistURL: URL,
        guideURL: URL? = nil,
        sources: [LiveTVGuideSource] = [],
        loader: any LiveTVSourceLoading = LiveTVSourceLoader()
    ) {
        let sources = guideURL.map {
            [LiveTVGuideSource(id: "guide", name: "XMLTV", url: $0, provider: LiveTVGuideSource.provider(for: $0))]
        } ?? sources
        precondition(Set(sources.map(\.id)).count == sources.count, "Guide source IDs must be unique.")
        let playlist = LiveTVPlaylistSource(
            id: "prototype", name: "IPTV", playlistURL: playlistURL, guideURLs: sources.map(\.url)
        )
        configuration = LiveTVSourcesConfiguration(playlists: [playlist])
        playlistSources = [LiveTVPlaylistSourceStatus(source: playlist)]
        legacySourceID = playlist.id
        guideSources = sources.map { LiveTVGuideSourceStatus(source: $0, playlistSourceID: playlist.id) }
        enabledSourceIDs = Set(sources.map(\.id))
        self.loader = loader
    }

    public func applyConfiguration(
        _ configuration: LiveTVSourcesConfiguration, into model: LiveTVPrototypeModel
    ) throws {
        try configuration.validate()
        guard self.configuration != configuration || legacySourceID != nil
            || (configuration.playlists.allSatisfy({ !$0.isEnabled })
                && configuration.servers.allSatisfy({ !$0.isEnabled })) else { return }
        reloadGeneration &+= 1
        applyServerConfiguration(configuration.servers)
        let enabledConfiguredIDs = Set(
            configuration.playlists.filter(\.isEnabled).map(\.id)
                + configuration.servers.filter(\.isEnabled).map(\.id)
        )
        if let selected = model.configuredSourceID, !enabledConfiguredIDs.contains(selected) {
            model.configuredSourceID = nil
        }
        if self.configuration.playlists == configuration.playlists, legacySourceID == nil {
            self.configuration = configuration
            try publishPlaylists(into: model)
            return
        }
        revision &+= 1
        let previousPlaylists = playlistSources.reduce(into: [String: LiveTVPlaylistSourceStatus]()) {
            $0[$1.id] = $1
        }
        let previousGuides = guideSources.reduce(into: [String: LiveTVGuideSourceStatus]()) {
            $0[$1.id] = $1
        }
        let retainedIDs = Set(configuration.playlists.filter {
            $0.isEnabled && previousPlaylists[$0.id]?.source.playlistURL == $0.playlistURL
                && $0.id != legacySourceID
        }.map(\.id))
        cachedPlaylists = cachedPlaylists.filter { retainedIDs.contains($0.key) }
        self.configuration = configuration
        legacySourceID = nil
        playlistSources = configuration.playlists.map { source in
            var status = LiveTVPlaylistSourceStatus(source: source)
            if retainedIDs.contains(source.id), let previous = previousPlaylists[source.id] {
                status.phase = previous.phase == .loading ? .idle : previous.phase
                status.failure = previous.failure
                status.entryCount = previous.entryCount
                status.skippedEntryCount = previous.skippedEntryCount
                status.channelCount = previous.channelCount
                status.lastRefresh = previous.lastRefresh
            }
            return status
        }
        guideSources = configuration.playlists.flatMap { playlist in
            LiveTVConfiguredSources.guides(for: playlist).map { source in
                var status = LiveTVGuideSourceStatus(source: source, playlistSourceID: playlist.id)
                if retainedIDs.contains(playlist.id), let previous = previousGuides[source.id] {
                    status.phase = previous.phase == .loading ? .idle : previous.phase
                    status.failure = previous.failure
                    status.matchedChannelCount = previous.matchedChannelCount
                    status.programCount = previous.programCount
                    status.lastRefresh = previous.lastRefresh
                }
                return status
            }
        }
        let enabledPlaylists = Set(configuration.playlists.filter(\.isEnabled).map(\.id))
        disabledGuideIDs.formIntersection(Set(guideSources.map(\.id)))
        enabledSourceIDs = Set(guideSources.filter {
            enabledPlaylists.contains($0.playlistSourceID) && !disabledGuideIDs.contains($0.id)
        }.map(\.id))
        let retainedGuides = Set(guideSources.filter {
            retainedIDs.contains($0.playlistSourceID) && enabledSourceIDs.contains($0.id)
        }.map(\.id))
        cachedGuides = cachedGuides.filter { retainedGuides.contains($0.key) }
        lastGuideRefresh = guideSources.filter { cachedGuides[$0.id] != nil }.compactMap(\.lastRefresh).max()
        playlistFailure = nil
        guideFailure = nil
        try publishPlaylists(into: model)
        updatePhases()
    }

    public func setPlaylistEnabled(
        _ sourceID: String, enabled: Bool, into model: LiveTVPrototypeModel
    ) throws {
        guard let index = configuration.playlists.firstIndex(where: { $0.id == sourceID }) else {
            throw LiveTVSourcesValidationError.invalidSourceID
        }
        var updated = configuration
        updated.playlists[index].isEnabled = enabled
        try applyConfiguration(updated, into: model)
    }

    public func setSourceEnabled(_ sourceID: String, enabled: Bool, into model: LiveTVPrototypeModel) throws {
        guard let source = guideSources.first(where: { $0.id == sourceID }),
              !enabled || configuration.playlists.contains(where: { $0.id == source.playlistSourceID && $0.isEnabled })
        else {
            throw LiveTVSourceImportError.invalidGuide
        }
        guard enabledSourceIDs.contains(sourceID) != enabled else { return }
        if enabled {
            enabledSourceIDs.insert(sourceID)
            disabledGuideIDs.remove(sourceID)
        }
        else {
            enabledSourceIDs.remove(sourceID)
            disabledGuideIDs.insert(sourceID)
            cachedGuides.removeValue(forKey: sourceID)
        }
        // Fence in-flight results immediately, before SwiftUI starts the replacement task.
        revision &+= 1
        for index in playlistSources.indices where playlistSources[index].phase == .loading {
            playlistSources[index].phase = .idle
        }
        if playlistPhase == .loading { playlistPhase = .idle }
        for index in guideSources.indices where guideSources[index].phase == .loading {
            guideSources[index].phase = .idle
        }
        guidePhase = enabledSourceIDs.isEmpty ? .idle : .loading
        try publishGuides(into: model)
    }

    public func gapState(for channel: LiveTVPrototypeChannel) -> LiveTVGuideGapState {
        if let reference = serverChannelReferences[channel.id],
           let status = serverSources.first(where: { $0.id == reference.sourceID }) {
            if status.phase == .loading { return .loading }
            if status.failure != nil || status.guideFailure == .permissionDenied { return .failed }
            if status.availability?.supportsGuide == false { return .disabled }
            guard let window = serverGuideWindows.last(where: {
                $0.sourceID == reference.sourceID && $0.channelIDs.contains(channel.id)
            }) else { return .unrequested }
            return serverGuideState(channelID: channel.id, from: window.from, to: window.to)
        }
        let owner = playlistSourceIDByChannel[channel.id]
        let enabledGuides = guideSources.filter {
            enabledSourceIDs.contains($0.id) && (owner == nil || $0.playlistSourceID == owner)
        }
        if enabledGuides.isEmpty { return .disabled }
        if selectedSourceByChannel[channel.id] != nil { return .noListings }
        if playlistPhase == .idle || playlistPhase == .loading || guidePhase == .loading { return .loading }
        let provider = LiveTVStreamIdentity(url: channel.streamURL).provider
        let relevant = enabledGuides.filter { $0.source.provider == provider }
        if relevant.contains(where: { $0.phase == .failed }) { return .failed }
        return .unmatched
    }

    public func reload(into model: LiveTVPrototypeModel) async {
        reloadGeneration &+= 1
        let request = reloadGeneration
        await reloadPlaylists(into: model)
        guard request == reloadGeneration, !Task.isCancelled else { return }
        await reloadServers(into: model)
    }

    private func reloadPlaylists(into model: LiveTVPrototypeModel) async {
        revision &+= 1
        let request = revision
        do {
            try configuration.validate()
        } catch {
            playlistPhase = .failed
            playlistFailure = .invalidPlaylist
            guidePhase = .idle
            return
        }
        let enabledPlaylists = playlistSources.filter { $0.source.isEnabled }
        guard !enabledPlaylists.isEmpty else {
            cachedPlaylists = [:]
            cachedGuides = [:]
            playlistFailure = nil
            guideFailure = nil
            lastGuideRefresh = nil
            do { try publishPlaylists(into: model) }
            catch { playlistFailure = .invalidPlaylist }
            playlistPhase = .idle
            guidePhase = .idle
            return
        }
        guidePhase = enabledSourceIDs.isEmpty ? .idle : .loading
        for index in guideSources.indices where guideSources[index].phase == .loading {
            guideSources[index].phase = .idle
        }
        playlistPhase = .loading
        playlistFailure = nil
        guideFailure = nil
        for index in playlistSources.indices {
            playlistSources[index].phase = .idle
            playlistSources[index].failure = nil
        }
        for index in playlistSources.indices where playlistSources[index].source.isEnabled {
            guard revision == request else { return }
            let source = playlistSources[index].source
            playlistSources[index].phase = .loading
            do {
                try Task.checkCancellation()
                let imported = try await loader.loadPlaylist(from: source.playlistURL)
                try Task.checkCancellation()
                guard revision == request else { return }
                let playlist = source.id == legacySourceID ? imported : LiveTVConfiguredSources.scope(
                    imported, to: source.id, preservesChannelIDs: preservesChannelIDs(for: source.id)
                )
                let previous = cachedPlaylists[source.id]
                cachedPlaylists[source.id] = playlist
                do {
                    try publishPlaylists(into: model)
                } catch {
                    cachedPlaylists[source.id] = previous
                    throw error
                }
                playlistSources[index].entryCount = playlist.entryCount
                playlistSources[index].skippedEntryCount = playlist.skippedEntryCount
                playlistSources[index].channelCount = playlist.channels.count
                playlistSources[index].lastRefresh = Date()
                playlistSources[index].phase = .loaded
            } catch {
                guard revision == request else { return }
                if isCancellation(error) {
                    playlistSources[index].phase = .idle
                    playlistPhase = .idle
                    guidePhase = .idle
                    return
                }
                let failure = error as? LiveTVSourceImportError ?? .invalidPlaylist
                playlistSources[index].failure = failure
                playlistSources[index].phase = .failed
                playlistFailure = failure
            }
        }
        playlistPhase = playlistSources.contains { $0.source.isEnabled && $0.phase == .loaded }
            ? .loaded : .failed

        let loadedPlaylists = Set(playlistSources.filter { $0.phase == .loaded }.map(\.id))
        for index in guideSources.indices {
            guideSources[index].phase = cachedGuides[guideSources[index].id] == nil ? .idle : .loaded
            guideSources[index].failure = nil
        }
        let now = Date()
        for index in guideSources.indices where enabledSourceIDs.contains(guideSources[index].id)
            && loadedPlaylists.contains(guideSources[index].playlistSourceID) {
            guard revision == request else { return }
            let source = guideSources[index].source
            let owner = guideSources[index].playlistSourceID
            let channels = cachedPlaylists[owner]?.channels ?? []
            guideSources[index].phase = .loading
            do {
                try Task.checkCancellation()
                let imported = try await loader.loadGuide(from: source.url, channels: channels, now: now)
                try Task.checkCancellation()
                guard revision == request else { return }
                let guide = preservesChannelIDs(for: owner)
                    ? imported : LiveTVConfiguredSources.scope(imported, to: owner)
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
                if isCancellation(error) {
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
        updateGuidePhase()
    }

    private func preservesChannelIDs(for sourceID: String) -> Bool {
        sourceID == legacySourceID || sourceID == "free-us"
    }

    func isCancellation(_ error: any Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? LiveTVSourceImportError) == .cancelled
    }

    private func updatePhases() {
        let enabled = playlistSources.filter { $0.source.isEnabled }
        if enabled.contains(where: { $0.phase == .loaded }) { playlistPhase = .loaded }
        else if !enabled.isEmpty, enabled.allSatisfy({ $0.phase == .failed }) { playlistPhase = .failed }
        else { playlistPhase = .idle }
        updateGuidePhase()
    }

    private func updateGuidePhase() {
        let enabled = guideSources.filter { enabledSourceIDs.contains($0.id) }
        if enabled.contains(where: { $0.phase == .loaded }) { guidePhase = .loaded }
        else if enabled.contains(where: { $0.phase == .failed }) { guidePhase = .failed }
        else { guidePhase = .idle }
    }

    func publishPlaylists(into model: LiveTVPrototypeModel) throws {
        let playlists = playlistSources.filter(\.source.isEnabled).compactMap { status in
            cachedPlaylists[status.id].map { (status.id, $0) }
        }
        let servers = serverSources.filter(\.source.isEnabled).compactMap { cachedServerCatalogs[$0.id] }
        guard playlists.reduce(0, { $0 + $1.1.channels.count }) + servers.reduce(0, { $0 + $1.channels.count })
            <= LiveTVPlaylistParser.maximumEntries else {
            throw LiveTVSourceImportError.responseTooLarge
        }
        let channels = playlists.flatMap { $0.1.channels } + servers.flatMap(\.channels)
        try model.replaceChannels(channels)
        sourceChannels = channels
        playlistSourceIDByChannel = Dictionary(uniqueKeysWithValues: playlists.flatMap { sourceID, playlist in
            playlist.channels.map { ($0.id, sourceID) }
        })
        serverChannelReferences = servers.reduce(into: [:]) { result, catalog in
            result.merge(catalog.references) { current, _ in current }
        }
        configuredSourceIDByChannel = playlistSourceIDByChannel.merging(
            serverChannelReferences.mapValues(\.sourceID)
        ) { current, _ in current }
        try publishGuides(into: model)
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
            let ownedChannelIDs = channelIDs.filter { playlistSourceIDByChannel[$0] == status.playlistSourceID }
            let matchedIDs = Set(guide.matches.keys).union(grouped.keys).intersection(ownedChannelIDs)
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
        let nativePrograms = serverSources.filter(\.source.isEnabled)
            .compactMap { cachedServerCatalogs[$0.id] }.flatMap(\.programs)
        let programs = chosen.values.flatMap(\.programs) + nativePrograms
        guard programs.count <= LiveTVXMLTVParser.maximumRetainedPrograms else {
            throw LiveTVSourceImportError.guideTooLarge
        }
        try model.replacePrograms(programs)
        selectedSourceByChannel = chosen.mapValues(\.sourceID)
        guideChannelCount = channelCount
        matchedChannelCount = chosen.count + Set(nativePrograms.map(\.channelID)).count
        programCount = programs.count
        coverageStart = programs.map(\.start).min()
        coverageEnd = programs.map(\.end).max()
    }

    func validateCacheBudget() throws {
        var count = 0
        var textBytes = 0
        let sources = cachedGuides.values.map(\.programs) + cachedServerCatalogs.values.map(\.programs)
        for programs in sources {
            count += programs.count
            guard count <= LiveTVXMLTVParser.maximumRetainedPrograms else {
                throw LiveTVSourceImportError.guideTooLarge
            }
            for program in programs {
                textBytes += program.title.utf8.count + program.subtitle.utf8.count
                guard textBytes <= LiveTVXMLTVParser.maximumRetainedTextBytes else {
                    throw LiveTVSourceImportError.guideTooLarge
                }
            }
        }
    }
}
#endif
