#if canImport(SwiftUI)
import SwiftUI
import PlozzCoreUI

/// A connected, segmented "pick one of a few" control for the Settings detail
/// pane.
///
/// Unlike ``SettingsOptionPicker`` (separate pills), this draws a single rounded
/// track split into segments — the iOS segmented idiom — so a short, fixed
/// choice (e.g. a subtitle mode: Off / On / Forced Only) reads unmistakably as
/// one multiple-choice control, distinct from the chevroned navigation rows and
/// the switch toggles.
///
/// ## Interaction (press to commit — focus and selection are decoupled)
/// This behaves like every other tvOS control, because on tvOS focus is purely
/// spatial: moving focus across the segments changes **nothing**; you press
/// **Select** to commit the focused segment. A left press at the leading edge
/// just leaves the control back to the master list (standard), and moving
/// up/down to a neighbouring control never grabs the wrong value because focus
/// doesn't drive selection.
///
/// ## Look (monochrome, theme-aware)
/// Two independent, non-competing indicators:
/// * **Focus** — the segment you're on wears the same theme-aware bright thumb
///   as every other Settings row (WHITE thumb + black text in dark themes, BLACK
///   thumb + white text in light themes), without enlarging the control.
/// * **Selection** — the chosen segment carries a trailing checkmark (matching
///   other settings choices), with no colour. Only the selected segment makes
///   room for the mark; selection animates that space between segments.
///
/// Best for 2–5 short options. For long labels or many options prefer a menu or
/// a vertical list instead.
struct SettingsSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> LocalizedStringResource
    /// Reports the option under focus as the user moves across the segments —
    /// before any Select/commit — and `nil` when focus leaves the control. Lets a
    /// caller mirror the focused option's own description live, decoupled from
    /// `selection` (which only changes on Select).
    var onFocusedOptionChange: ((Option?) -> Void)? = nil

    @FocusState private var focusedOption: Option?
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        SegmentLabel(
                            text: title(option),
                            isSelected: option == selection
                        )
                    }
                    .buttonStyle(SegmentButtonStyle(isSelected: option == selection))
                    .focused($focusedOption, equals: option)
                    .accessibilityValue(option == selection ? Text("Selected") : Text(verbatim: ""))
                }
            }
            .padding(SettingsRowMetrics.segmentedTrackInset)
            .background(
                Capsule(style: .continuous)
                    .fill(palette.cardSurface.opacity(0.45))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(palette.cardBorder.opacity(0.8), lineWidth: 1)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selection)
        }
        .scrollClipDisabled()
        // English fits without scrolling; longer translations scroll the focused
        // segment fully into view instead of drawing beyond the detail pane.
        .frame(maxWidth: .infinity, alignment: .leading)
        // Surface focus movement so a caller can live-update a description of the
        // focused option — decoupled from selection, which only changes on Select.
        .onChange(of: focusedOption) { _, newValue in
            onFocusedOptionChange?(newValue)
        }
    }

    private struct SegmentLabel: View {
        let text: LocalizedStringResource
        let isSelected: Bool

        var body: some View {
            HStack(spacing: 8) {
                Text(text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if isSelected {
                    SettingsCheckmark(isChecked: true)
                        .transition(.opacity)
                }
            }
        }
    }

    /// Press-to-commit segment styling. Focus draws the theme-aware bright thumb
    /// (decoupled from selection); a merely-selected segment keeps a brighter
    /// label + checkmark on the plain track.
    private struct SegmentButtonStyle: ButtonStyle {
        let isSelected: Bool

        func makeBody(configuration: Configuration) -> some View {
            SegmentBody(configuration: configuration, isSelected: isSelected)
        }

        private struct SegmentBody: View {
            let configuration: ButtonStyle.Configuration
            let isSelected: Bool
            @Environment(\.isFocused) private var isFocused
            @Environment(\.colorScheme) private var colorScheme
            @Environment(\.themePalette) private var palette

            // Theme-aware focus thumb, mirroring `SettingsFocusButtonStyle`:
            // invert against the background so the highlight reads in every theme.
            private var focusThumbFill: Color { colorScheme == .dark ? .white : .black }
            private var focusThumbText: Color { colorScheme == .dark ? .black : .white }

            private var foreground: Color {
                if isFocused { return focusThumbText }
                if isSelected { return palette.primaryText }
                return palette.secondaryText
            }

            // Selection wears a subtle neutral fill (no colour) so the chosen
            // segment reads as a soft inset chip even from across the room; the
            // focus thumb still overrides it as the bright theme-aware highlight.
            private var segmentFill: Color {
                if isFocused { return focusThumbFill }
                if isSelected { return palette.primaryText.opacity(0.14) }
                return .clear
            }

            var body: some View {
                configuration.label
                    .font(SettingsRowMetrics.titleFont)
                    .foregroundStyle(foreground)
                    .frame(minHeight: SettingsRowMetrics.minHeight(.primary))
                    .padding(.horizontal, SettingsRowMetrics.spacing(.secondary))
                    .padding(
                        .vertical,
                        SettingsRowMetrics.verticalPadding(.primary) - SettingsRowMetrics.segmentedTrackInset
                    )
                    .background {
                        Capsule(style: .continuous)
                            .fill(segmentFill)
                            .shadow(
                                color: .black.opacity(isFocused ? 0.25 : 0),
                                radius: isFocused ? 8 : 0,
                                y: isFocused ? 3 : 0
                            )
                    }
                    .scaleEffect(configuration.isPressed ? 0.97 : 1)
                    .animation(.easeOut(duration: 0.16), value: isFocused)
                    .animation(.easeOut(duration: 0.16), value: isSelected)
                    .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            }
        }
    }
}
#endif
