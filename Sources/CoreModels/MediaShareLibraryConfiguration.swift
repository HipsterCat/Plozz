import Foundation

/// Non-secret instructions describing how one network-share root should be
/// presented and indexed.
///
/// The configuration is optional on ``MediaServer`` so accounts written before
/// this feature continue to decode and retain the legacy automatic behavior.
public struct MediaShareLibraryConfiguration: Codable, Hashable, Sendable {
    public enum ContentType: String, Codable, Hashable, CaseIterable, Sendable {
        /// Infer movies and episodic content from the selected root and filenames.
        case automatic
        /// Treat playable files as movies, even when their names contain episode-like tokens.
        case movies
        /// Index files with episode evidence as television episodes.
        case tvShows
        /// Keep files browsable and playable without external movie/show matching.
        case personalVideos
    }

    /// User-visible name for the selected library root.
    public var name: String
    public var contentType: ContentType
    /// Anime is an independent metadata context, not a movie-vs-episode choice.
    public var isAnime: Bool

    public init(
        name: String,
        contentType: ContentType = .automatic,
        isAnime: Bool = false
    ) {
        self.name = name
        self.contentType = contentType
        self.isAnime = isAnime
    }
}
