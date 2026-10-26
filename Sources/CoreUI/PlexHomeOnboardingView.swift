#if canImport(SwiftUI)
import CoreModels
import SwiftUI

/// One Plex Home decision followed by the viewer's identity, without authenticating
/// any of the other profiles being imported.
public struct PlexHomeOnboardingView: View {
    private let users: [PlexHomeUser]
    private let onSelect: (PlexHomeUser, Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(users: [PlexHomeUser], onSelect: @escaping (PlexHomeUser, Bool) -> Void) {
        self.users = users
        self.onSelect = onSelect
    }

    public var body: some View {
        PlexHomeOnboardingContent(users: users, reduceMotion: reduceMotion, onSelect: onSelect)
    }
}

struct PlexHomeOnboardingContent: View {
    let users: [PlexHomeUser]
    let reduceMotion: Bool
    let onSelect: (PlexHomeUser, Bool) -> Void
    @State private var addAllProfiles: Bool?
    @FocusState private var focused: String?

    init(users: [PlexHomeUser], reduceMotion: Bool, onSelect: @escaping (PlexHomeUser, Bool) -> Void) {
        self.users = users
        self.reduceMotion = reduceMotion
        self.onSelect = onSelect
    }

    private var orderedUsers: [PlexHomeUser] {
        users.sorted {
            if $0.isAdmin != $1.isAdmin { return $0.isAdmin }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 16)),
            removal: .opacity.combined(with: .offset(y: -12))
        )
    }

    var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                if let addAllProfiles {
                    userSelection(addAllProfiles: addAllProfiles)
                        .transition(pageTransition)
                } else {
                    importChoice
                        .transition(pageTransition)
                }
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
        .defaultScrollAnchor(.center)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.14) : .smooth(duration: 0.38, extraBounce: 0),
            value: addAllProfiles
        )
        .task(id: addAllProfiles) {
            focused = addAllProfiles == nil ? "add-all" : orderedUsers.first?.id
        }
    }

    private var importChoice: some View {
        VStack(spacing: 28) {
            HStack(spacing: 12) {
                ForEach(Array(orderedUsers.prefix(3))) { user in
                    PlexHomeUserAvatar(user: user, size: 64)
                        .accessibilityHidden(true)
                }
            }
            OnboardingHeader(
                Text("Add your Plex Home profiles?"),
                subtitle: Text("Keep everyone's Plex name, photo, and PIN protection.")
            )
            VStack(spacing: 16) {
                Button("Add all profiles") { addAllProfiles = true }
                    .plozzActionButton(role: .primary)
                    .focused($focused, equals: "add-all")
                    .accessibilityIdentifier("plex-home-add-all")
                Button("Just me") { addAllProfiles = false }
                    .plozzActionButton(role: .secondary)
                    .accessibilityIdentifier("plex-home-just-me")
            }
        }
    }

    private func userSelection(addAllProfiles: Bool) -> some View {
        VStack(spacing: 24) {
            OnboardingHeader(
                Text("Who are you?"),
                subtitle: addAllProfiles
                    ? Text("Everyone will have a profile. Choose yours to continue.")
                    : Text("Only your profile will be added.")
            )
            VStack(spacing: 14) {
                ForEach(orderedUsers) { user in
                    Button {
                        onSelect(user, addAllProfiles)
                    } label: {
                        PlexHomeUserRow(user: user, showsOwnerBadge: user.isAdmin)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    #if os(tvOS)
                    .buttonStyle(SettingsFocusButtonStyle())
                    #else
                    .buttonStyle(.plain)
                    #endif
                    .focused($focused, equals: user.id)
                    .accessibilityIdentifier("plex-home-user-\(user.id)")
                }
            }
            Button("Back") { self.addAllProfiles = nil }
                .plozzActionButton(role: .secondary)
                .accessibilityIdentifier("plex-home-back")
        }
        #if os(tvOS)
        .onExitCommand { self.addAllProfiles = nil }
        #endif
    }
}
#endif
