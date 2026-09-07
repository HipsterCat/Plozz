#if DEBUG && os(iOS)
import CoreModels
import EnginePlozzigen
import FeatureLiveTV
import FeaturePlayback
import SwiftUI

/// Development-only Live TV destination hosted by the real iPhone/iPad tab shell.
struct PlozziOSLiveTVDestination: View {
    let isActive: Bool
    let profileID: String

    @State private var isExpanded = false
    private let preferencesStore: LiveTVPreferencesStore
    private let viewSettingsStore: LiveTVViewSettingsStore

    init(
        isActive: Bool,
        profileID: String,
        preferencesNamespace: String?
    ) {
        self.isActive = isActive
        self.profileID = profileID
        self.preferencesStore = LiveTVPreferencesStore(namespace: preferencesNamespace)
        self.viewSettingsStore = LiveTVViewSettingsStore(namespace: preferencesNamespace)
    }

    var body: some View {
        LiveTVPrototypeView(
            isActive: isActive,
            preferencesStore: preferencesStore,
            viewSettingsStore: viewSettingsStore,
            onExpandedChange: { isExpanded = $0 }
        ) { playback in
            LiveChannelPlayerView(
                channelID: playback.channel.id,
                title: playback.channel.name,
                streamURL: playback.streamURL,
                logoURL: playback.channel.logoURL,
                logoNeedsDarkBackground: playback.channel.logoNeedsDarkBackground,
                httpHeaders: playback.channel.httpHeaders,
                makeEngine: { try PlozzigenVideoEngine() },
                onPreviousChannel: playback.previousChannel,
                onNextChannel: playback.nextChannel,
                isExpanded: playback.isExpanded,
                onReturnToGuide: playback.returnToGuide,
                playPauseRequest: playback.playPauseRequest,
                onPlaybackStarted: playback.playbackStarted
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
#endif
