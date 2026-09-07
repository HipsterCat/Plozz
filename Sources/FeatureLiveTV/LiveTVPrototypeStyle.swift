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
    static let rowGap = PlozzTheme.Spacing.medium
    static let columnGap = PlozzTheme.Spacing.small
    static let cellGap = PlozzTheme.Spacing.xSmall
    static let rowInset = PlozzTheme.Spacing.medium
    static let logoRadius = PlozzTheme.Metrics.Radius.content
    static let rowRadius = logoRadius + rowInset
    static let programInset = PlozzTheme.Spacing.xSmall
    static let programRadius = rowRadius - programInset
    static let horizontalFade = PlozzTheme.Spacing.large
    static let verticalFade = PlozzTheme.Spacing.xLarge
    static let guideInset = PlozzTheme.Metrics.Radius.inset
    static let guideRadius = rowRadius + guideInset
    static let controlRadius = PlozzTheme.Metrics.Radius.control
    static let controlInset = PlozzTheme.Spacing.xSmall
    static let controlGroupRadius = controlRadius + controlInset
    #if os(tvOS)
    static let inset = PlozzTheme.Spacing.xLarge
    static let stationSize: CGFloat = 96
    static let controlHeight: CGFloat = 56
    static let guideFontSize: CGFloat = 26
    static let sectionFontSize: CGFloat = 22
    #else
    static let inset = PlozzTheme.Spacing.medium
    static let stationSize: CGFloat = 80
    static let controlHeight: CGFloat = 44
    static let guideFontSize: CGFloat = 16
    static let sectionFontSize: CGFloat = 14
    #endif
    static let rowHeight = stationSize + rowInset * 2
    static let stationColumnWidth = stationSize * 1.75 + rowInset * 2
    static var guideShape: UnevenRoundedRectangle {
        #if os(tvOS)
        let bottom: CGFloat = 0
        #else
        let bottom = guideRadius
        #endif
        return UnevenRoundedRectangle(
            topLeadingRadius: guideRadius, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: guideRadius
        )
    }

    static func stationWidth(for _: CGFloat) -> CGFloat {
        stationColumnWidth
    }

    static func timelineWidth(for width: CGFloat) -> CGFloat {
        max(1, width - stationWidth(for: width) - columnGap)
    }

    static func programHeight(in rowHeight: CGFloat) -> CGFloat {
        max(1, rowHeight - programInset * 2)
    }
}

extension LiveTVGuideSection {
    var title: LocalizedStringResource {
        switch self {
        case .recent: "Recently watched"
        case .favorites: "Favorites"
        case .channels: "Channels"
        }
    }
}

struct PrototypeScrollFade: Equatable {
    let leading: CGFloat
    let trailing: CGFloat

    init(before: CGFloat = 0, after: CGFloat = 0, distance: CGFloat = PrototypeLayout.verticalFade) {
        leading = min(1, max(0, before) / max(1, distance))
        trailing = min(1, max(0, after) / max(1, distance))
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
    var plateSize: CGSize? = nil
    var cornerRadius: CGFloat = PrototypeLayout.logoRadius
    @State private var resolvedTone: ResolvedLogoTone?

    private var dimensions: CGSize {
        plateSize ?? CGSize(width: size * 1.75, height: size)
    }

    private var artworkInset: CGFloat {
        plateSize == nil ? 6 : PrototypeLayout.guideInset
    }

    private var lightPlate: Bool {
        guard let resolvedTone else { return false }
        return PrototypeLogoPlate.usesLightBackground(
            luminance: resolvedTone.luminance, brightInk: resolvedTone.brightInk
        )
    }

    var body: some View {
        HeroLogoArtwork(
            primaryURL: channel.logoURL,
            maxWidth: dimensions.width - artworkInset * 2, maxHeight: dimensions.height - artworkInset * 2,
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
            .frame(width: dimensions.width, height: dimensions.height)
            .background(
                lightPlate ? Color.white : Color(white: 0.07),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
    case standard, guide, station, program, control
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
        focused && surface != .station
            && ((surface != .guide && surface != .program) || reduceTransparency || contrast == .increased)
    }

    private var cornerRadius: CGFloat {
        switch surface {
        case .standard: PrototypeLayout.radius
        case .guide, .station: PrototypeLayout.rowRadius
        case .program: PrototypeLayout.programRadius
        case .control: PrototypeLayout.controlRadius
        }
    }

    private var fill: Color {
        if solidFocus { return palette.accent }
        if focused || selected { return palette.fill }
        switch surface {
        case .standard: return palette.cardSurface
        case .guide, .station: return .clear
        case .program:
            return palette.fillSubtle.opacity(reduceTransparency || contrast == .increased ? 1 : 0.45)
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
                        focused && !solidFocus ? (surface == .station ? Color.white : palette.primaryText).opacity(0.9)
                            : (selected && !focused ? palette.accent.opacity(0.35) : .clear),
                        lineWidth: focused ? (surface == .station && contrast == .increased ? 4 : 2.5) : 1
                    )
                    .shadow(color: surface == .station && focused ? .black : .clear, radius: 1.5)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            // Directional entry gates remove candidates without dimming the rail.
            .transaction { $0.animation = nil }
    }
}

struct PrototypeGuideSurface: View {
    @Environment(\.plozzReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.themePalette) private var palette

    var body: some View {
        Group {
            if reduceTransparency || contrast == .increased {
                Color.clear.plozzSurface(.raised, cornerRadius: 0)
                    .clipShape(PrototypeLayout.guideShape)
            } else {
                PrototypeLayout.guideShape
                    .fill(LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: palette.backgroundBase.opacity(0.12), location: 0.2),
                            .init(color: palette.backgroundBase.opacity(0.4), location: 0.55),
                            .init(color: palette.backgroundBase.opacity(0.75), location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
