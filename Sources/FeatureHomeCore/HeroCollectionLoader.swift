import CoreModels
import Foundation

/// Samples a bounded window, retaining the server's order within that window.
public enum HeroCollectionLoader {
    public static func load(
        selection: HeroCollectionSelection,
        limit: Int,
        provider: any MediaProvider,
        visibility: HomeLibraryVisibility,
        seed: UInt64 = 0
    ) async throws -> MediaPage {
        try await CollectionPreviewLoader.load(
            selection: selection, limit: min(limit, HeroFreshnessSnapshot.rawDiscoveryLimit),
            provider: provider, visibility: visibility, seed: seed
        )
    }
}
