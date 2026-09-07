#if DEBUG && os(tvOS)
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
    let onExpandedChange: (Bool) -> Void

    @State private var isExpanded = false

    init(
        isActive: Bool,
        onExpandedChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.isActive = isActive
        self.onExpandedChange = onExpandedChange
    }

    var body: some View {
        LiveTVPrototypeView(
            isActive: isActive,
            onExpandedChange: updateExpandedState
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
                updateExpandedState(false)
            }
        }
        .onDisappear {
            updateExpandedState(false)
        }
    }

    private func updateExpandedState(_ expanded: Bool) {
        isExpanded = expanded && isActive
        guard isActive else { return }
        onExpandedChange(expanded)
    }
}
#endif
