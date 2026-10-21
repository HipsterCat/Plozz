import TVServices

/// Supplies content for the tvOS Top Shelf — the banner shown above the app
/// grid when Plozz is in the top row of the Home screen.
///
/// This runs in a separate, short-lived, memory-constrained process. Rather
/// than re-implement the Jellyfin client (and its Keychain auth) here, it
/// renders the snapshot the main app last published into the shared App Group
/// container. Jellyfin image URLs are token-free and absolute, so the shelf
/// cards load their artwork directly. Each card deep-links back into the app to
/// start playback (`plozz://item/{id}`).
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(
        completionHandler: @escaping (TVTopShelfContent?) -> Void
    ) {
        completionHandler(Self.makeContent())
    }

    private static func makeContent() -> TVTopShelfContent? {
        guard let snapshot = TopShelfStore.load() else { return nil }
        return TopShelfContentBuilder.makeContent(from: snapshot)
    }
}
