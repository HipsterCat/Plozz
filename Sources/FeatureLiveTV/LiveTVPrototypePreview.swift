#if DEBUG
import CoreUI
import FeatureLiveTVCore
import SwiftUI

struct PrototypePreviewLayout {
    let contentWidth: CGFloat
    let heroHeight: CGFloat
    let videoFrame: CGRect
    let stacked: Bool

    init(size: CGSize, largeText: Bool, metadataHeight: CGFloat) {
        let inset = PrototypeLayout.inset
        #if os(tvOS)
        contentWidth = max(1, size.width - inset * 2 - PrototypeLayout.controlsWidth - PrototypeLayout.gap)
        #else
        contentWidth = max(1, size.width - inset * 2)
        #endif
        stacked = contentWidth < 650 || largeText
        if stacked {
            let videoWidth = min(contentWidth, size.height * 0.3 * 16 / 9)
            let videoHeight = videoWidth * 9 / 16
            heroHeight = videoHeight + metadataHeight
            videoFrame = CGRect(
                x: inset + (contentWidth - videoWidth) / 2, y: inset,
                width: videoWidth, height: videoHeight
            )
        } else {
            let videoHeight = min(size.height * 0.31, contentWidth * 0.57 * 9 / 16)
            heroHeight = videoHeight
            videoFrame = CGRect(
                x: inset + contentWidth - videoHeight * 16 / 9, y: inset,
                width: videoHeight * 16 / 9, height: videoHeight
            )
        }
    }
}

struct PrototypePreviewHero: View {
    let channel: LiveTVPrototypeChannel?
    let program: LiveTVPrototypeProgram?
    let hasPlayer: Bool
    let followsFocus: Bool
    let layout: PrototypePreviewLayout
    let watch: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        ZStack(alignment: layout.stacked ? .bottomLeading : .leading) {
            if !hasPlayer {
                PrototypePreviewPlaceholder(channel: channel)
                    .frame(width: layout.videoFrame.width, height: layout.videoFrame.height)
                    .frame(
                        maxWidth: .infinity, maxHeight: .infinity,
                        alignment: layout.stacked ? .top : .topTrailing
                    )
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
                if let channel {
                    if !layout.stacked {
                        HStack(spacing: PrototypeLayout.gap) {
                            PrototypeStationMark(channel: channel, size: 48)
                            Label(
                                !hasPlayer ? "Channel" : (followsFocus ? "Live preview" : "Current channel"),
                                systemImage: "antenna.radiowaves.left.and.right"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)
                        }
                    }
                    Text(channel.name)
                        .font(layout.stacked ? .headline : .title.bold())
                        .lineLimit(layout.stacked ? 1 : 2)
                    Text(program?.title ?? channel.category)
                        .font(layout.stacked ? .subheadline : .title3)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(layout.stacked ? 1 : 2)
                    if !layout.stacked, let program {
                        Text("\(program.start, format: .dateTime.hour().minute()) – \(program.end, format: .dateTime.hour().minute())")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.secondaryText)
                    }
                    #if os(iOS)
                    if !layout.stacked {
                        Button("Watch channel", systemImage: "arrow.up.left.and.arrow.down.right", action: watch)
                            .buttonStyle(PrototypeButtonStyle())
                    }
                    #endif
                } else {
                    Text("Find your next channel").font(.title2.bold())
                    Text("Browse by channel, genre or what's on.")
                        .font(.subheadline).foregroundStyle(palette.secondaryText)
                }
            }
            .frame(
                maxWidth: layout.stacked ? .infinity : max(1, layout.contentWidth - layout.videoFrame.width - PrototypeLayout.gap * 2),
                alignment: .leading
            )
        }
        .frame(width: layout.contentWidth, height: layout.heroHeight)
    }
}

#if os(iOS)
struct PrototypePreviewExpandButton: View {
    let watch: () -> Void

    var body: some View {
        Button(action: watch) {
            Color.clear
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(12)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open channel full screen")
    }
}
#endif

private struct PrototypePreviewPlaceholder: View {
    let channel: LiveTVPrototypeChannel?
    @Environment(\.themePalette) private var palette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.backgroundSecondary, palette.backgroundBase],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
            if let channel {
                PrototypeStationMark(channel: channel, size: 76)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(palette.secondaryText.opacity(0.4))
            }
        }
    }
}
#endif
