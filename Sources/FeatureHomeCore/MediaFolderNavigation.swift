import CoreModels

public enum MediaFolderNavigation {
    /// Filesystem containers keep their own hierarchy; catalog-resolved titles
    /// already have a movie/series/season kind and follow ordinary detail routing.
    public static func library(
        for item: MediaItem,
        providerKind: ProviderKind,
        sourceAccountID: String? = nil
    ) -> MediaLibrary? {
        guard providerKind == .mediaShare, item.kind == .folder else { return nil }
        return MediaLibrary(
            id: item.id,
            title: item.title,
            kind: .folder,
            sourceAccountID: sourceAccountID ?? item.sourceAccountID
        )
    }
}
