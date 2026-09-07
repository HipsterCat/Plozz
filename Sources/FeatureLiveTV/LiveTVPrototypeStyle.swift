#if DEBUG
import CoreUI
import CoreModels
import FeatureLiveTVCore
import SwiftUI

enum PrototypeLayout {
    static let gap = PlozzTheme.Spacing.medium
    static let smallGap = PlozzTheme.Spacing.xSmall
    static let radius = PlozzTheme.Metrics.cornerRadius
    #if os(tvOS)
    static let inset = PlozzTheme.Spacing.xLarge
    static let stationSize: CGFloat = 64
    static let rowHeight: CGFloat = 100
    static let controlsWidth: CGFloat = 270
    #else
    static let inset = PlozzTheme.Spacing.medium
    static let stationSize: CGFloat = 48
    static let rowHeight: CGFloat = 80
    static let controlsWidth: CGFloat = 260
    #endif
}

extension LiveTVPrototypeSource {
    var title: LocalizedStringResource {
        switch self {
        case .iptv: "IPTV"
        case .jellyfin: "Jellyfin"
        case .plex: "Plex"
        case .emby: "Emby"
        case .plozz: "Plozz channels"
        }
    }
}

extension LiveTVPrototypeScenario {
    var title: LocalizedStringResource {
        switch self {
        case .noGuide: "No guide"
        case .mixedGuide: "Partial guide"
        case .fullGuide: "Full guide"
        case .staleGuide: "Stale guide"
        case .failedGuide: "Guide unavailable"
        }
    }
}

extension LiveTVPrototypeSort {
    var title: LocalizedStringResource {
        switch self {
        case .channelNumber: "Channel number"
        case .name: "Name"
        }
    }
}

struct PrototypeStationMark: View {
    let channel: LiveTVPrototypeChannel
    var size: CGFloat = PrototypeLayout.stationSize

    var body: some View {
        FallbackAsyncImage(
            references: channel.logoURL.map { [.remote($0)] } ?? [],
            variant: .serviceLogo
        ) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Text(channel.name)
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .foregroundStyle(channel.logoNeedsDarkBackground ? .white : .black)
        }
            .padding(size * 0.15)
            .frame(width: size * 1.75, height: size)
            // Preserve transparent black wordmarks rather than recoloring station artwork.
            .background(
                channel.logoNeedsDarkBackground ? Color.black : Color.white,
                in: RoundedRectangle(cornerRadius: size * 0.16)
            )
            .accessibilityHidden(true)
    }
}

struct PrototypeButtonStyle: ButtonStyle {
    var selected = false
    var padded = true

    func makeBody(configuration: Configuration) -> some View {
        PrototypeButtonBody(configuration: configuration, selected: selected, padded: padded)
    }
}

private struct PrototypeButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    let padded: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.themePalette) private var palette

    var body: some View {
        configuration.label
            .foregroundStyle(focused ? palette.onAccent : palette.primaryText)
            .padding(padded ? PrototypeLayout.gap : 0)
            .background(
                focused ? palette.accent : (selected ? palette.fill : palette.cardSurface),
                in: RoundedRectangle(cornerRadius: PrototypeLayout.radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PrototypeLayout.radius)
                    .strokeBorder(selected && !focused ? palette.accent.opacity(0.5) : .clear)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            // Directional entry gates remove candidates without dimming the rail.
            .transaction { $0.animation = nil }
    }
}

enum PrototypeTab: String, CaseIterable, Identifiable {
    case channels, guide
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .channels: "Channels"
        case .guide: "Guide"
        }
    }
}

enum PrototypeSheet: Identifiable {
    case search, filters, sources
    case program(LiveTVPrototypeProgram)

    var id: String {
        switch self {
        case .search: "search"
        case .filters: "filters"
        case .sources: "sources"
        case .program(let program): program.id
        }
    }
}
#endif
