/// The two independent capabilities offered by a show's download sheet.
public struct SeriesDownloadPresentation: Equatable, Sendable {
    public let hasLibraryDownloads: Bool
    public let canRequestSeasons: Bool

    public var isVisible: Bool { hasLibraryDownloads || canRequestSeasons }

    public init(
        item: MediaItem,
        children: [MediaItem],
        isDiscoveryItem: Bool,
        seerConnected: Bool
    ) {
        hasLibraryDownloads = item.kind == .series
            && !isDiscoveryItem
            && children.contains { $0.kind == .season || $0.kind == .episode }
        canRequestSeasons = item.kind == .series
            && item.providerIDs["Tmdb"] != nil
            && seerConnected
    }
}
