#if canImport(SwiftUI)
import CoreModels
import SwiftUI

/// A palette choice shared by profile avatars and appearance settings.
public struct ColorSwatchButton: View {
    private let title: LocalizedStringResource
    private let color: Color
    private let foreground: Color
    private let isSelected: Bool
    private let unselectedSymbol: String?
    private let action: () -> Void
    @Environment(\.themePalette) private var palette

    public init(
        title: LocalizedStringResource, color: Color, foreground: Color,
        isSelected: Bool, unselectedSymbol: String? = nil, action: @escaping () -> Void
    ) {
        self.title = title
        self.color = color
        self.foreground = foreground
        self.isSelected = isSelected
        self.unselectedSymbol = unselectedSymbol
        self.action = action
    }

    private var diameter: CGFloat {
        #if os(tvOS)
        42
        #else
        44
        #endif
    }

    public var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
                .overlay {
                    Circle().strokeBorder(
                        borderColor, lineWidth: borderWidth
                    )
                }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: diameter * 0.4, weight: .heavy))
                            .foregroundStyle(foreground)
                    } else if let unselectedSymbol {
                        Image(systemName: unselectedSymbol)
                            .font(.system(size: diameter * 0.35, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                .contentShape(Circle())
        }
        #if os(tvOS)
        .plozzCardFocusButtonStyle(
            CircularSelectionButtonStyle(diameter: diameter), cornerRadius: diameter / 2,
            contentSuppliesProjection: true
        )
        .plozzCircularFocusStyle()
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var borderColor: Color {
        #if os(tvOS)
        palette.cardBorder
        #else
        isSelected ? palette.accent : palette.cardBorder
        #endif
    }

    private var borderWidth: CGFloat {
        #if os(tvOS)
        1
        #else
        isSelected ? 3 : 1
        #endif
    }
}

#if os(tvOS)
public struct CircularSelectionButtonStyle: ButtonStyle {
    private let diameter: CGFloat

    public init(diameter: CGFloat) { self.diameter = diameter }

    public func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration, diameter: diameter)
    }

    private struct TileBody: View {
        let configuration: ButtonStyle.Configuration
        let diameter: CGFloat
        @Environment(\.isFocused) private var isFocused
        @Environment(\.plozzCardFocusStyle) private var focusStyle

        var body: some View {
            configuration.label
                .plozzFocusHalo(
                    cornerRadius: diameter / 2,
                    focusScale: PlozzTheme.Metrics.mediumFocusedCardScale,
                    isFocused: isFocused
                )
                .scaleEffect(configuration.isPressed && !focusStyle.usesSystemEffect ? 0.96 : 1)
                .animation(focusStyle.usesSystemEffect ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
#endif
#endif
