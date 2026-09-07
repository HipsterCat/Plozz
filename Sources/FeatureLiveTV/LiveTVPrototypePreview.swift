#if DEBUG
import CoreUI
import FeatureLiveTVCore
import SwiftUI

struct PrototypePreviewLayout {
    let bounds: CGRect
    let contentFrame: CGRect
    let heroHeight: CGFloat
    let videoFrame: CGRect
    let metadataWidth: CGFloat
    let compact: Bool

    init(
        size: CGSize, safeAreaInsets: EdgeInsets = EdgeInsets(),
        navigationInset: CGFloat = 0, largeText: Bool = false
    ) {
        bounds = CGRect(
            x: -safeAreaInsets.leading, y: -safeAreaInsets.top,
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
        compact = bounds.width < 650
        #if os(tvOS)
        let side: CGFloat = 32
        let top = max(32, safeAreaInsets.top)
        let bottom: CGFloat = 20
        #else
        let side = max(16, max(safeAreaInsets.leading, safeAreaInsets.trailing))
        let top = max(12, safeAreaInsets.top)
        let bottom = max(12, safeAreaInsets.bottom)
        #endif
        contentFrame = CGRect(
            x: bounds.minX + side + navigationInset, y: bounds.minY + top,
            width: max(1, bounds.width - side * 2 - navigationInset),
            height: max(1, bounds.height - top - bottom)
        )
        heroHeight = min(
            contentFrame.height * (largeText ? 0.48 : 0.28),
            largeText ? 440 : (compact ? 200 : 260)
        )
        metadataWidth = compact || largeText ? contentFrame.width : contentFrame.width * 0.56
        let videoWidth = compact ? bounds.width : bounds.width * 0.72
        let videoHeight = videoWidth * 9 / 16
        videoFrame = CGRect(
            x: bounds.maxX - videoWidth,
            y: compact ? contentFrame.minY : contentFrame.minY + heroHeight * 0.58 - videoHeight * 0.5,
            width: videoWidth, height: videoHeight
        )
    }
}

/// The player stays mounted beneath this scrim; watching only removes the guide.
struct PrototypePreviewScrim: View {
    let layout: PrototypePreviewLayout
    let reduceTransparency: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            HeroLegibilityScrim(
                tone: palette.backgroundBase, edgePeak: 0.96, wash: 0.08,
                edges: [.leading], bottomFadeTop: 0.3
            )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: palette.backgroundBase.opacity(0.12), location: 0.35),
                    .init(color: palette.backgroundBase.opacity(0.7), location: 0.68),
                    .init(color: palette.backgroundBase, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: layout.contentFrame.minY - layout.bounds.minY + layout.heroHeight + 20)
            VStack(spacing: 0) {
                Color.clear.frame(height: layout.contentFrame.minY - layout.bounds.minY + layout.heroHeight)
                palette.backgroundBase
            }
            if reduceTransparency {
                palette.backgroundBase
                    .frame(width: layout.metadataWidth + 48, height: layout.heroHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, layout.contentFrame.minY - layout.bounds.minY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PrototypePreviewHero: View {
    let channel: LiveTVPrototypeChannel?
    let program: LiveTVPrototypeProgram?
    let isPlaying: Bool
    let layout: PrototypePreviewLayout
    let watch: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
            if let channel {
                HStack(spacing: PrototypeLayout.smallGap) {
                    PrototypeStationMark(channel: channel, size: 72)
                    Text(channel.name).lineLimit(1)
                    if isPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .accessibilityLabel("Current channel")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.secondaryText)
                Text(program?.title ?? channel.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: PrototypeLayout.gap) {
                    Text(channel.category).lineLimit(1)
                    if let program {
                        Text("\(program.start, format: .dateTime.hour().minute()) – \(program.end, format: .dateTime.hour().minute())")
                            .monospacedDigit().lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                if let program, !program.subtitle.isEmpty {
                    Text(program.subtitle)
                        .font(.subheadline).lineLimit(2)
                        .foregroundStyle(palette.secondaryText)
                }
                #if os(iOS)
                Button("Watch channel", systemImage: "arrow.up.left.and.arrow.down.right", action: watch)
                    .font(.subheadline)
                    .buttonStyle(PrototypeButtonStyle())
                #endif
            } else {
                Text("Find your next channel").font(.title2.weight(.semibold))
                Text("Browse by channel, genre or what's on.")
                    .font(.subheadline).foregroundStyle(palette.secondaryText)
            }
        }
        .frame(width: layout.metadataWidth, alignment: .leading)
        .frame(width: layout.contentFrame.width, height: layout.heroHeight, alignment: .bottomLeading)
        .clipped()
    }
}

#endif
