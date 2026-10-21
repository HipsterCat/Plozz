#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import PlozzCoreUI

/// Equal-weight native choices keep every presentation visible without a separate layout control.
struct ContinueWatchingArtworkPicker: View {
    @Binding var style: ContinueWatchingArtworkStyle
    var playbackDetails: ContinueWatchingPlaybackDetails = .default
    var captions: CardCaptionSettings = .default
    var isShowcase = false
    @Environment(\.themePalette) private var palette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesRows: Bool {
        #if os(tvOS)
        false
        #else
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
        #endif
    }

    private var widePreviewHeight: CGFloat {
        #if os(tvOS)
        240
        #else
        200
        #endif
    }

    var body: some View {
        let layout = usesRows
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            ForEach(ContinueWatchingArtworkStyle.allCases, id: \.self) { option in
                Button { style = option } label: {
                    optionLabel(option)
                        .padding(.horizontal, 12)
                        .padding(.vertical, usesRows ? 8 : 12)
                        .contentShape(RoundedRectangle(cornerRadius: PlozzTheme.Metrics.Radius.panel))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(option.displayName))
                }
                .buttonStyle(ThemeCardButtonStyle(
                    accent: palette.accent,
                    isSelected: style == option,
                    cornerRadius: PlozzTheme.Metrics.Radius.panel
                ))
                .focusEffectDisabled()
                .accessibilityLabel(Text(option.displayName))
                .accessibilityHint(Text(option.detail))
                .accessibilityAddTraits(style == option ? .isSelected : [])
                .accessibilityIdentifier("continue-watching-style-\(option.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func optionLabel(_ option: ContinueWatchingArtworkStyle) -> some View {
        if usesRows {
            HStack(spacing: 12) {
                swatch(option).frame(width: 120, height: 128)
                VStack(alignment: .leading, spacing: 6) {
                    Text(option.displayName).font(.headline)
                    Text(option.detail).font(.footnote).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                selectionMark(option)
            }
            .multilineTextAlignment(.leading)
        } else {
            VStack(spacing: 12) {
                swatch(option).frame(height: widePreviewHeight)
                HStack(spacing: 8) {
                    ZStack {
                        ForEach(ContinueWatchingArtworkStyle.allCases, id: \.self) { candidate in
                            Text(candidate.displayName).hidden().accessibilityHidden(true)
                        }
                        Text(option.displayName)
                    }
                    .font(SettingsRowMetrics.optionFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    selectionMark(option)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    private func swatch(_ option: ContinueWatchingArtworkStyle) -> some View {
        ContinueWatchingArtworkSwatch(
            style: option, cornerRadius: PlozzTheme.Metrics.Radius.content, playbackDetails: playbackDetails,
            showsCaptions: option.showsCaptions(settings: captions, isShowcase: isShowcase)
        )
        .accessibilityHidden(true)
    }

    private func selectionMark(_ option: ContinueWatchingArtworkStyle) -> some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .opacity(style == option ? 1 : 0)
            .accessibilityHidden(true)
    }
}
#endif
