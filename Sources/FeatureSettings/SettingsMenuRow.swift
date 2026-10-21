#if canImport(SwiftUI)
import CoreUI
import SwiftUI

/// A settings choice is one focusable row; the system still owns its menu.
struct SettingsMenuRow<Options: View>: View {
    let title: LocalizedStringResource
    let value: Text
    var subtitle: LocalizedStringResource? = nil
    var icon: String? = nil
    @ViewBuilder var options: () -> Options

    var body: some View {
        #if os(tvOS)
        Menu(content: options) {
            SettingsSectionLabel(
                title: Text(title), icon: icon, assetIcon: nil,
                value: value, subtitle: subtitle.map(Text.init),
                accessorySymbol: "chevron.up.chevron.down"
            )
        }
        .menuStyle(.button)
        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
        .accessibilityLabel(Text(title))
        .accessibilityValue(value)
        #else
        LabeledSettingRow(title, subtitle: subtitle, trailingAlignment: .trailing) {
            Menu(content: options) {
                HStack {
                    if let icon { Image(systemName: icon) }
                    value
                }
            }
            .menuStyle(.button)
        }
        #endif
    }
}
#endif
