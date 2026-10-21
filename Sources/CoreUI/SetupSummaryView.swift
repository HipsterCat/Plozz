#if canImport(SwiftUI)
import CoreModels
import SwiftUI

public struct SetupSectionCard<Content: View>: View {
    @Environment(\.themePalette) private var palette
    private let title: LocalizedStringResource
    private let count: Int?
    private let content: Content

    public init(
        _ title: LocalizedStringResource, count: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.count = count
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(title).font(.headline).plozzForeground(.primary)
                Spacer(minLength: 12)
                if let count {
                    Text(count, format: .number)
                        .font(.subheadline.monospacedDigit()).plozzForeground(.secondary)
                }
            }
            content
        }
        #if os(tvOS)
        .padding(32)
        #else
        .padding(20)
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardSurface, in: RoundedRectangle(cornerRadius: PlozzTheme.Metrics.mediumCardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: PlozzTheme.Metrics.mediumCardCornerRadius)
                .strokeBorder(palette.cardBorder.opacity(0.45), lineWidth: 1)
        }
    }
}

/// Both directions share the same bounded, scrolling summary. Shells supply
/// profile avatars and retain responsibility for applying setup and dismissing it.
public struct SetupSummaryView<Profiles: View>: View {
    @Environment(\.themePalette) private var palette
    #if os(tvOS)
    @State private var hasContentBelow = false
    #endif
    private let title: LocalizedStringResource
    private let serverGroups: [SyncedServerAccountGroup]
    private let pendingIDs: Set<String>
    private let profileCount: Int
    private let profiles: Profiles
    private let actionTitle: LocalizedStringResource
    private let onAction: () -> Void

    public init(
        title: LocalizedStringResource, serverGroups: [SyncedServerAccountGroup],
        pendingIDs: Set<String> = [], profileCount: Int,
        actionTitle: LocalizedStringResource, onAction: @escaping () -> Void,
        @ViewBuilder profiles: () -> Profiles
    ) {
        self.title = title
        self.serverGroups = serverGroups
        self.pendingIDs = pendingIDs
        self.profileCount = profileCount
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.profiles = profiles()
    }

    public var body: some View {
        VStack(spacing: 0) {
            summaryContent
            summaryAction
        }
        #if os(tvOS)
        .ignoresSafeArea(.container, edges: .top)
        #endif
    }

    private var summaryContent: some View {
        ScrollView {
            VStack(spacing: 28) {
                OnboardingHeader(Text(title))
                    .padding(.vertical, 12)
                if !serverGroups.isEmpty {
                    SetupSectionCard("Servers", count: serverGroups.count) {
                        #if os(tvOS)
                        let columns = [GridItem(.flexible(), spacing: 32), GridItem(.flexible(), spacing: 32)]
                        #else
                        let columns = [GridItem(.flexible())]
                        #endif
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(serverGroups) { group in
                                SetupSummaryServerRow(
                                    group: group, needsSignIn: group.accounts.contains { pendingIDs.contains($0.id) }
                                )
                                #if os(tvOS)
                                .focusable()
                                #endif
                            }
                        }
                    }
                }
                if profileCount > 0 {
                    SetupSectionCard("Profiles", count: profileCount) { profiles }
                }
                if !pendingIDs.isEmpty {
                    Text("Finish signing in to the remaining servers in Settings > iCloud Sync.")
                        .font(.callout).plozzForeground(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: contentWidth)
            .padding(24)
            #if os(tvOS)
            .padding(.top, 24)
            #endif
            .frame(maxWidth: .infinity)
        }
        #if os(tvOS)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height + geometry.contentInsets.bottom
                - geometry.contentOffset.y - geometry.containerSize.height > 2
        } action: { _, hasContentBelow in
            self.hasContentBelow = hasContentBelow
        }
        .mask {
            VerticalEdgeFadeMask(
                fadeHeight: 64,
                topStrength: 0,
                bottomStrength: hasContentBelow ? 1 : 0,
                horizontalOverhang: 32
            )
        }
        #endif
    }

    private var summaryAction: some View {
        Button(action: onAction) {
            Text(actionTitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                #if !os(tvOS)
                .frame(maxWidth: .infinity)
                #endif
        }
        .plozzActionButton()
        .controlSize(.large)
        .accessibilityIdentifier("sync-setup-continue")
        .frame(maxWidth: contentWidth)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        #if os(tvOS)
        .focusSection()
        #else
        .background(palette.backgroundBase)
        #endif
    }

    private var contentWidth: CGFloat {
        #if os(tvOS)
        1320
        #else
        640
        #endif
    }
}

private struct SetupSummaryServerRow: View {
    let group: SyncedServerAccountGroup
    let needsSignIn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ProviderBrandMark(provider: group.provider, size: 40, mediaShareTransport: group.mediaShareTransportKind)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.serverName).font(.body.weight(.semibold)).plozzForeground(.primary)
                Group {
                    if needsSignIn {
                        Text("Needs sign-in")
                    } else if group.userNames.isEmpty {
                        Text("Signed in")
                    } else {
                        Text("Signed in as \(group.userNames.formatted(.list(type: .and)))")
                    }
                }
                .font(.caption).plozzForeground(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("setup-summary-server-\(group.id)")
    }
}
#endif
