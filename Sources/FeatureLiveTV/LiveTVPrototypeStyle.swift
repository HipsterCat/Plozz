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
    static let rowHeight: CGFloat = 76
    #else
    static let inset = PlozzTheme.Spacing.medium
    static let stationSize: CGFloat = 48
    static let rowHeight: CGFloat = 72
    #endif

    static func stationWidth(for width: CGFloat) -> CGFloat {
        width > 1_100 ? 320 : 260
    }
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
    @State private var resolvedTone: ResolvedLogoTone?

    private var lightPlate: Bool {
        guard let resolvedTone else { return false }
        return PrototypeLogoPlate.usesLightBackground(
            luminance: resolvedTone.luminance, brightInk: resolvedTone.brightInk
        )
    }

    var body: some View {
        HeroLogoArtwork(
            primaryURL: channel.logoURL,
            maxWidth: size * 1.75 - 12, maxHeight: size - 12,
            constrainsToBounds: true, alignment: .center, haloStyle: .gentle,
            onResolve: { resolvedTone = $0 }
        ) {
            Text(channel.name)
                .font(.system(size: size * 0.25, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(lightPlate ? .black : .white)
        }
            .environment(\.colorScheme, lightPlate ? .light : .dark)
            .frame(width: size * 1.75, height: size)
            .background(
                lightPlate ? Color.white : Color(white: 0.07),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .onChange(of: channel.logoURL) { _, _ in resolvedTone = nil }
            .accessibilityHidden(true)
    }
}

enum PrototypeLogoPlate {
    static func usesLightBackground(luminance: Double, brightInk: Double) -> Bool {
        luminance < 0.42 && brightInk < 0.20
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

enum PrototypeSheet: Identifiable {
    case search, filters, sources, options
    case program(LiveTVPrototypeProgram)

    var id: String {
        switch self {
        case .search: "search"
        case .filters: "filters"
        case .sources: "sources"
        case .options: "options"
        case .program(let program): program.id
        }
    }
}
#endif
