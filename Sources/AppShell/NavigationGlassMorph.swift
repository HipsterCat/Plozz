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

/// A persistent glass surface, separate from focus targets and focus highlights.
struct NavigationGlassMorph: View {
    let buttonFrame: CGRect?
    let menuFrame: CGRect
    let isExpanded: Bool
    let showsPageButton: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let surface = NavigationGlassSurface.resolve(
            isExpanded: isExpanded,
            showsPageButton: showsPageButton,
            hasButtonFrame: buttonFrame != nil
        )
        let geometry = NavigationGlassMorphGeometry(button: buttonFrame ?? menuFrame, menu: menuFrame)
        let frame = surface == .button ? geometry.button : geometry.menu
        let radius = surface == .button ? geometry.buttonRadius : geometry.menuRadius
        return NavigationGlassSurfaceView(frame: frame, cornerRadius: radius)
            .opacity(surface == .none ? 0 : 1)
            .animation(reduceMotion ? nil : NavigationGlassMorphGeometry.animation, value: surface)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Supply interpolated geometry to the material itself. tvOS does not reliably
/// animate glassEffectID replacement through a preference-resolved background.
struct NavigationGlassSurfaceView: View, Animatable {
    var frame: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(frame.animatableData, cornerRadius) }
        set {
            frame.animatableData = newValue.first
            frame.size.width = max(1, frame.width)
            frame.size.height = max(1, frame.height)
            cornerRadius = min(max(0, newValue.second), min(frame.width, frame.height) / 2)
        }
    }

    var body: some View {
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .plozzGlassPanel(cornerRadius: cornerRadius, scrimOpacity: 0.08)
            .position(x: frame.midX, y: frame.midY)
            // Geometry is already interpolated; do not start a second material
            // animation each time this body supplies the next frame.
            .transaction { $0.animation = nil }
    }
}

enum NavigationGlassSurface: Equatable {
    case none
    case button
    case menu

    static func resolve(
        isExpanded: Bool,
        showsPageButton: Bool,
        hasButtonFrame: Bool
    ) -> Self {
        if isExpanded { return .menu }
        guard showsPageButton else { return .none }
        // Retain the outgoing panel until the new Search capsule is measured.
        return hasButtonFrame ? .button : .menu
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
