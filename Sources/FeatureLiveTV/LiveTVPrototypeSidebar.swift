#if DEBUG
import CoreUI
import FeatureLiveTVCore
import SwiftUI

struct PrototypeBrowseSidebar: View {
    @Bindable var model: LiveTVPrototypeModel
    @Binding var active: Bool
    let focusRequest: Int
    let search: () -> Void
    let more: () -> Void
    @FocusState private var focused: Control?
    @State private var categoryFade = PrototypeScrollFade()
    @ScaledMetric(relativeTo: .subheadline) private var fontSize = PrototypeLayout.guideFontSize

    private enum Control: Hashable {
        case search, more
        case category(String?)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.gap) {
            Button(action: search) {
                Label("Search", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: PrototypeLayout.controlHeight, alignment: .leading)
                    .padding(.horizontal, PrototypeLayout.gap)
            }
            .buttonStyle(PrototypeButtonStyle(selected: !model.query.isEmpty, padded: false, surface: .control))
            .focused($focused, equals: .search)
            .accessibilityValue(model.query)
            .accessibilityIdentifier("live-tv-search")
            .padding(PrototypeLayout.controlInset)
            .background { PrototypeControlSurface() }

            ScrollView {
                LazyVStack(spacing: PrototypeLayout.smallGap) {
                    ForEach([nil] + model.categories.map(Optional.some), id: \.self) { category in
                        Button {
                            model.category = category
                        } label: {
                            HStack(spacing: PrototypeLayout.smallGap) {
                                if let category { Text(category) }
                                else { Text("All categories") }
                                Spacer(minLength: 0)
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .opacity(model.category == category ? 1 : 0)
                                    .accessibilityHidden(true)
                            }
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: PrototypeLayout.controlHeight, alignment: .leading)
                            .padding(.horizontal, PrototypeLayout.gap)
                        }
                        .buttonStyle(PrototypeButtonStyle(
                            padded: false, surface: .control
                        ))
                        .focused($focused, equals: .category(category))
                        .accessibilityAddTraits(model.category == category ? .isSelected : [])
                    }
                }
                .padding(.vertical, PrototypeLayout.smallGap)
            }
            .scrollIndicators(.hidden)
            .verticalEdgeFadeMask(
                fadeHeight: PrototypeLayout.verticalFade,
                topStrength: categoryFade.leading,
                bottomStrength: categoryFade.trailing
            )
            .onScrollGeometryChange(for: PrototypeScrollFade.self) { geometry in
                PrototypeScrollFade(
                    before: geometry.contentOffset.y + geometry.contentInsets.top,
                    after: geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height)
                )
            } action: { _, fade in
                categoryFade = fade
            }
            .accessibilityIdentifier("live-tv-category-list")

            Button(action: more) {
                Label("More", systemImage: "ellipsis")
                    .frame(maxWidth: .infinity, minHeight: PrototypeLayout.controlHeight, alignment: .leading)
                    .padding(.horizontal, PrototypeLayout.gap)
            }
            .buttonStyle(PrototypeButtonStyle(
                selected: model.source != nil || model.guideOnly || model.favoritesOnly,
                padded: false, surface: .control
            ))
            .focused($focused, equals: .more)
            .accessibilityIdentifier("live-tv-options")
        }
        .font(.system(size: fontSize, weight: .regular))
        .lineLimit(1)
        .focusEffectDisabled()
        #if os(tvOS)
        .focusSection()
        #endif
        .onChange(of: focused) { _, target in
            if target != nil { active = true }
        }
        .onChange(of: focusRequest) { _, _ in focused = .search }
    }
}
#endif
