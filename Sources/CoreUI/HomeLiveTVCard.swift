#if canImport(SwiftUI)
import CoreModels
import SwiftUI

private struct HomeLiveTVSnapshotKey: EnvironmentKey {
    static let defaultValue = HomeLiveTVSnapshot.empty
}

private struct HomeLiveTVSelectionKey: EnvironmentKey {
    static let defaultValue: @MainActor (HomeLiveTVRoute) -> Void = { _ in }
}

public extension EnvironmentValues {
    var homeLiveTVSnapshot: HomeLiveTVSnapshot {
        get { self[HomeLiveTVSnapshotKey.self] }
        set { self[HomeLiveTVSnapshotKey.self] = newValue }
    }
    var openHomeLiveTV: @MainActor (HomeLiveTVRoute) -> Void {
        get { self[HomeLiveTVSelectionKey.self] }
        set { self[HomeLiveTVSelectionKey.self] = newValue }
    }
}

/// An intentionally non-VOD card: a channel logo, never a playback
/// preview. The broadcast badge makes its one-press tune behavior explicit.
public struct HomeLiveTVCard: View {
    public let channel: HomeLiveTVChannel
    public let width: CGFloat
    private let onFocused: ((HomeLiveTVChannel) -> Void)?
    @Environment(\.themePalette) private var palette
    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.plozzCardFocusStyle) private var focusStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openHomeLiveTV) private var open
    @FocusState private var isFocused: Bool

    public init(
        channel: HomeLiveTVChannel, width: CGFloat,
        onFocused: ((HomeLiveTVChannel) -> Void)? = nil
    ) {
        self.channel = channel
        self.width = width
        self.onFocused = onFocused
    }

    public var body: some View {
        control
            .onChange(of: isFocused) { _, focused in
                if focused { onFocused?(channel) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: channel.name) + Text(", Live TV"))
            .accessibilityHint("Watch this channel")
            .accessibilityIdentifier("home-live-channel-\(channel.route.channelID)")
    }

    @ViewBuilder
    private var control: some View {
        #if os(tvOS)
        if focusStyle.usesSystemEffect {
            Button { open(channel.route) } label: { label }
                .buttonStyle(.card)
                .focused($isFocused)
                .frame(width: width, height: width * 9 / 16)
        } else {
            label
                .plozzFocusHalo(
                    cornerRadius: metrics.landscapeCardCornerRadius,
                    focusScale: reduceMotion ? 1 : PlozzTheme.Metrics.mediumFocusedCardScale,
                    isFocused: isFocused
                )
                .focusableCard(
                    isFocused: $isFocused, cornerRadius: metrics.landscapeCardCornerRadius,
                    action: { open(channel.route) }
                )
                .frame(width: width, height: width * 9 / 16)
                .zIndex(isFocused ? 1 : 0)
                .plozzCardFocusTransition(isFocused: isFocused, animates: !reduceMotion)
        }
        #else
        Button { open(channel.route) } label: { label }
            .buttonStyle(.plain)
        #endif
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: width * 0.025) {
            HStack {
                Label("Live", systemImage: "antenna.radiowaves.left.and.right")
                Spacer(minLength: 0)
                if channel.number > 0 {
                    Text(verbatim: String(channel.number)).monospacedDigit()
                }
            }
            .font(.caption.weight(.semibold))
            HStack(spacing: width * 0.04) {
                #if canImport(UIKit)
                ChannelLogoArtwork(
                    name: channel.name, logoURL: channel.logoURL,
                    size: CGSize(width: width * 0.30, height: width * 0.24),
                    cornerRadius: metrics.landscapeCardCornerRadius * 0.5
                )
                #endif
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: channel.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(verbatim: channel.sourceName)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(width * 0.055)
        .frame(width: width, height: width * 9 / 16, alignment: .leading)
        .foregroundStyle(palette.primaryText)
        .background {
            #if os(tvOS)
            if !focusStyle.usesSystemEffect {
                fallbackSurface
            }
            #else
            fallbackSurface
            #endif
        }
    }

    private var fallbackSurface: some View {
        RoundedRectangle(cornerRadius: metrics.landscapeCardCornerRadius)
            .fill(palette.cardSurface)
            .overlay {
                RoundedRectangle(cornerRadius: metrics.landscapeCardCornerRadius)
                    .strokeBorder(palette.cardBorder, lineWidth: 1)
            }
    }
}
#endif
