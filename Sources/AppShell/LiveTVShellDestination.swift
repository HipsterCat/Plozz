#if DEBUG && os(tvOS)
import CoreModels
import CoreSecureStore
import AppRuntime
import EnginePlozzigen
import FeatureLiveTV
import FeaturePlayback
import SwiftUI

/// Development-only composition root for Live TV inside Plozz's real navigation.
///
/// The prototype owns one player construction site and keeps this child at a
/// stable identity while channels change. The shell only reports whether the
/// destination is visible and coordinates its expanded chrome.
struct LiveTVShellDestination: View {
    let isActive: Bool
    let profileID: String
    let usesNativeNavigation: Bool
    let onExpandedChange: (Bool) -> Void

    @Environment(ProfilesModel.self) private var profiles
    @State private var hidesNavigation = false
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
        didConfigurePlaylist: @escaping () -> Void = {},
        usesNativeNavigation: Bool = false,
        onExpandedChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.isActive = isActive
        self.profileID = profileID
        self.usesNativeNavigation = usesNativeNavigation
        self.onExpandedChange = onExpandedChange
        self.preferencesStore = LiveTVPreferencesStore(namespace: preferencesNamespace)
        self.viewSettingsStore = LiveTVViewSettingsStore(namespace: preferencesNamespace)
        self.sourceStore = LiveTVSourceStorage.store(namespace: preferencesNamespace)
        self.accountsProviders = accountsProviders
        self.authenticatedHTTPResolver = authenticatedHTTPResolver
        self.connectServer = connectServer
        self.didConfigurePlaylist = didConfigurePlaylist
    }

    @ViewBuilder
    var body: some View {
        if usesNativeNavigation {
            LiveTVNavigationContainer(hidesNavigation: hidesNavigation) {
                liveTVContent
            }
        } else {
            liveTVContent
        }
    }

    private var liveTVContent: some View {
        LiveTVPrototypeView(
            isActive: isActive,
            usesNativeFullscreen: usesNativeNavigation,
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
            onExpandedChange: updateExpandedState
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
                usesNativeFullscreen: usesNativeNavigation,
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
        .onChange(of: isActive, initial: true) { _, active in
            if !active {
                updateExpandedState(false)
            }
        }
        .onDisappear {
            guard !(isActive && usesNativeNavigation && hidesNavigation) else { return }
            updateExpandedState(false)
        }
    }

    private func updateExpandedState(_ expanded: Bool) {
        hidesNavigation = expanded && isActive
        guard isActive else { return }
        onExpandedChange(expanded)
    }
}

struct LiveTVShellSourcesDestination: View {
    let profileID: String
    let preferencesNamespace: String?
    let accountsProviders: AccountsProvidersModel
    var connectServer: (() -> Void)? = nil
    let didConfigurePlaylist: () -> Void

    var body: some View {
        LiveTVSourcesView(
            store: LiveTVSourceStorage.store(namespace: preferencesNamespace),
            presentation: .settingsPane,
            serverChoices: accountsProviders.liveTVServerChoices,
            serverProviderResolver: accountsProviders.liveTVProviderResolver(),
            connectServer: connectServer,
            didConfigurePlaylist: didConfigurePlaylist
        )
        .id(profileID)
    }
}
#endif
