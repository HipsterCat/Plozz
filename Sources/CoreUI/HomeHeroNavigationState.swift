#if canImport(SwiftUI)
import SwiftUI

/// Tracks the visible Home region, not focus: opening navigation must not make
/// a still-visible hero switch back to the pinned icon rail.
public enum HomeHeroNavigationState: Equatable, Sendable {
    case absent
    case hero
    case content

    public static func resolve(hasHero: Bool, isReceded: Bool) -> Self {
        guard hasHero else { return .absent }
        return isReceded ? .content : .hero
    }
}

public struct HomeHeroNavigationPreference: PreferenceKey {
    public static var defaultValue: HomeHeroNavigationState { .absent }

    public static func reduce(
        value: inout HomeHeroNavigationState,
        nextValue: () -> HomeHeroNavigationState
    ) {
        let next = nextValue()
        if next != .absent { value = next }
    }
}
#endif
