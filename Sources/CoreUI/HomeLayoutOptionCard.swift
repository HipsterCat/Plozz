#if canImport(SwiftUI)
import SwiftUI
import CoreModels

/// The same Home layout choice in Settings and profile onboarding.
public struct HomeLayoutOptionCard: View {
    private let style: HeroStyle
    private let isSelected: Bool
    private let swatchHeight: CGFloat
    private let action: () -> Void
    @Environment(\.themePalette) private var palette

    public init(
        style: HeroStyle,
        isSelected: Bool,
        swatchHeight: CGFloat,
        action: @escaping () -> Void
    ) {
        self.style = style
        self.isSelected = isSelected
        self.swatchHeight = swatchHeight
        self.action = action
    }

    public var body: some View {
        PreviewCard(
            title: style.layoutTitle,
            isSelected: isSelected,
            accent: palette.accent,
            compact: true,
            swatchHeight: swatchHeight,
            action: action
        ) {
            HomeLayoutSwatch(style: style, cornerRadius: PlozzTheme.Metrics.Radius.content)
        }
        .accessibilityIdentifier("home-layout-\(style.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

public extension HeroStyle {
    var layoutTitle: LocalizedStringResource {
        switch self {
        case .carousel:
            LocalizedStringResource(
                "homeLayout.fullscreenHero",
                defaultValue: "Fullscreen Hero",
                comment: "Apple TV Home layout option: a full-screen featured title with Play and other buttons above the rows."
            )
        case .followsFocus:
            LocalizedStringResource(
                "homeLayout.showcase",
                defaultValue: "Showcase",
                comment: "Apple TV Home layout option: one row at a time, with the top of the screen showing whichever title is focused."
            )
        }
    }
}
#endif
