import Foundation

/// The kinds of content a Home **hero** carousel can source from (pure data
/// model). Ordered, per-profile-configurable, and additive: a new source is a
/// new case plus its curation branch, never a rewrite of the hero.
///
/// Featured combines configured external discovery feeds. Seerr is optional
/// and supplies request/availability context rather than deciding every pick.
public enum HeroSourceKind: String, CaseIterable, Identifiable, Codable, Sendable {
    /// External discovery picks, matched to the user's own copies when available.
    case featured
    /// Your in-progress, resumable titles presented in a featured format.
    case continueWatching
    /// The newest titles to land in your libraries.
    case recentlyAdded
    /// Random picks from your (chosen) libraries.
    case randomFromLibrary
    /// Titles you've saved to your watchlist.
    case watchlist
    /// Movies and shows from collections selected for this profile.
    case collection

    public var id: String { rawValue }

    /// User-facing label for the Settings source picker.
    public var displayName: LocalizedStringResource {
        switch self {
        case .featured:
            return LocalizedStringResource(
                "heroSource.discovery",
                defaultValue: "Discovery",
                comment: "Home content source: recommendations from external catalogs, not necessarily in the user's libraries."
            )
        case .continueWatching:
            return LocalizedStringResource(
                "heroSource.continueWatching",
                defaultValue: "Continue Watching",
                comment: "Home hero content-source option in Settings."
            )
        case .recentlyAdded:
            return LocalizedStringResource(
                "heroSource.recentlyAdded",
                defaultValue: "Recently Added",
                comment: "Home hero content-source option in Settings."
            )
        case .randomFromLibrary:
            return LocalizedStringResource(
                "heroSource.randomFromLibrary",
                defaultValue: "Random from Library",
                comment: "Home hero content-source option in Settings."
            )
        case .watchlist:
            return LocalizedStringResource(
                "heroSource.watchlist",
                defaultValue: "Watchlist",
                comment: "Home hero content-source option in Settings."
            )
        case .collection:
            return LocalizedStringResource("Collections", comment: "Home hero content-source option in Settings.")
        }
    }

    /// One-line explanation shown under the option in Settings.
    public var detail: LocalizedStringResource {
        switch self {
        case .featured:
            return LocalizedStringResource(
                "Recommendations from external catalogs. Titles may not be in your libraries.",
                comment: "Explanation of the Discovery source in Home settings."
            )
        case .continueWatching:
            return LocalizedStringResource(
                "Pick up where you left off, front and centre.",
                comment: "Explanation shown under the Continue Watching hero source option in Settings."
            )
        case .recentlyAdded:
            return LocalizedStringResource(
                "The newest additions to your libraries, shown large.",
                comment: "Explanation shown under the Recently Added hero source option in Settings."
            )
        case .randomFromLibrary:
            return LocalizedStringResource(
                "A rotating spotlight on titles from your libraries.",
                comment: "Explanation shown under the Random from Library hero source option in Settings."
            )
        case .watchlist:
            return LocalizedStringResource(
                "Titles you've saved to watch later.",
                comment: "Explanation shown under the Watchlist hero source option in Settings."
            )
        case .collection:
            return LocalizedStringResource(
                "Movies and shows from your selected collections, across libraries.",
                comment: "Explanation of the Collections hero source."
            )
        }
    }

    /// SF Symbol shown next to the option in Settings.
    public var symbolName: String {
        switch self {
        case .featured: return "sparkles.tv"
        case .continueWatching: return "play.circle"
        case .recentlyAdded: return "sparkles"
        case .randomFromLibrary: return "shuffle"
        case .watchlist: return "bookmark"
        case .collection: return "rectangle.stack"
        }
    }

    /// Whether this source draws from local library content (as opposed to the
    /// external `.featured` feeds). Used by the curator to know which
    /// sources depend on already-aggregated Home content vs. an injected fetch.
    public var isLibrarySourced: Bool {
        self != .featured
    }
}
