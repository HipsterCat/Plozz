import Foundation

public struct OfflinePlaybackAsset: Sendable {
    public let fileURL: URL
    public let subtitleTracks: [MediaTrack]
    public let metadata: MediaSourceMetadata?

    public init(fileURL: URL, subtitleTracks: [MediaTrack] = [], metadata: MediaSourceMetadata? = nil) {
        self.fileURL = fileURL
        self.subtitleTracks = subtitleTracks
        self.metadata = metadata
    }
}

/// Leaf seam that lets the playback layer ask "is there a completed offline
/// download for this item, and if so where is its local file?" WITHOUT taking a
/// dependency on the `MediaDownloads` module.
///
/// It lives in `CoreModels` (the graph leaf) on purpose: `FeaturePlayback`
/// already imports `CoreModels`, so injecting a resolver adds **no** new module
/// edge and keeps the layering clean (arch-guard green). The concrete
/// implementation (backed by the download registry) is provided by
/// `MediaDownloads` and wired in at the app layer.
///
/// The contract is deliberately tiny and additive: a `nil` return means "no
/// usable local copy" and the caller must behave exactly as if no resolver were
/// present. Implementations must only return a URL for a **completed** download
/// whose file actually exists on disk.
public protocol OfflinePlaybackResolving: Sendable {
    /// A completed, on-disk copy of `item` in the active profile, matched across
    /// servers. Prefer `versionID` when it is available locally, otherwise use
    /// another downloaded version before allowing server playback. A nil/empty
    /// version has no preference. Return nil only when no usable copy exists.
    /// Subtitles and metadata must come from the same selected local file.
    func localPlaybackURL(for item: MediaItem, versionID: String?) async -> URL?
    /// Resolve the file and its sidecars together so a concurrently completed
    /// version cannot replace the metadata of a file already selected to play.
    func localPlaybackAsset(for item: MediaItem, versionID: String?) async -> OfflinePlaybackAsset?
    func localSubtitleTracks(for item: MediaItem, versionID: String?) async -> [MediaTrack]
    func localPlaybackMetadata(for item: MediaItem, versionID: String?) async -> MediaSourceMetadata?
}

public extension OfflinePlaybackResolving {
    func localPlaybackAsset(for item: MediaItem, versionID: String?) async -> OfflinePlaybackAsset? {
        guard let url = await localPlaybackURL(for: item, versionID: versionID) else { return nil }
        return await OfflinePlaybackAsset(
            fileURL: url,
            subtitleTracks: localSubtitleTracks(for: item, versionID: versionID),
            metadata: localPlaybackMetadata(for: item, versionID: versionID)
        )
    }

    func localSubtitleTracks(for item: MediaItem, versionID: String?) async -> [MediaTrack] { [] }
    func localPlaybackMetadata(for item: MediaItem, versionID: String?) async -> MediaSourceMetadata? { nil }

    /// Version-agnostic convenience for availability checks.
    func localPlaybackURL(for item: MediaItem) async -> URL? {
        await localPlaybackURL(for: item, versionID: nil)
    }
}
