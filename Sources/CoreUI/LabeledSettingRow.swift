#if canImport(SwiftUI)
import SwiftUI

/// A compact settings row: a minimum-width title column on the leading
/// edge and an arbitrary control (pills, a stepper, a menu, a toggle…) trailing
/// it. Stacking a header label *above* every control eats a lot of vertical
/// space in the 10-foot UI; laying the label beside the control instead lets a
/// whole settings panel breathe on one screen.
///
/// TV rows stack when the label and control cannot fit side by side.
/// The title column has a shared minimum width so controls line up down the panel. Pass an
/// optional `subtitle` for a secondary line of helper text under the title.
/// Pair the trailing slot with ``SettingsOptionPicker`` for the common
/// "label + pills" row.
public struct LabeledSettingRow<Trailing: View>: View {
    private let title: LocalizedStringResource
    private let subtitle: LocalizedStringResource?
    private let labelWidth: CGFloat
    private let trailingAlignment: Alignment
    private let trailing: Trailing

    /// - Parameters:
    ///   - title: The leading label.
    ///   - subtitle: Optional helper text shown under the title.
    ///   - labelWidth: Width of the fixed title column so rows align. Defaults to
    ///     a value tuned for the Settings panels.
    ///   - trailingAlignment: How the trailing control sits in its column.
    ///     Defaults to `.leading` (hugs the label). Pass `.trailing` for dropdown
    ///     "button menus" so they align to the right edge of the row.
    ///   - trailing: The control shown to the right of the label.
    public init(
        _ title: LocalizedStringResource,
        subtitle: LocalizedStringResource? = nil,
        labelWidth: CGFloat = 240,
        trailingAlignment: Alignment = .leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.labelWidth = labelWidth
        self.trailingAlignment = trailingAlignment
        self.trailing = trailing()
    }

    public var body: some View {
        #if os(tvOS)
        ViewThatFits(in: .horizontal) {
            horizontalRow
            VStack(alignment: .leading, spacing: SettingsFormMetrics.relatedControlSpacing) {
                label(wrapping: true)
                trailing
                    .frame(maxWidth: .infinity, alignment: trailingAlignment)
            }
        }
        .settingsFormTextLayout()
        #else
        horizontalRow
        #endif
    }

    private var horizontalRow: some View {
        HStack(alignment: .center, spacing: 24) {
            label(wrapping: false)
            trailing
                .frame(maxWidth: .infinity, alignment: trailingAlignment)
        }
    }

    private func label(wrapping: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SettingsRowMetrics.titleFont)
                .lineLimit(wrapping ? nil : 1)
                .fixedSize(horizontal: !wrapping, vertical: wrapping)
            if let subtitle {
                Text(subtitle)
                    #if os(tvOS)
                    .font(SettingsRowMetrics.helperFont)
                    .settingsRowSecondary()
                    #else
                    .font(.footnote)
                    .plozzForeground(.secondary)
                    #endif
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(
            minWidth: wrapping ? 0 : labelWidth,
            maxWidth: wrapping ? .infinity : nil,
            alignment: .leading
        )
    }
}

#endif
