#if DEBUG
import CoreUI
import SwiftUI

struct LiveTVSetupWelcome: View {
    let addPlaylist: () -> Void
    let useServer: () -> Void
    let tryFreeChannels: () -> Void
    var issue: LocalizedStringResource? = nil
    @Environment(\.themePalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    LiveTVSetupIntroduction()
                    let layout = geometry.size.width >= 900 && !typeSize.isAccessibilitySize
                        ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                        : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                    layout {
                        LiveTVSetupChoice(
                            title: "Add an IPTV playlist",
                            detail: "Use an M3U link from your provider. Add a program guide now or later.",
                            symbol: "list.bullet.rectangle",
                            action: addPlaylist
                        )
                        LiveTVSetupChoice(
                            title: "Use a media server",
                            detail: "Choose Live TV from Jellyfin, Emby or Plex. Your server needs a configured Live TV source.",
                            symbol: "server.rack",
                            action: useServer
                        )
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Try free channels", systemImage: "play.rectangle", action: tryFreeChannels)
                            .buttonStyle(PrototypeButtonStyle(surface: .control))
                        Text("Start with a public US playlist. Channels and guide availability vary by region.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                        if let issue {
                            Label {
                                Text(issue)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                            }
                        }
                    }
                    LiveTVNoGuideExplanation()
                }
                .frame(maxWidth: 1_160, alignment: .leading)
                .padding(geometry.size.width >= 900 ? 48 : 24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.backgroundBase)
        .foregroundStyle(palette.primaryText)
        .accessibilityIdentifier("live-tv-source-welcome")
    }
}

private struct LiveTVSetupIntroduction: View {
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Live TV", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(palette.accent)
            Text("Bring your channels to Plozz")
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Connect your own source, or start with free channels. Nothing loads until you choose a source.")
                .font(.title3)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LiveTVSetupChoice: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .medium))
                    .frame(height: 44, alignment: .leading)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .padding(PrototypeLayout.sectionGap)
            .contentShape(RoundedRectangle(cornerRadius: PrototypeLayout.guideRadius, style: .continuous))
        }
        .plozzCardButton(cornerRadius: PrototypeLayout.guideRadius)
    }
}

struct LiveTVNoGuideExplanation: View {
    @Environment(\.themePalette) private var palette

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 8) {
                Text("No guide? No problem.")
                    .font(.headline)
                Text("Browse channel names, logos and categories. Search and Favorites work with or without program listings.")
                    .font(.body)
                    .foregroundStyle(palette.secondaryText)
            }
        } icon: {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(palette.accent)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
