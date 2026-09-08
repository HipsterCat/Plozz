#if DEBUG
import CoreUI
import SwiftUI

struct LiveTVSetupWelcome: View {
    let addPlaylist: () -> Void
    let useServer: () -> Void
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
                            detail: "M3U URL",
                            symbol: "list.bullet.rectangle",
                            action: addPlaylist
                        )
                        LiveTVSetupChoice(
                            title: "Use a media server",
                            detail: "Jellyfin, Emby or Plex",
                            symbol: "server.rack",
                            action: useServer
                        )
                    }
                    if let issue {
                        Label {
                            Text(issue)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
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
            Text("Add your channels")
                .font(.largeTitle.weight(.semibold))
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
            SettingsRowLabel(icon: symbol, title: title, secondary: {
                Text(detail)
                    .font(.callout)
                    .settingsRowSecondary()
                    .fixedSize(horizontal: false, vertical: true)
            })
        }
        .buttonStyle(SettingsCardButtonStyle())
    }
}

#endif
