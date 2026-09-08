#if DEBUG && os(tvOS)
import CoreModels
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
    let onExpandedChange: (Bool) -> Void

    @State private var hidesNavigation = false
    private let preferencesStore: LiveTVPreferencesStore
    private let viewSettingsStore: LiveTVViewSettingsStore

    init(
        isActive: Bool,
        profileID: String,
        preferencesNamespace: String?,
        onExpandedChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.isActive = isActive
        self.profileID = profileID
        self.onExpandedChange = onExpandedChange
        self.preferencesStore = LiveTVPreferencesStore(namespace: preferencesNamespace)
        self.viewSettingsStore = LiveTVViewSettingsStore(namespace: preferencesNamespace)
    }

    var body: some View {
        LiveTVPrototypeView(
            isActive: isActive,
            preferencesStore: preferencesStore,
            viewSettingsStore: viewSettingsStore,
            onExpandedChange: updateExpandedState
        ) { playback in
            LiveChannelPlayerView(
                channelID: playback.channel.id,
                title: playback.channel.name,
                streamURL: playback.streamURL,
                logoURL: playback.channel.logoURL,
                httpHeaders: playback.channel.httpHeaders,
                makeEngine: { try PlozzigenVideoEngine() },
                onPreviousChannel: playback.previousChannel,
                onNextChannel: playback.nextChannel,
                isFavorite: playback.isFavorite,
                canToggleFavorite: playback.canToggleFavorite,
                onToggleFavorite: playback.onToggleFavorite,
                isExpanded: playback.isExpanded,
                onReturnToGuide: playback.returnToGuide,
                playPauseRequest: playback.playPauseRequest,
                onPlaybackStarted: playback.playbackStarted
            )
        }
        .id(profileID)
        .toolbar(hidesNavigation ? .hidden : .visible, for: .tabBar)
        .onChange(of: isActive, initial: true) { _, active in
            if !active {
                updateExpandedState(false)
            }
        }
        .onDisappear {
            updateExpandedState(false)
        }
    }

    private func updateExpandedState(_ expanded: Bool) {
        hidesNavigation = expanded && isActive
        guard isActive else { return }
        onExpandedChange(expanded)
    }
}
#endif
