#if canImport(SwiftUI)
import SwiftUI

public struct PlayerControlButton: View {
    private let title: LocalizedStringResource
    private let systemImage: String
    private let prominent: Bool
    private let action: () -> Void

    public init(
        _ title: LocalizedStringResource, systemImage: String, prominent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        }
        .playerGlassButton(prominent: prominent)
        .accessibilityLabel(Text(title))
    }
}

public extension View {
    func playerGlassButton(prominent: Bool) -> some View {
        modifier(PlayerGlassButtonModifier(prominent: prominent))
    }
}

private struct PlayerGlassButtonModifier: ViewModifier {
    let prominent: Bool
    @Environment(\.plozzReducePanelGlass) private var reducePanelGlass
    @Environment(\.plozzReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        Group {
            if reducePanelGlass || reduceTransparency {
                content.buttonStyle(PlayerFrostedButtonStyle(prominent: prominent))
            } else if #available(iOS 26.0, tvOS 26.0, *) {
                if prominent {
                    content.buttonStyle(.glassProminent)
                } else {
                    content.buttonStyle(.glass)
                }
            } else {
                if prominent {
                    content.buttonStyle(.borderedProminent)
                } else {
                    content.buttonStyle(.bordered)
                }
            }
        }
        .playerPlatformAppearance()
    }
}

private struct PlayerFrostedButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isFocused ? (colorScheme == .light ? Color.white : .black) : .primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background {
                if isFocused {
                    shape.fill(Color.primary)
                } else {
                    Color.clear.plozzFrostedBackground(shape, raised: prominent)
                }
            }
            .plozzFrostedBorder(shape, visible: !isFocused)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
#endif
