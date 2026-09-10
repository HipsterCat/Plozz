import SwiftUI

/// Shared touch-target sizing and appearance for Home and detail hero actions.
public struct TouchHeroActionButtonStyle: ButtonStyle {
    public enum Kind {
        case primary
        case secondary
    }

    private let kind: Kind
    private let circular: Bool
    @Environment(\.themePalette) private var palette

    public init(kind: Kind, circular: Bool = false) {
        self.kind = kind
        self.circular = circular
    }

    public func makeBody(configuration: Configuration) -> some View {
        styledLabel(configuration)
            .contentShape(circular ? AnyShape(Circle()) : AnyShape(Capsule()))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder
    private func styledLabel(_ configuration: Configuration) -> some View {
        if circular {
            configuration.label
                .foregroundStyle(kind == .primary ? palette.backgroundBase : palette.primaryText)
                .frame(width: 48, height: 48)
                .background {
                    Circle()
                        .fill(backgroundColor)
                        .overlay {
                            if kind == .secondary {
                                Circle().strokeBorder(palette.primaryText.opacity(0.2), lineWidth: 1)
                            }
                        }
                }
        } else {
            configuration.label
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .font(.headline.weight(.semibold))
                .foregroundStyle(kind == .primary ? palette.backgroundBase : palette.primaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .background {
                    Capsule()
                        .fill(backgroundColor)
                        .overlay {
                            if kind == .secondary {
                                Capsule().strokeBorder(palette.primaryText.opacity(0.2), lineWidth: 1)
                            }
                        }
                }
                .contentShape(Capsule())
        }
    }

    private var backgroundColor: Color {
        kind == .primary ? palette.primaryText : palette.cardSurface.opacity(0.92)
    }
}
