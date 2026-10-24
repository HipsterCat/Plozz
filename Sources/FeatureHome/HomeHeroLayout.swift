#if canImport(SwiftUI)
import SwiftUI
import PlozzCoreUI
import CoreModels
#if canImport(UIKit)
import UIKit
#endif

/// Shared geometry for the Home **hero** so the real hero (`HomeHeroView`), the
/// Home layout that pulls the rows up under it (`HomeView`), and the loading
/// **skeleton** (`HomeSkeletonView`) all read from ONE source of truth. Without
/// this, the skeleton's placeholder positions and the Continue-Watching "peek"
/// would silently drift out of alignment with the loaded hero whenever a value is
/// tuned in one place but not the others.
enum HomeHeroLayout {
    /// Full-screen hero height — the backdrop fills the display top-to-bottom.
    static var screenHeight: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.bounds.height
        #else
        1080
        #endif
    }

    /// Full-screen hero width.
    static var screenWidth: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.bounds.width
        #else
        1920
        #endif
    }

    /// Distance the hero content column (logo / metadata / overview / buttons /
    /// dots) is lifted off the bottom edge of the full-screen hero, so it sits in
    /// the lower third — paired with ``rowOverlap`` to land Continue Watching just
    /// beneath the paging dots.
    static let contentBottomInset: CGFloat = 222

    /// Vertical spacing between the hero content column's stacked elements.
    static let contentColumnSpacing: CGFloat = 12

    /// How far the rows are pulled up so the first row (Continue Watching) peeks in
    /// just below the hero's paging dots — the Apple TV look.
    static let rowOverlap: CGFloat = 132

    /// Leading inset for the hero content column (matches the rows' screen inset).
    static var contentLeadingPadding: CGFloat { PlozzTheme.Metrics.heroLeadingPadding }
}

/// Home and detail keep the same baseline, with independent profile size choices.
enum HeroLogoLayout {
    /// Nominal budget: Home's text column, and a wordmark height to match.
    static let budget = HeroLogoSizing.Layout.television.budget

    /// The nominal box handed to `HeroLogoArtwork` / `HeroLogoFit.fittedSize`.
    ///
    /// Pinned, not raw: `HeroLogoFit` reads its box as a budget and lets a wide
    /// shape flex a quarter past it, so passing the column straight through would
    /// draw the logo wider than the column it is being held to. The width the pin
    /// takes is returned as height, so no logo shrinks for being pinned — see
    /// ``HeroLogoFit/pinnedBox(budget:drawnWidth:maxHeight:)``.
    static let box: CGSize = HeroLogoFit.pinnedBox(
        budget: budget,
        drawnWidth: budget.width
    )

    /// The same box resolved against a column that may be narrower than the budget
    /// (a smaller screen, or a hero inset further than usual). Returns ``box``
    /// unchanged at the normal width.
    static func box(fitting availableWidth: CGFloat) -> CGSize {
        let column = min(availableWidth, budget.width)
        guard column < budget.width else { return box }
        return HeroLogoFit.pinnedBox(
            budget: CGSize(width: column, height: budget.height),
            drawnWidth: column
        )
    }

    static func box(size: HeroLogoSize, availableWidth: CGFloat = .infinity) -> CGSize {
        HeroLogoSizing.box(for: .television, size: size, availableWidth: availableWidth)
    }
}

#endif
