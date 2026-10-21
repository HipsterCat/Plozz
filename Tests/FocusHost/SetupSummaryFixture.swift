import CoreModels
import CoreUI
import FeatureProfiles
import FeatureSyncSetup
import SwiftUI
@testable import AppShell

struct SetupPickerFixture: View {
    @State private var closed = false
    private let invite = SyncSetupSourceInvite()

    var body: some View {
        Group {
            if closed {
                Text(verbatim: "Setup closed").accessibilityIdentifier("setup-closed")
            } else {
                SyncSetupSenderPicker(
                    invite: invite, inviteExpired: false,
                    devices: [DiscoveredPairingDevice(serviceName: "856E", displayName: "Test iPhone")],
                    code: .constant("856E"), onRefresh: {}, onSelect: { _ in },
                    onSendCode: {}, onClose: { closed = true }
                )
                .padding(70)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemePalette.dark.settingsBackground)
        .environment(\.themePalette, ThemePalette.dark)
        .preferredColorScheme(.dark)
    }
}

struct SetupSummaryFixture: View {
    @State private var finished = false

    private let groups = SyncedServerAccountGroup.groups(from: (0..<25).map { index in
        SyncedAccountDescriptor(
            id: "account-\(index)", provider: index.isMultiple(of: 2) ? .jellyfin : .plex,
            serverID: "server-\(index)",
            serverName: String(format: "Server %02d with a long library name", index),
            userID: "viewer", userName: "Viewer", candidateBaseURLs: []
        )
    })
    private let profiles = (0..<40).map { index in
        Profile(id: "profile-\(index)", name: "Household viewer \(index)")
    }

    var body: some View {
        Group {
            if finished {
                Text(verbatim: "Setup closed").accessibilityIdentifier("setup-closed")
            } else {
                SetupSummaryView(
                    title: "Your other device is set up", serverGroups: groups,
                    profileCount: profiles.count, actionTitle: "Done", onAction: { finished = true }
                ) {
                    ProfileSummaryGrid(
                        profiles: profiles, avatarSize: 80, itemWidth: 152, spacing: 24,
                        nameFont: .caption, nameLineLimit: nil, focusableProfiles: true
                    )
                }
                .padding(.horizontal, 70)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemePalette.dark.settingsBackground)
        .environment(\.themePalette, ThemePalette.dark)
        .preferredColorScheme(.dark)
    }
}
