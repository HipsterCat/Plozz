#if os(tvOS)
import SwiftUI
import CoreUI

enum NavigationGlassPart: Hashable {
    case button
    case menu
}

struct NavigationGlassAnchors: PreferenceKey {
    static var defaultValue: [NavigationGlassPart: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [NavigationGlassPart: Anchor<CGRect>],
        nextValue: () -> [NavigationGlassPart: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct NavigationGlassButtonFocus: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// One shared surface grows from the measured button into the measured menu.
/// Only the backdrop morphs; the actual focus targets retain their final layout.
struct NavigationGlassMorph: View {
    let buttonFrame: CGRect
    let menuFrame: CGRect
    let isExpanded: Bool
    let isButtonFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.plozzReduceTransparency) private var reduceTransparency
    @Namespace private var glassNamespace

    private var geometry: NavigationGlassMorphGeometry {
        NavigationGlassMorphGeometry(button: buttonFrame, menu: menuFrame)
    }

    var body: some View {
        Group {
            if #available(tvOS 26.0, *), !reduceTransparency, !reduceMotion {
                GlassEffectContainer {
                    if isExpanded {
                        nativeSurface(frame: menuFrame, radius: geometry.menuRadius, focused: false)
                    } else {
                        nativeSurface(frame: buttonFrame, radius: geometry.buttonRadius, focused: isButtonFocused)
                    }
                }
            } else {
                let frame = isExpanded ? menuFrame : buttonFrame
                Color.clear
                    .frame(width: frame.width, height: frame.height)
                    .plozzGlassPanel(
                        cornerRadius: isExpanded ? geometry.menuRadius : geometry.buttonRadius,
                        scrimOpacity: 0.08
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: geometry.buttonRadius)
                            .fill(.white)
                            .opacity(!isExpanded && isButtonFocused ? 1 : 0)
                    }
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .animation(reduceMotion ? nil : NavigationGlassMorphGeometry.animation, value: isExpanded)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @available(tvOS 26.0, *)
    private func nativeSurface(frame: CGRect, radius: CGFloat, focused: Bool) -> some View {
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .glassEffectID("navigation-surface", in: glassNamespace)
            .glassEffectTransition(.matchedGeometry)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.white)
                    .opacity(focused ? 1 : 0)
            }
            .position(x: frame.midX, y: frame.midY)
    }
}

struct NavigationGlassMorphGeometry: Equatable {
    let button: CGRect
    let menu: CGRect

    static let animation = Animation.smooth(duration: 0.32)
    var buttonRadius: CGFloat { min(button.width, button.height) / 2 }
    var menuRadius: CGFloat { NavigationRailMetrics.expandedPanelCornerRadius }

    var isUsable: Bool {
        [button, menu].allSatisfy { !$0.isEmpty && !$0.isNull && !$0.isInfinite }
    }
}
#endif
