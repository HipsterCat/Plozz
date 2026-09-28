import CoreModels

/// A concrete server collection or video playlist's members.
public struct CollectionBrowseRoute: Hashable, Sendable {
    public let collectionID: String
    public let title: String // l10n:content — collection name from the server
    public let accountID: String?
    public let kind: MediaItemKind

    public init?(item: MediaItem, fallbackAccountID: String? = nil) {
        guard item.kind == .collection || item.kind == .playlist else { return nil }
        collectionID = item.id
        title = item.title
        accountID = item.sourceAccountID ?? fallbackAccountID
        kind = item.kind
    }
}
