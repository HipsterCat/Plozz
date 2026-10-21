#if canImport(SwiftUI)
import SwiftUI

// MARK: - Platform-native settings toggles

/// A platform-aware `ToggleStyle` used across the app — the Settings detail
/// pane AND the onboarding library picker — so every real on/off control looks
/// consistent. iOS/iPadOS use the native switch without custom geometry or colors.
/// tvOS uses its native On/Off presentation with the shared settings row style.
public struct SettingsSwitchToggleStyle: ToggleStyle {
    @Environment(\.settingsFormRowsFlushLeading) private var groupFlushLeading
    /// When false the row does NOT pull its leading edge outward — pass this
    /// inside a bordered card so the focus card nests concentrically instead of
    /// hugging the card's border. Default true (flush-left, for the borderless
    /// split-detail panes where the title lines up with the pane heading).
    var flushLeading: Bool

    public init(flushLeading: Bool = true) {
        self.flushLeading = flushLeading
    }

    public func makeBody(configuration: Configuration) -> some View {
        #if os(iOS)
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(nil)
        #else
        Toggle(configuration)
            .toggleStyle(.automatic)
            .font(SettingsRowMetrics.titleFont)
            .buttonStyle(SettingsFormButtonStyle())
            .padding(.leading, flushLeading && groupFlushLeading ? -SettingsRowMetrics.horizontalPadding : 0)
        #endif
    }
}

/// An On/Off row with an explicit `canFocus` gate.
///
/// Unlike a stock `Toggle` (whose internal `Button` can't be removed from focus
/// with `.focusable(false)`, and where `.disabled` dims the row), this owns its
/// `Button` and renders with the custom `SettingsFocusButtonStyle`, which ignores
/// `\.isEnabled`. So `.disabled(!canFocus)` takes the control out of the focus
/// order **without** dimming it — letting a caller steer where a directional
/// focus move lands (e.g. keep this off the focus map until sibling controls have
/// been focused) while it still looks fully enabled.
public struct FocusGatedSwitch: View {
    private let title: LocalizedStringResource
    @Binding private var isOn: Bool
    private let canFocus: Bool
    @Environment(\.settingsFormRowsFlushLeading) private var flushLeading
    private var hInset: CGFloat { SettingsRowMetrics.horizontalPadding }

    public init(_ title: LocalizedStringResource, isOn: Binding<Bool>, canFocus: Bool = true) {
        self.title = title
        self._isOn = isOn
        self.canFocus = canFocus
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: SettingsRowMetrics.spacing(.primary)) {
                Text(title)
                    .font(SettingsRowMetrics.titleFont)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: SettingsRowMetrics.spacing(.primary))
                SettingsToggleValue(isOn: isOn)
            }
            .frame(minHeight: SettingsRowMetrics.minHeight(.primary))
            .padding(.vertical, SettingsRowMetrics.verticalPadding(.primary))
            .padding(.horizontal, hInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsFocusButtonStyle())
        .padding(.leading, flushLeading ? -hInset : 0)
        // Custom button style ignores `\.isEnabled`, so disabling only removes it
        // from the focus order — no dimming.
        .disabled(!canFocus)
    }
}

/// An On/Off action row with an arbitrary label.
///
/// Use this when "on/off" is really a **side-effectful action** rather than a
/// simple boolean binding — e.g. the per-profile server master switch, where one
/// press expands/collapses a whole card and mutates a multi-account set. A plain
/// `Button` makes the press path unambiguous on tvOS (a real `Toggle` with a
/// custom style drove nothing here), and reading `isOn` from live state each
/// render keeps it honest even when the hosting screen is a cached navigation
/// destination.
public struct SettingsSwitchButton<Label: View>: View {
    private let isOn: Bool
    private let flushLeading: Bool
    private let action: () -> Void
    @ViewBuilder private let label: () -> Label
    @Environment(\.settingsFormRowsFlushLeading) private var groupFlushLeading
    private var hInset: CGFloat { SettingsRowMetrics.horizontalPadding }

    public init(
        isOn: Bool,
        flushLeading: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.isOn = isOn
        self.flushLeading = flushLeading
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsRowMetrics.spacing(.primary)) {
                label()
                    .font(SettingsRowMetrics.titleFont)
                    .lineLimit(1)
                Spacer(minLength: SettingsRowMetrics.spacing(.primary))
                SettingsToggleValue(isOn: isOn)
            }
            .frame(minHeight: SettingsRowMetrics.minHeight(.primary))
            .padding(.vertical, SettingsRowMetrics.verticalPadding(.primary))
            .padding(.horizontal, hInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsFocusButtonStyle())
        .padding(.leading, flushLeading && groupFlushLeading ? -hInset : 0)
    }
}

private struct SettingsToggleValue: View {
    let isOn: Bool

    var body: some View {
        Group {
            if isOn { Text("On") }
            else { Text("Off") }
        }
        .font(SettingsRowMetrics.titleFont)
        .settingsRowSecondary()
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 48, alignment: .trailing)
    }
}
#endif
