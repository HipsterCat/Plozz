import Foundation

/// Original-file facts retained for previews and source metadata. The selected
/// PlaybackRequest source, not this descriptor, owns the playback rendition.
public struct LocalRemuxSourceDescriptor: Hashable, Sendable {
    public var itemID: String
    public var mediaSourceID: String?
    public var provider: ProviderKind
    /// Credential-free original range-readable media bytes.
    public var originalSource: PlaybackSource
    public var referencePlaybackSource: PlaybackSource?
    public var durationSeconds: TimeInterval?
    public var byteRangeSupported: Bool
    public var sourceMetadata: MediaSourceMetadata

    public init(
        itemID: String,
        mediaSourceID: String? = nil,
        provider: ProviderKind,
        originalSource: PlaybackSource,
        referencePlaybackSource: PlaybackSource? = nil,
        durationSeconds: TimeInterval? = nil,
        byteRangeSupported: Bool = true,
        sourceMetadata: MediaSourceMetadata
    ) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.provider = provider
        self.originalSource = originalSource
        self.referencePlaybackSource = referencePlaybackSource
        self.durationSeconds = durationSeconds
        self.byteRangeSupported = byteRangeSupported
        self.sourceMetadata = sourceMetadata
    }

    /// Explicit provider metadata wins. A display-only DOVI label does not
    /// establish a profile; only the provider's specific VideoRangeType does.
    public var normalizedDolbyVisionProfile: Int? {
        if let explicit = sourceMetadata.video?.dolbyVisionProfile { return explicit }
        switch (sourceMetadata.video?.videoRangeType ?? "").uppercased() {
        case "DOVIWITHHDR10", "DOVIWITHHLG", "DOVIWITHSDR": return 8
        case "DOVI": return 5
        default: return nil
        }
    }
}
