#if DEBUG && os(iOS)
import EnginePlozzigen
import FeatureLiveTV
import FeaturePlayback
import SwiftUI

/// Development-only Live TV destination hosted by the real iPhone/iPad tab shell.
struct PlozziOSLiveTVDestination: View {
    let isActive: Bool

    @State private var isExpanded = false

    var body: some View {
        LiveTVPrototypeView(
            isActive: isActive,
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
                playPauseRequest: playback.playPauseRequest
            )
        }
        .toolbar(isExpanded ? .hidden : .visible, for: .tabBar)
        .onChange(of: isActive, initial: true) { _, active in
            if !active {
                isExpanded = false
            }
        }
    }
}
#endif
