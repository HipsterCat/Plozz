#if DEBUG && os(iOS)
import CoreModels
import CoreSecureStore
import AppRuntime
import EnginePlozzigen
import FeatureLiveTV
import FeaturePlayback
import SwiftUI

/// Development-only Live TV destination hosted by the real iPhone/iPad tab shell.
struct PlozziOSLiveTVDestination: View {
    let isActive: Bool
    let profileID: String

    @Environment(ProfilesModel.self) private var profiles
    @State private var isExpanded = false
    private let preferencesStore: LiveTVPreferencesStore
    private let viewSettingsStore: LiveTVViewSettingsStore
    private let sourceStore: LiveTVSourcesStore
    private let accountsProviders: AccountsProvidersModel?
    private let authenticatedHTTPResolver: (any AuthenticatedHTTPResourceResolving)?
    private let connectServer: (() -> Void)?
    private let didConfigurePlaylist: () -> Void

    init(
        isActive: Bool,
        profileID: String,
        preferencesNamespace: String?,
        accountsProviders: AccountsProvidersModel? = nil,
        authenticatedHTTPResolver: (any AuthenticatedHTTPResourceResolving)? = nil,
        connectServer: (() -> Void)? = nil,
        didConfigurePlaylist: @escaping () -> Void = {}
    ) {
        self.isActive = isActive
        self.profileID = profileID
        self.preferencesStore = LiveTVPreferencesStore(namespace: preferencesNamespace)
        self.viewSettingsStore = LiveTVViewSettingsStore(namespace: preferencesNamespace)
        self.sourceStore = LiveTVSourceStorage.store(namespace: preferencesNamespace)
        self.accountsProviders = accountsProviders
        self.authenticatedHTTPResolver = authenticatedHTTPResolver
        self.connectServer = connectServer
        self.didConfigurePlaylist = didConfigurePlaylist
    }

    var body: some View {
        LiveTVPrototypeView(
            isActive: isActive,
            preferencesStore: preferencesStore,
            viewSettingsStore: viewSettingsStore,
            sourceStore: sourceStore,
            serverProviderResolver: accountsProviders?.liveTVProviderResolver(),
            authenticatedHTTPResolver: authenticatedHTTPResolver,
            isProfileAuthorized: { [profiles, profileID] in profiles.activeProfileID == profileID },
            serverChoices: accountsProviders?.liveTVServerChoices ?? [],
            serverAuthorizationID: accountsProviders?.liveTVAuthorizationID ?? "",
            connectServer: connectServer,
            didConfigurePlaylist: didConfigurePlaylist,
            onExpandedChange: { isExpanded = $0 }
        ) { playback in
            LiveChannelPlayerView(
                channelID: playback.channel.id,
                title: playback.channel.name,
                streamURL: playback.streamURL,
                logoURL: playback.channel.logoURL,
                httpHeaders: playback.httpHeaders,
                makeEngine: { try PlozzigenVideoEngine() },
                onPreviousChannel: playback.previousChannel,
                onNextChannel: playback.nextChannel,
                isFavorite: playback.isFavorite,
                canToggleFavorite: playback.canToggleFavorite,
                onToggleFavorite: playback.onToggleFavorite,
                isExpanded: playback.isExpanded,
                isActive: isActive,
                onReturnToGuide: playback.returnToGuide,
                playPauseRequest: playback.playPauseRequest,
                onPlaybackStarted: playback.playbackStarted,
                reportingID: playback.reportingID,
                onPlaybackUpdate: playback.playbackUpdate,
                onPlaybackFailed: playback.playbackFailed,
                preparingChannelName: playback.preparingChannelName
            )
        }
        .id(profileID)
        .toolbar(isExpanded ? .hidden : .visible, for: .tabBar)
        .onChange(of: isActive, initial: true) { _, active in
            if !active {
                isExpanded = false
            }
        }
    }
}

struct PlozziOSLiveTVSourcesDestination: View {
    let profileID: String
    let preferencesNamespace: String?
    let accountsProviders: AccountsProvidersModel
    let profiles: ProfilesModel
    var connectServer: (() -> Void)? = nil
    let didConfigurePlaylist: () -> Void

    var body: some View {
        LiveTVSourcesView(
            store: LiveTVSourceStorage.store(namespace: preferencesNamespace),
            serverChoices: accountsProviders.liveTVServerChoices,
            serverProviderResolver: accountsProviders.liveTVProviderResolver(),
            connectServer: connectServer,
            didConfigurePlaylist: didConfigurePlaylist
        )
        .environment(profiles)
        .id(profileID)
    }
}
#endif
