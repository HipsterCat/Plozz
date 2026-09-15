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
    @FocusState private var hasFocus: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.backward")
                .font(.system(size: 30, weight: .semibold))
                .scaleEffect(x: 0.65, y: 1)
                .frame(width: 11)
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
            .focused($hasFocus)
            .disabled(isNavigationExpanded || !isFocusEnabled)
            .buttonStyle(NavigationGlassPageButtonStyle())
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
        .onChange(of: hasFocus) { _, focused in
            guard Self.shouldOpenOnFocus(
                hasFocus: focused,
                isFocusEnabled: isFocusEnabled,
                isNavigationExpanded: isNavigationExpanded
            ) else { return }
            onOpenNavigation()
        }
    }

    nonisolated static func shouldOpenOnFocus(
        hasFocus: Bool,
        isFocusEnabled: Bool,
        isNavigationExpanded: Bool
    ) -> Bool {
        hasFocus && isFocusEnabled && !isNavigationExpanded
    }

    private static let openNavigationHint = LocalizedStringResource(
        "navigationRail.openHint",
        defaultValue: "Open navigation",
        comment: "Accessibility hint for the page button that opens the pinned sidebar."
    )
}

/// Focus immediately opens the menu, so the capsule has no intermediate white
/// focus platter. Its geometry stays stable for the shared glass transition.
private struct NavigationGlassPageButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .foregroundStyle(.primary)
            .contentShape(Capsule())
    }
}
#endif
