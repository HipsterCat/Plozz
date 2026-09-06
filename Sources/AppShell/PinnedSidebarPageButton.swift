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
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .plozzGlassPillButton()
            .accessibilityHint(Text(Self.openNavigationHint))
            .accessibilityIdentifier("pinned-sidebar-page-button")
        }
        // Preserve header geometry, and therefore the native search field, while
        // the expanded menu overlays the page.
        .opacity(isNavigationExpanded ? 0 : 1)
        .accessibilityHidden(isNavigationExpanded)
    }

    private static let openNavigationHint = LocalizedStringResource(
        "navigationRail.openHint",
        defaultValue: "Open navigation",
        comment: "Accessibility hint for the page button that opens the pinned sidebar."
    )
}
#endif
