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

@MainActor
@Observable
public final class LiveTVPrototypeImportModel {
    public let playlistURL: URL
    public let guideURL: URL
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

    public var isLoading: Bool { playlistPhase == .loading || guidePhase == .loading }

    public init(
        playlistURL: URL = URL(string: "https://iptv-org.github.io/iptv/countries/us.m3u")!,
        guideURL: URL = URL(string: "https://epgshare01.online/epgshare01/epg_ripper_US2.xml.gz")!,
        loader: any LiveTVSourceLoading = LiveTVSourceLoader()
    ) {
        self.playlistURL = playlistURL
        self.guideURL = guideURL
        self.loader = loader
    }

    public func reload(into model: LiveTVPrototypeModel) async {
        revision += 1
        let request = revision
        var sourceChannels: [LiveTVPrototypeChannel] = []
        if guidePhase == .loading {
            guidePhase = lastGuideRefresh == nil ? .idle : .loaded
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
        } catch {
            guard revision == request else { return }
            playlistFailure = error as? LiveTVSourceImportError ?? .invalidPlaylist
            playlistPhase = Task.isCancelled ? .idle : .failed
            return
        }

        guidePhase = .loading
        guideFailure = nil
        do {
            let guide = try await loader.loadGuide(
                from: guideURL, channels: sourceChannels, now: Date()
            )
            try Task.checkCancellation()
            guard revision == request else { return }
            try model.replacePrograms(guide.programs)
            guideChannelCount = guide.guideChannelCount
            matchedChannelCount = guide.matchedChannelCount
            programCount = guide.programCount
            coverageStart = guide.coverageStart
            coverageEnd = guide.coverageEnd
            lastGuideRefresh = Date()
            guidePhase = .loaded
        } catch {
            guard revision == request else { return }
            guideFailure = error as? LiveTVSourceImportError ?? .invalidGuide
            guidePhase = Task.isCancelled ? .idle : .failed
        }
    }
}
#endif
