#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreUI

/// The compact, in-Settings picker for the watch-status indicator: a row of
/// preview cards (`PreviewCard` + `WatchStatusIndicatorSwatch`) that share the
/// detail pane's width, mirroring `CompactThemePicker`. Tapping a card selects
/// that indicator; the active one carries the same accent wash/ring the theme and
/// music-player pickers use.
struct CompactWatchIndicatorPicker: View {
    @Binding var selection: WatchStatusIndicator
    /// Height of the TV option illustrations; mobile uses one compact preview.
    var swatchHeight: CGFloat = 248
    @Environment(\.themePalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        #if os(iOS)
        VStack(spacing: 12) {
            WatchStatusIndicatorSwatch(indicator: selection)
                .frame(height: 96)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Watch indicator preview")
                .accessibilityValue(Text(selection.displayName))
                .accessibilityIdentifier("watch-indicator-preview")
            Picker("Watch indicators", selection: $selection) {
                ForEach(WatchStatusIndicator.allCases) { indicator in
                    Text(indicator.displayName).tag(indicator)
                        .accessibilityIdentifier("watch-indicator-option-\(indicator.rawValue)")
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("watch-indicator-picker")
        }
        #else
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            ForEach(WatchStatusIndicator.allCases) { indicator in
                PreviewCard(
                    title: indicator.displayName,
                    detail: indicator.detail,
                    isSelected: selection == indicator,
                    accent: palette.accent,
                    compact: true,
                    swatchHeight: swatchHeight,
                    action: { selection = indicator }
                ) {
                    WatchStatusIndicatorSwatch(
                        indicator: indicator,
                        cornerRadius: PlozzTheme.Metrics.Radius.content
                    )
                    .accessibilityHidden(true)
                }
                .accessibilityIdentifier("watch-indicator-preview-\(indicator.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}
#endif
