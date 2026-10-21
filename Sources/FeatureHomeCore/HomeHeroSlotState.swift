import CoreModels

/// Reserves Hero geometry only while configured content is pending or available.
public enum HomeHeroSlotState: Equatable, Sendable {
    case hidden
    case placeholder
    case content

    public static func resolve(
        isConfigured: Bool,
        hasItems: Bool,
        recomputeComplete: Bool
    ) -> Self {
        guard isConfigured else { return .hidden }
        if hasItems { return .content }
        return recomputeComplete ? .hidden : .placeholder
    }

    public static func resolve(
        settings: HeroSettings,
        hasItems: Bool,
        recomputeComplete: Bool
    ) -> Self {
        let hasConfiguredSource = settings.sources.contains { source in
            switch source {
            case .collection: !settings.collections.isEmpty
            case .featured: !settings.discoverySources.isEmpty
            case .continueWatching, .recentlyAdded, .randomFromLibrary, .watchlist: true
            }
        }
        return resolve(
            isConfigured: settings.isActive && hasConfiguredSource,
            hasItems: hasItems,
            recomputeComplete: recomputeComplete
        )
    }
}
