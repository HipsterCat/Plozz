#if os(tvOS)
import CoreUI
import CoreModels
import FeatureProfiles
import SwiftUI

public struct SettingsExitAction {
    public let perform: () -> Void

    public init(_ perform: @escaping () -> Void) { self.perform = perform }
}

private struct SettingsExitActionKey: EnvironmentKey {
    static let defaultValue: SettingsExitAction? = nil
}

private struct SettingsWorkspaceFocusScopeKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

public extension EnvironmentValues {
    var settingsExitAction: SettingsExitAction? {
        get { self[SettingsExitActionKey.self] }
        set { self[SettingsExitActionKey.self] = newValue }
    }
}

extension EnvironmentValues {
    var settingsWorkspaceFocusScope: Namespace.ID? {
        get { self[SettingsWorkspaceFocusScopeKey.self] }
        set { self[SettingsWorkspaceFocusScopeKey.self] = newValue }
    }
}

struct SettingsWorkspace<Sidebar: View, Detail: View>: View {
    @Bindable var navigation: SettingsNavigationModel
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: (SettingsRoute) -> Detail
    @Environment(\.settingsExitAction) private var exit
    @Namespace private var sidebarScope

    var body: some View {
        SettingsPageStack(
            navigation: navigation.pages, pageWidth: SettingsFormMetrics.pageWidth,
            onRootBack: { exit?.perform() },
            fullWidthDestination: \.usesFullScreenDetail
        ) {
            sidebar()
                .focusSection()
                .focusScope(sidebarScope)
                .environment(\.settingsWorkspaceFocusScope, sidebarScope)
        } destination: { route in
            SettingsWorkspaceDestination(route: route, navigation: navigation) {
                detail(route)
            }
        }
        .safeAreaPadding(.top, 36)
        .ignoresSafeArea(.container, edges: .vertical)
        .environment(navigation)
        .environment(\.settingsInWorkspace, true)
        .onChange(of: navigation.pages.returnGeneration) { _, generation in
            if generation > 0, !navigation.isCategoryOpen {
                navigation.restoreCategoryFocus()
            }
        }
        .onAppear {
            if navigation.isCategoryOpen || !navigation.path.isEmpty {
                navigation.enterDetail()
            } else {
                navigation.returnToSidebar()
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct SettingsWorkspaceDestination<Content: View>: View {
    let route: SettingsRoute
    let navigation: SettingsNavigationModel
    @ViewBuilder var content: () -> Content
    @SettingsPageDismiss private var dismiss
    @Environment(\.settingsPageContext) private var page

    var body: some View {
        pageContent
            .focusSection()
            .background {
                NativeFocusRegionObserver(isEnabled: page?.isCurrent == true) {
                    navigation.focusInDetail = true
                    navigation.restoringSidebar = false
                    navigation.enteringDetail = false
                }
            }
    }

    @ViewBuilder private var pageContent: some View {
        if route == .artwork || route == .navigationLayout {
            content()
        } else {
            content()
                .environment(\.settingsPageBackButton, AnyView(SettingsBackButton {
                    dismiss()
                }.settingsWorkspaceEntry(route: route)
                    .settingsPageEntryFocus(enabled: !route.usesFullScreenDetail)
                    .accessibilityIdentifier(page?.depth == 1 ? "settings-category-back" : "settings-workspace-back")))
                .toolbar(.hidden, for: .tabBar)
        }
    }
}

struct SettingsSectionButton: View {
    let title: Text
    let icon: String
    var assetIcon: String?
    var value: Text?
    var subtitle: Text?
    var subtitleContent: AnyView?
    let route: SettingsRoute
    @Environment(SettingsNavigationModel.self) private var navigation
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        SettingsPageActionLink(openOnMove: layoutDirection == .leftToRight ? .right : .left) { source in
            navigation.select(route)
            navigation.enterDetail(sourceID: source)
        } label: {
            SettingsSectionLabel(
                title: title, icon: icon, assetIcon: assetIcon,
                value: value, subtitle: subtitle, subtitleContent: subtitleContent
            )
        }
        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
        .settingsCategoryFocus(route)
    }
}

extension View {
    func settingsCategoryFocus(_ route: SettingsRoute) -> some View {
        modifier(SettingsCategoryFocus(route: route))
    }
}

private struct SettingsCategoryFocus: ViewModifier {
    let route: SettingsRoute
    @Environment(SettingsNavigationModel.self) private var navigation
    @Environment(\.settingsWorkspaceFocusScope) private var scope
    @Environment(\.resetFocus) private var resetFocus
    @Environment(\.settingsPageContext) private var page
    @FocusState private var focused: Bool

    private var canReceiveFocus: Bool {
        page?.isCurrent != false && !navigation.isCategoryOpen && !navigation.enteringDetail
            && (!(navigation.focusInDetail || navigation.restoringSidebar) || navigation.section == route)
    }

    func body(content: Content) -> some View {
        content
        .focused($focused)
        .modifier(SettingsSectionFocusPreference(scope: scope, selected: navigation.section == route))
        .disabled(!canReceiveFocus)
        .accessibilityIdentifier("settings-section-\(route)")
        .accessibilityAddTraits(focused ? .isSelected : [])
        .navigationEntryFocus(navigation.section == route ? .content : nil)
        .background {
            NativeFocusRegionObserver(isEnabled: canReceiveFocus) {
                guard canReceiveFocus else { return }
                navigation.focusInDetail = false
                navigation.restoringSidebar = false
                navigation.enteringDetail = false
                navigation.select(route)
            }
        }
        .task(id: navigation.sidebarFocusRequest) {
            guard navigation.section == route else { return }
            focused = false
            await Task.yield()
            guard !Task.isCancelled, navigation.section == route,
                  !navigation.focusInDetail, !navigation.enteringDetail else { return }
            focused = true
            if let scope { resetFocus(in: scope) }
        }
    }
}

private struct SettingsSectionFocusPreference: ViewModifier {
    let scope: Namespace.ID?
    let selected: Bool

    func body(content: Content) -> some View {
        if let scope {
            content.prefersDefaultFocus(selected, in: scope)
        } else {
            content
        }
    }
}

struct SettingsSectionLabel: View {
    let title: Text
    let icon: String?
    let assetIcon: String?
    let value: Text?
    let subtitle: Text?
    var subtitleContent: AnyView?
    var accessorySymbol = "chevron.forward"

    var body: some View {
        SettingsRowLabel(icon: icon, assetIcon: assetIcon, title: title, secondary: {
            Group {
                if let subtitleContent {
                    subtitleContent
                } else {
                    subtitle
                }
            }
            .font(SettingsRowMetrics.helperFont)
            .settingsRowSecondary()
            .lineLimit(2)
        }, trailing: {
            HStack(spacing: 10) {
                value?.font(.caption).settingsRowSecondary()
                Image(systemName: accessorySymbol)
                    .font(.caption.weight(.semibold))
                    .settingsRowSecondary()
            }
        })
    }
}

enum SettingsWorkspaceHeaderMetrics {
    static let iconSize: CGFloat = 52
    static let titleFont: Font = .system(size: 36, weight: .bold)
    static let labelSpacing = PlozzTheme.Spacing.medium
    static let outerInset = SettingsFormMetrics.groupInset
    static let controlInset = PlozzTheme.Spacing.xSmall
    static let contentInset = outerInset + controlInset
}

struct SettingsWorkspaceScopeBadge: View {
    let syncEnabled: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        Image(systemName: syncEnabled ? "person.2" : "appletv")
            .font(.system(size: SettingsWorkspaceHeaderMetrics.iconSize / 2))
            .frame(width: SettingsWorkspaceHeaderMetrics.iconSize,
                   height: SettingsWorkspaceHeaderMetrics.iconSize)
            .background(Circle().fill(palette.fillSubtle))
            .overlay(Circle().strokeBorder(palette.cardBorder, lineWidth: 1))
    }
}

struct SettingsWorkspaceProfileHeader: View {
    let profile: Profile
    let canEdit: Bool
    let onSwitch: () -> Void
    let onEdit: (UUID) -> Void
    @Environment(SettingsNavigationModel.self) private var navigation

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSwitch) {
                HStack(spacing: SettingsWorkspaceHeaderMetrics.labelSpacing) {
                    ProfileAvatarView(profile: profile, size: SettingsWorkspaceHeaderMetrics.iconSize)
                        .accessibilityIdentifier("settings-profile-avatar")
                    Text(verbatim: profile.name)
                        .font(SettingsWorkspaceHeaderMetrics.titleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("settings-profile-name")
                    Spacer(minLength: 0)
                }
                .padding(SettingsWorkspaceHeaderMetrics.controlInset)
            }
            .buttonStyle(SettingsFocusButtonStyle(size: .contained))
            .accessibilityLabel("Switch Profile")
            .accessibilityValue(Text(verbatim: profile.name))
            .accessibilityIdentifier("settings-profile-switch")
            if canEdit {
                SettingsPageActionLink(action: onEdit) { Text("Edit") }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("settings-profile-edit")
            }
        }
        .disabled(navigation.focusInDetail || navigation.restoringSidebar || navigation.enteringDetail)
        .padding(SettingsWorkspaceHeaderMetrics.outerInset)
    }
}
#endif
