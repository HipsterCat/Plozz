import Foundation

/// The member selected from a server playlist. The grid's index is the server's
/// authored order; the item ID alone is not sufficient when entries repeat.
public struct VideoPlaylistPlaybackOrigin: Hashable, Sendable {
    public let playlistID: String
    public let accountID: String
    public let index: Int
    public let totalCount: Int
    public let item: MediaItem

    public init(playlistID: String, accountID: String, index: Int, totalCount: Int, item: MediaItem) {
        self.playlistID = playlistID
        self.accountID = accountID
        self.index = index
        self.totalCount = totalCount
        self.item = item
    }

    /// Playing another episode from the series page is not playing the selected
    /// playlist entry, even if it happens to come from the same account.
    public func containsSelection(_ item: MediaItem) -> Bool {
        item.id == self.item.id && item.sourceAccountID == accountID
    }
}
