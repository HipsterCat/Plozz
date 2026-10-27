#if os(tvOS)
import CoreModels
import CoreUI
import FeatureProfiles
import SwiftUI

struct TopBarNavigation: View {
    let destinations: [NavigationRailDestination]
    @Binding var selection: NavigationRailDestination
    let preventsAccidentalExit: Bool
    let content: (NavigationRailDestination, Bool) -> AnyView
    let label: (NavigationRailDestination) -> AnyView
    var profile: Profile?
    var onOpenProfileSwitcher: (() -> Void)?
    var chrome: NavigationChromeModel?
    @State private var fallbackChrome = NavigationChromeModel()

    var body: some View {
        let chrome = chrome ?? fallbackChrome
        return GeometryReader { geometry in
            NavigationRailFocusHost(contentExitHeading: .down) { owner in
                TopBarNavigationContent(
                    destinations: destinations, selection: $selection,
                    preventsAccidentalExit: preventsAccidentalExit,
                    content: content, label: label,
                    profile: profile, onOpenProfileSwitcher: onOpenProfileSwitcher,
                    chrome: chrome, safeAreaInsets: geometry.safeAreaInsets,
                    onNavigationFocusChanged: { [weak owner] in owner?.isNavigationFocused = $0 }
                )
            }
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .environment(chrome)
    }
}

private struct TopBarNavigationContent: View {
    let destinations: [NavigationRailDestination]
    @Binding var selection: NavigationRailDestination
    let preventsAccidentalExit: Bool
    let content: (NavigationRailDestination, Bool) -> AnyView
    let label: (NavigationRailDestination) -> AnyView
    let profile: Profile?
    let onOpenProfileSwitcher: (() -> Void)?
    let chrome: NavigationChromeModel
    let safeAreaInsets: EdgeInsets
    let onNavigationFocusChanged: (Bool) -> Void

    private enum Target: Hashable {
        case profile
        case destination(NavigationRailDestination)
    }

    @Namespace private var focusScope
    @FocusState private var focused: Target?
    @State private var isNavigating = true
    @State private var navigationRequest: Int? = 0
    @State private var navigationGeneration = 0
    @State private var contentRequest: UInt64?
    @State private var contentGeneration: UInt64 = 0
    @State private var returnFocus = NavigationContentFocusRequester.ReturnFocus()
    @State private var destinationFocus = NavigationDestinationFocusHandoff()
    @State private var overflow = HorizontalOverflow()
    @State private var destinationContentWidth: CGFloat?
    @Environment(\.themePalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    private var panelHeight: CGFloat {
        NavigationRailMetrics.expandedRowHeight + 2 * NavigationRailMetrics.expandedPanelContentInset
    }
    private var contentTopInset: CGFloat {
        NavigationRailMetrics.expandedPanelOuterMargin + panelHeight
    }
    private var contentInsets: EdgeInsets {
        EdgeInsets(
            top: contentTopInset,
            leading: safeAreaInsets.leading + PlozzTheme.Metrics.screenPadding,
            bottom: 0,
            trailing: safeAreaInsets.trailing + PlozzTheme.Metrics.screenPadding
        )
    }

    private var current: NavigationRailDestination {
        NavigationRailPlan.resolvedSelection(selection, destinations: destinations)
    }

    private var isShellActive: Bool {
        isEnabled && destinations.contains(selection)
    }

    var body: some View {
        ZStack(alignment: .top) {
            pages
                .background {
                    NavigationContentFocusRequester(
                        request: contentRequest, onCompleted: contentFocused,
                        returnFocus: returnFocus, restoresPreviousFocus: true
                    )
                }
                .background {
                    NavigationDestinationPresentationAnchor(
                        destination: current, request: destinationFocus.request,
                        onPresented: destinationPresented
                    )
                }
                .disabled(isNavigating && contentRequest == nil)
                .environment(\.plozzTopNavigationContentInsets, contentInsets)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: contentTopInset)
                }

            navigation
                .padding(.leading, contentInsets.leading)
                .padding(.trailing, contentInsets.trailing)
                .padding(.top, NavigationRailMetrics.expandedPanelOuterMargin)
                .opacity(chrome.isChromeHidden ? 0 : 1)
                .disabled(!isShellActive || chrome.isChromeHidden || chrome.transitionSuppressesFocus)
                .accessibilityHidden(chrome.isChromeHidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .focusScope(focusScope)
        .background { NavigationChromeTransitionAnchor(chrome: chrome) }
        .tvNavigationExitProtection(
            isEnabled: preventsAccidentalExit,
            navigationHasFocus: isNavigating && !chrome.isChromeHidden
        )
        .onExitCommand(perform: !isNavigating && !chrome.isChromeHidden ? openNavigation : nil)
        .onAppear { openNavigation() }
        .onChange(of: focused) { _, target in
            guard isShellActive, let target else { return }
            isNavigating = true
            contentRequest = nil
            destinationFocus.cancel()
            if case let .destination(destination) = target, destination != selection {
                returnFocus.clear()
                selection = destination
            }
        }
        .onChange(of: isNavigating && isShellActive, initial: true) { _, value in
            onNavigationFocusChanged(value)
        }
        .onChange(of: isShellActive) { _, active in
            if active {
                openNavigation()
            } else {
                navigationRequest = nil
                contentRequest = nil
                destinationFocus.cancel()
            }
        }
        .onChange(of: current) { _, _ in
            chrome.resetForDestinationChange()
            if destinationFocus.request?.destination != current { destinationFocus.cancel() }
            contentRequest = nil
            returnFocus.clear()
        }
        .onChange(of: chrome.isChromeHidden) { _, hidden in
            if hidden {
                navigationRequest = nil
                contentRequest = nil
                destinationFocus.cancel()
                isNavigating = false
            }
        }
        .onDisappear {
            navigationRequest = nil
            contentRequest = nil
            destinationFocus.cancel()
            onNavigationFocusChanged(false)
        }
    }

    private var pages: some View {
        ZStack {
            if current != .liveTV {
                content(current, selection == current)
                    .id(current)
                    .transition(.identity)
            }
            // Preserve the guide's filters and sources without keeping every
            // library grid mounted as focus traverses a long navigation list.
            RetainedLiveTVDestination(isActive: current == .liveTV) {
                content(.liveTV, selection == .liveTV)
            }
            .opacity(current == .liveTV ? 1 : 0)
            .disabled(current != .liveTV)
            .allowsHitTesting(current == .liveTV)
            .accessibilityElement(children: .contain)
            .accessibilityHidden(current != .liveTV)
        }
    }

    private var navigation: some View {
        HStack(spacing: NavigationRailMetrics.itemSpacing) {
            if let profile, let onOpenProfileSwitcher {
                Button(action: onOpenProfileSwitcher) {
                    ProfileAvatarView(profile: profile, size: NavigationRailMetrics.avatarSize)
                        .frame(height: NavigationRailMetrics.profileRowHeight)
                        .background { focusMarker(for: .profile) }
                }
                .buttonStyle(NavigationRailItemStyle(
                    expansionProgress: 0, isSelected: false, accent: palette.accent
                ))
                .focused($focused, equals: .profile)
                .disabled(!canFocus(.profile))
                .accessibilityLabel(Text("Switch Profile"))
                .accessibilityValue(Text(verbatim: profile.name))
                .accessibilityIdentifier("top-navigation-profile")
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: NavigationRailMetrics.itemSpacing) {
                        ForEach(destinations, id: \.storageValue) { destination in
                            destinationButton(destination).id(destination)
                        }
                    }
                    .padding(.vertical, NavigationRailMetrics.expandedPanelContentInset)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        destinationContentWidth = width
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .white], startPoint: .leading, endPoint: .trailing)
                            .frame(width: overflow.leading)
                        Rectangle()
                        LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: overflow.trailing)
                    }
                    .padding(.vertical, -40)
                }
                .onScrollGeometryChange(for: HorizontalOverflow.self) { geometry in
                    HorizontalOverflow(
                        leading: min(40, max(0, geometry.contentOffset.x + geometry.contentInsets.leading)),
                        trailing: min(40, max(0, geometry.contentSize.width
                            - geometry.contentOffset.x - geometry.containerSize.width))
                    )
                } action: { _, value in
                    overflow = value
                }
                .onChange(of: navigationRequest) { _, request in
                    guard request != nil else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { proxy.scrollTo(current) }
                }
            }
            .frame(maxWidth: destinationContentWidth)
        }
        .padding(.horizontal, NavigationRailMetrics.expandedPanelContentInset)
        .frame(height: panelHeight)
        .plozzGlassPanel(
            cornerRadius: NavigationRailMetrics.expandedPanelCornerRadius,
            scrimOpacity: 0.08
        )
        .focusSection()
        .onMoveCommand { direction in
            if direction == .down, focused != nil { enterContent() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("top-navigation")
    }

    private func destinationButton(_ destination: NavigationRailDestination) -> some View {
        Button { enterContent(destination) } label: {
            label(destination)
                .font(NavigationRailMetrics.labelFont)
                .lineLimit(1)
                .frame(maxWidth: 340)
                .frame(height: NavigationRailMetrics.rowContentHeight)
                .background { focusMarker(for: .destination(destination)) }
        }
        .buttonStyle(NavigationRailItemStyle(
            expansionProgress: 0, isSelected: selection == destination, accent: palette.accent
        ))
        .focused($focused, equals: .destination(destination))
        .prefersDefaultFocus(destination == current, in: focusScope)
        .disabled(!canFocus(.destination(destination)))
        .accessibilityAddTraits(selection == destination ? [.isSelected] : [])
        .accessibilityIdentifier("top-navigation-\(destination.storageValue)")
    }

    private func canFocus(_ target: Target) -> Bool {
        guard isShellActive else { return false }
        if navigationRequest != nil { return target == .destination(current) }
        return isNavigating || target == .destination(current)
    }

    private func focusMarker(for target: Target) -> some View {
        NavigationRowFocusRequester(
            request: isShellActive && target == .destination(current) ? navigationRequest : nil
        ) { request, didFocus in
            guard isShellActive, navigationRequest == request else { return }
            if !didFocus { focused = .destination(current) }
            navigationRequest = nil
        }
    }

    private func openNavigation() {
        guard isShellActive, !chrome.isChromeHidden, !chrome.transitionSuppressesFocus else { return }
        returnFocus.capture()
        contentRequest = nil
        destinationFocus.cancel()
        isNavigating = true
        navigationGeneration &+= 1
        navigationRequest = navigationGeneration
    }

    private func enterContent(_ destination: NavigationRailDestination? = nil) {
        guard isShellActive, isNavigating, !chrome.transitionSuppressesFocus else { return }
        let destination = destination ?? current
        if destination != current { selection = destination }
        destinationFocus.begin(destination)
    }

    private func destinationPresented(_ request: NavigationDestinationFocusHandoff.Request) {
        guard isShellActive, destinationFocus.complete(request), request.destination == current,
              isNavigating, !chrome.isChromeHidden else { return }
        isNavigating = false
        contentGeneration &+= 1
        contentRequest = contentGeneration
    }

    private func contentFocused(_ request: UInt64, didFocus: Bool) {
        guard isShellActive, contentRequest == request else { return }
        contentRequest = nil
        if !didFocus, focused != nil { openNavigation() }
    }

    private struct HorizontalOverflow: Equatable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }
}
#endif
