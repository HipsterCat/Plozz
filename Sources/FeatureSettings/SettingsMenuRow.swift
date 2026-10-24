#if canImport(SwiftUI)
import PlozzCoreUI
import SwiftUI

/// A settings choice is one focusable row; the system still owns its menu.
/// Inline picker options override grouped containers that otherwise add a submenu.
struct SettingsMenuRow<Options: View>: View {
    let title: LocalizedStringResource
    let value: Text
    var subtitle: LocalizedStringResource? = nil
    var icon: String? = nil
    @ViewBuilder var options: () -> Options

    var body: some View {
        #if os(tvOS)
        Menu {
            options().pickerStyle(.inline)
        } label: {
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
        LabeledSettingRow(title, subtitle: subtitle, labelWidth: 0, trailingAlignment: .trailing) {
            Menu {
                options().pickerStyle(.inline)
            } label: {
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
