#if canImport(SwiftUI)
import CoreModels
import PlozzCoreUI
import SwiftUI

public struct SkipMarkerSettingsControl: View {
    @Bindable private var model: PlaybackSettingsModel

    public init(model: PlaybackSettingsModel) {
        self.model = model
    }

    public var body: some View {
        #if os(tvOS)
        SettingsControlRows {
            SkipMarkerEnableControl(model: model)
            if model.settings.skipMarkersEnabled {
                SkipMarkerConfiguration(model: model)
            }
        }
        #else
        SettingsSectionGroup("Skip intros, credits & more") {
            SkipMarkerEnableControl(model: model)
            if model.settings.skipMarkersEnabled {
                SkipMarkerConfiguration(model: model)
            }
        }
        #endif
    }
}

private struct SkipMarkerEnableControl: View {
    @Bindable var model: PlaybackSettingsModel

    var body: some View {
        Toggle("Enable skipping", isOn: Binding(
            get: { model.settings.skipMarkersEnabled },
            set: { model.settings.setSkipMarkersEnabled($0) }
        ))
        .accessibilityIdentifier("skip-markers-enabled")
    }
}

private struct SkipMarkerConfiguration: View {
    @Bindable var model: PlaybackSettingsModel

    var body: some View {
        SettingsControlRows(nonTVSpacing: 20) {
            if model.settings.skipModeOverrides.isEmpty {
                SkipMarkerRuleControls(model: model, kind: nil)
            }
            SettingsDetailGroup(title: "Enable for") {
                ForEach([ContentCategory.movie, .tvShow, .anime], id: \.self) { category in
                    Toggle(isOn: Binding(
                        get: { model.settings.skipContentCategories.contains(category) },
                        set: { enabled in
                            if enabled { model.settings.skipContentCategories.insert(category) }
                            else { model.settings.skipContentCategories.remove(category) }
                        }
                    )) {
                        Text(category.displayName)
                    }
                    .accessibilityIdentifier("skip-content-\(category.rawValue)")
                }
            }
            Toggle("Set each marker separately", isOn: Binding(
                get: { !model.settings.skipModeOverrides.isEmpty },
                set: { model.settings.setSkipMarkersSeparately($0) }
            ))
            .accessibilityIdentifier("skip-markers-separately")
            if !model.settings.skipModeOverrides.isEmpty {
                ForEach(MediaSegment.Kind.skippable, id: \.self) { kind in
                    SkipMarkerRuleControls(model: model, kind: kind)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use community markers", isOn: $model.settings.useCommunityMarkers)
                    .accessibilityIdentifier("skip-community-markers")
                Text("From IntroDB and TheIntroDB when your server has none. Shares IMDb/TMDB IDs.")
                    .settingsHelperText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private enum SkipBehavior: CaseIterable, Hashable {
    case off, manual, automatic

    var title: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .manual: "Show skip button"
        case .automatic: "Skip automatically"
        }
    }
}

private struct SkipMarkerRuleControls: View {
    @Bindable var model: PlaybackSettingsModel
    let kind: MediaSegment.Kind?
    @Environment(\.locale) private var locale

    private var title: LocalizedStringResource { kind?.settingsTitle ?? "Behavior" }
    private var identifier: String { kind?.rawValue ?? "all" }
    private var behavior: Binding<SkipBehavior> {
        Binding(
            get: {
                let mode = model.settings.configuredSkipMode(for: kind)
                return mode == .off ? .off : mode.isAutomatic ? .automatic : .manual
            },
            set: { value in
                let mode: SkipIntrosMode = switch value {
                case .off: .off
                case .manual: .on
                case .automatic: model.settings.configuredSkipDelay(for: kind) == 0 ? .autoInstant : .autoDelay
                }
                model.settings.setConfiguredSkipMode(mode, for: kind)
            }
        )
    }
    private var delay: Binding<Int> {
        Binding(
            get: { model.settings.configuredSkipDelay(for: kind) },
            set: { model.settings.setSkipAutomaticDelay($0, for: kind) }
        )
    }

    var body: some View {
        SettingsControlRows(nonTVSpacing: 12) {
            #if os(tvOS)
            SettingsMenuRow(title: title, value: Text(behavior.wrappedValue.title)) {
                SkipBehaviorPicker(title: title, allowsOff: kind != nil, selection: behavior)
            }
            .accessibilityIdentifier("skip-behavior-\(identifier)")
            #else
            SkipBehaviorPicker(title: title, allowsOff: kind != nil, selection: behavior)
                .accessibilityIdentifier("skip-behavior-\(identifier)")
            #endif
            if behavior.wrappedValue == .automatic {
                #if os(tvOS)
                SettingsStepper(
                    options: PlaybackSettings.skipAutomaticDelayOptions,
                    selection: delay, label: "Skip after",
                    textTitle: { seconds in
                        seconds == 0
                            ? Text("Immediately")
                            : Text(Duration.seconds(seconds), format: .units(allowed: [.seconds], width: .wide).locale(locale))
                    }
                )
                .accessibilityIdentifier("skip-delay-\(identifier)")
                #else
                Stepper(value: delay, in: 0...30) {
                    LabeledContent {
                        if delay.wrappedValue == 0 {
                            Text("Immediately")
                        } else {
                            Text(Duration.seconds(delay.wrappedValue), format: .units(allowed: [.seconds], width: .wide))
                        }
                    } label: {
                        Text("Skip after")
                    }
                }
                .accessibilityIdentifier("skip-delay-\(identifier)")
                #endif
            }
        }
    }
}

private struct SkipBehaviorPicker: View {
    let title: LocalizedStringResource
    let allowsOff: Bool
    @Binding var selection: SkipBehavior

    var body: some View {
        Picker(selection: $selection) {
            ForEach(SkipBehavior.allCases.filter { allowsOff || $0 != .off }, id: \.self) { behavior in
                Text(behavior.title).tag(behavior)
            }
        } label: {
            Text(title)
        }
    }
}
#endif
