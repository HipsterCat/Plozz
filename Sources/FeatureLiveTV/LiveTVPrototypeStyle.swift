#if DEBUG
import CoreUI
import CoreModels
import FeatureLiveTVCore
import SwiftUI

enum PrototypeLayout {
    static let gap = PlozzTheme.Spacing.medium
    static let smallGap = PlozzTheme.Spacing.xSmall
    static let radius = PlozzTheme.Metrics.cornerRadius
    static let sectionGap = PlozzTheme.Spacing.large
    static let rowGap = PlozzTheme.Spacing.small
    static let columnGap = PlozzTheme.Spacing.small
    static let cellGap = PlozzTheme.Spacing.xSmall
    static let rowInset = PlozzTheme.Spacing.medium
    static let logoRadius = PlozzTheme.Metrics.Radius.content
    static let rowRadius = logoRadius + rowInset
    static let guideInset = PlozzTheme.Metrics.Radius.inset
    static let guideRadius = rowRadius + guideInset
    static let controlRadius = PlozzTheme.Metrics.Radius.control
    static let controlInset = PlozzTheme.Spacing.xSmall
    static let controlGroupRadius = controlRadius + controlInset
    #if os(tvOS)
    static let inset = PlozzTheme.Spacing.xLarge
    static let stationSize: CGFloat = 72
    static let controlHeight: CGFloat = 56
    #else
    static let inset = PlozzTheme.Spacing.medium
    static let stationSize: CGFloat = 64
    static let controlHeight: CGFloat = 44
    #endif
    static let rowHeight = stationSize + rowInset * 2

    static func stationWidth(for width: CGFloat) -> CGFloat {
        width > 1_100 ? 384 : 280
    }

    static func timelineWidth(for width: CGFloat) -> CGFloat {
        max(1, width - stationWidth(for: width) - columnGap)
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
                in: RoundedRectangle(cornerRadius: PrototypeLayout.logoRadius, style: .continuous)
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
    var surface: PrototypeButtonSurface = .standard

    func makeBody(configuration: Configuration) -> some View {
        PrototypeButtonBody(configuration: configuration, selected: selected, padded: padded, surface: surface)
    }
}

enum PrototypeButtonSurface: Equatable {
    case standard, guide, control
}

private struct PrototypeButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    let padded: Bool
    let surface: PrototypeButtonSurface
    @Environment(\.isFocused) private var focused
    @Environment(\.themePalette) private var palette
    @Environment(\.plozzReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var solidFocus: Bool {
        focused && (surface != .guide || reduceTransparency || contrast == .increased)
    }

    private var cornerRadius: CGFloat {
        switch surface {
        case .standard: PrototypeLayout.radius
        case .guide: PrototypeLayout.rowRadius
        case .control: PrototypeLayout.controlRadius
        }
    }

    private var fill: Color {
        if solidFocus { return palette.accent }
        if focused || selected { return palette.fill }
        switch surface {
        case .standard: return palette.cardSurface
        case .guide: return palette.fillSubtle
        case .control: return .clear
        }
    }

    var body: some View {
        configuration.label
            .foregroundStyle(solidFocus ? palette.onAccent : palette.primaryText)
            .padding(padded ? PrototypeLayout.gap : 0)
            .background(
                fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        focused && !solidFocus ? palette.primaryText.opacity(0.9)
                            : (selected && !focused ? palette.accent.opacity(0.35) : .clear),
                        lineWidth: focused ? 2.5 : 1
                    )
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            // Directional entry gates remove candidates without dimming the rail.
            .transaction { $0.animation = nil }
    }
}

/// One glass underlay, not a glass layer per programme or a focus-dependent style.
struct PrototypeControlSurface: View {
    @Environment(\.plozzReduceTransparency) private var reduceTransparency
    @Environment(\.plozzReducePanelGlass) private var reduceGlass

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PrototypeLayout.controlGroupRadius, style: .continuous)
        Group {
            if reduceTransparency {
                Color.clear.plozzSurface(.raised, cornerRadius: PrototypeLayout.controlGroupRadius)
            } else if reduceGlass {
                Color.clear.plozzFrostedBackground(shape).plozzFrostedBorder(shape)
            } else {
                Color.clear.plozzGlassPanel(cornerRadius: PrototypeLayout.controlGroupRadius)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
