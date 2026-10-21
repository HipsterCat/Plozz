#if canImport(SwiftUI)
import CoreUI
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsDetailNavigation {
    private(set) var isPresented = false
    private(set) var awaitingFocus = false
    private(set) var returnFocusGeneration = 0
    private(set) var pageID: String?
    private var transitionGeneration = 0

    func push(pageID: String? = nil, animated: Bool) {
        transitionGeneration += 1
        self.pageID = pageID
        awaitingFocus = true
        withAnimation(animated ? SettingsPageMotion.animation : nil) {
            isPresented = true
        }
    }

    func pop(animated: Bool) {
        transitionGeneration += 1
        let generation = transitionGeneration
        awaitingFocus = true
        withAnimation(animated ? SettingsPageMotion.animation : nil, completionCriteria: .removed) {
            isPresented = false
        } completion: {
            guard self.transitionGeneration == generation else { return }
            self.returnFocusGeneration += 1
        }
    }

    func focusArrived() { awaitingFocus = false }

    func reset() {
        transitionGeneration += 1
        isPresented = false
        awaitingFocus = false
        returnFocusGeneration = 0
        pageID = nil
    }
}

/// A retained settings page and its child share the workspace's directional fade.
struct SettingsDetailPages<Root: View, Detail: View>: View {
    let navigation: SettingsDetailNavigation
    @ViewBuilder var root: () -> Root
    @ViewBuilder var detail: () -> Detail
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var rootFocusScope

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                root()
                    .tvOSFocusScope(rootFocusScope)
                    .environment(\.settingsDetailRootFocusScope, rootFocusScope)
                    .environment(\.settingsDetailRootEnabled, isEnabled)
                    .environment(\.isEnabled, isEnabled && !navigation.isPresented && !navigation.awaitingFocus)
                    .allowsHitTesting(!navigation.isPresented)
                    .accessibilityHidden(navigation.isPresented)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .settingsPageVisibility(!navigation.isPresented)
                if navigation.isPresented {
                    detail()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                        .transition(reduceMotion ? .identity : SettingsPageMotion.transition(edge: .trailing))
                        #if os(tvOS)
                        .onExitCommand {
                            navigation.pop(animated: !reduceMotion)
                        }
                        #endif
                }
            }
        }
        .environment(navigation)
        .mask {
            // Contain the horizontal slide without cutting off the scroll view's
            // native rendering into the vertical safe-area margins.
            Rectangle().ignoresSafeArea(.container, edges: .vertical)
        }
    }
}

/// Uses the registered detail pane on TV, or ordinary navigation outside that pane.
struct SettingsDetailLink<Destination: View, Label: View>: View {
    var pageID: String? = nil
    @ViewBuilder var destination: () -> Destination
    @ViewBuilder var label: () -> Label
    @Environment(SettingsDetailNavigation.self) private var navigation: SettingsDetailNavigation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsDetailRootFocusScope) private var rootFocusScope
    @Environment(\.settingsDetailRootEnabled) private var rootEnabled
    #if os(tvOS)
    @Environment(\.resetFocus) private var resetFocus
    #endif
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if let navigation {
                Button {
                    navigation.push(pageID: pageID, animated: !reduceMotion)
                } label: {
                    label()
                }
                .focused($isFocused)
                .modifier(SettingsDetailReturnFocus(pageID: pageID))
                .environment(
                    \.isEnabled,
                    rootEnabled && !navigation.isPresented
                        && (!navigation.awaitingFocus || navigation.pageID == pageID)
                )
                #if os(tvOS)
                .background {
                    NativeFocusRegionObserver(isEnabled: !navigation.isPresented) {
                        navigation.focusArrived()
                    }
                }
                #endif
            } else {
                SettingsPageLink(destination: destination, label: label)
                    .focused($isFocused)
            }

        }
        #if !os(tvOS)
        .onChange(of: isFocused) { _, focused in
            if focused { navigation?.focusArrived() }
        }
        #endif
        .task(id: navigation?.returnFocusGeneration) {
            guard let navigation, navigation.pageID == pageID, navigation.returnFocusGeneration > 0 else { return }
            isFocused = false
            await Task.yield()
            if !Task.isCancelled, !navigation.isPresented {
                isFocused = true
                #if os(tvOS)
                if let rootFocusScope { resetFocus(in: rootFocusScope) }
                #endif
            }
        }
    }
}

struct SettingsRouteLink<Label: View>: View {
    let value: SettingsRoute
    let label: Label
    #if os(tvOS)
    @Environment(SettingsNavigationModel.self) private var navigation: SettingsNavigationModel?
    @Environment(\.settingsPageContext) private var pageContext
    #endif

    init(value: SettingsRoute, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    var body: some View {
        #if os(tvOS)
        if let navigation, pageContext != nil {
            SettingsPageActionLink { source in
                navigation.pages.push(value, sourceID: source)
            } label: { label }
        } else {
            NavigationLink(value: value) { label }
        }
        #else
        NavigationLink(value: value) { label }
        #endif
    }
}

extension SettingsRouteLink where Label == Text {
    init(_ title: LocalizedStringKey, value: SettingsRoute) {
        self.value = value
        self.label = Text(title)
    }
}

private struct SettingsDetailReturnFocus: ViewModifier {
    let pageID: String?
    @Environment(SettingsDetailNavigation.self) private var navigation: SettingsDetailNavigation?
    @Environment(\.settingsDetailRootFocusScope) private var scope

    @ViewBuilder
    func body(content: Content) -> some View {
        if let scope {
            content.tvOSPrefersDefaultFocus(
                navigation?.isPresented == false && navigation?.pageID == pageID
                    && (navigation?.returnFocusGeneration ?? 0) > 0,
                in: scope
            )
        } else {
            content
        }
    }
}

private struct SettingsDetailRootFocusScopeKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

private struct SettingsDetailRootEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var settingsDetailRootEnabled: Bool {
        get { self[SettingsDetailRootEnabledKey.self] }
        set { self[SettingsDetailRootEnabledKey.self] = newValue }
    }

    var settingsDetailRootFocusScope: Namespace.ID? {
        get { self[SettingsDetailRootFocusScopeKey.self] }
        set { self[SettingsDetailRootFocusScopeKey.self] = newValue }
    }
}
#endif
