#if canImport(SwiftUI)
import SwiftUI
#if os(iOS)
import UIKit
#endif

public extension EnvironmentValues {
    var playerUsesNativeGlass: Bool {
        if #available(iOS 26.0, tvOS 26.0, *) {
            return !plozzReducePanelGlass && !plozzReduceTransparency
        }
        return false
    }

    var playerControlForeground: Color {
        #if os(iOS)
        Color(playerControlTint)
        #else
        .primary
        #endif
    }

    #if os(iOS)
    var playerControlTint: UIColor {
        playerUsesNativeGlass || colorScheme == .dark ? .white : .black
    }
    #endif
}

public extension View {
    /// Scope television playback chrome, not the window or the browsing theme.
    @ViewBuilder
    func playerPlatformAppearance() -> some View {
        #if os(tvOS)
        environment(\.colorScheme, .dark)
            .environment(\.themePalette, .dark)
        #else
        self
        #endif
    }
}

@available(iOS 26.0, tvOS 26.0, *)
public struct PlayerNativeGlassSurface<S: Shape>: View {
    private let shape: S
    private let glass: Glass

    public init(_ shape: S, glass: Glass = .regular) {
        self.shape = shape
        self.glass = glass
    }

    public var body: some View {
        Color.clear.glassEffect(glass, in: shape)
    }
}
#endif
