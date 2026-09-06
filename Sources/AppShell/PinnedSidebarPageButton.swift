#if os(tvOS)
import SwiftUI
import CoreUI

/// The native-style page affordance: a separate chevron beside a glass capsule.
struct PinnedSidebarPageButton: View {
    let title: LocalizedStringResource
    let symbol: String
    let isNavigationExpanded: Bool
    let isFocusEnabled: Bool
    let onOpenNavigation: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.backward")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Button(action: onOpenNavigation) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: symbol)
                }
                .labelStyle(.titleAndIcon)
                .font(NavigationRailMetrics.labelFont)
            }
            .disabled(isNavigationExpanded || !isFocusEnabled)
            .buttonStyle(NavigationGlassPageButtonStyle(showsFocusBackground: !isNavigationExpanded))
            .focusEffectDisabled()
            .anchorPreference(key: NavigationGlassAnchors.self, value: .bounds) { [.button: $0] }
            .accessibilityHint(Text(Self.openNavigationHint))
            .accessibilityIdentifier("pinned-sidebar-page-button")
        }
        // Preserve header geometry, and therefore the native search field, while
        // the expanded menu overlays the page.
        .opacity(isNavigationExpanded ? 0 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isNavigationExpanded)
        .accessibilityHidden(isNavigationExpanded)
    }

    private static let openNavigationHint = LocalizedStringResource(
        "navigationRail.openHint",
        defaultValue: "Open navigation",
        comment: "Accessibility hint for the page button that opens the pinned sidebar."
    )
}

/// The shell owns the shared glass surface; this control keeps normal focus
/// feedback and reserves the capsule's dimensions without drawing a second one.
private struct NavigationGlassPageButtonStyle: ButtonStyle {
    let showsFocusBackground: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .foregroundStyle(isFocused ? AnyShapeStyle(Color.black) : AnyShapeStyle(.primary))
            .background {
                // Focus chrome belongs to the control, never the morphing panel.
                Capsule()
                    .fill(.white)
                    .opacity(isFocused && showsFocusBackground ? 1 : 0)
                    .transaction { $0.animation = nil }
            }
            .contentShape(Capsule())
    }
}
#endif
