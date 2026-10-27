#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct SkipMarkerSettingsControl: View {
    @Bindable private var model: PlaybackSettingsModel
    #if os(tvOS)
    public init(model: PlaybackSettingsModel) {
        self.model = model
    }
    #else
    private let onOpenSettings: () -> Void

    public init(model: PlaybackSettingsModel, onOpenSettings: @escaping () -> Void) {
        self.model = model
        self.onOpenSettings = onOpenSettings
    }
    #endif

    public var body: some View {
        #if os(tvOS)
        SettingsControlRows {
            SkipMarkerEnableControl(model: model)
            if model.settings.skipMarkersEnabled {
                SettingsPageLink {
                    SkipMarkerSettingsView(model: model)
                } label: {
                    SettingsDisclosureLabel { Text("Customize") }
                        .settingsFormRowLayout()
                }
                .buttonStyle(SettingsFormButtonStyle())
                .accessibilityIdentifier("skip-marker-settings")
            }
        }
        #else
        SettingsSectionGroup {
            SkipMarkerEnableControl(model: model)
            if model.settings.skipMarkersEnabled {
                Button(action: onOpenSettings) {
                    SettingsDisclosureLabel { Text("Customize") }
                }
                .accessibilityIdentifier("skip-marker-settings")
            }
        }
        #endif
    }
}

private struct SkipMarkerEnableControl: View {
    @Bindable var model: PlaybackSettingsModel

    var body: some View {
        Toggle("Skip intros, credits & more", isOn: Binding(
            get: { model.settings.skipMarkersEnabled },
            set: { model.settings.setSkipMarkersEnabled($0) }
        ))
        .accessibilityIdentifier("skip-markers-enabled")
    }
}

public struct SkipMarkerSettingsView: View {
    @Bindable private var model: PlaybackSettingsModel
    @State private var selectedKind: MediaSegment.Kind?

    public init(model: PlaybackSettingsModel) {
        self.model = model
    }

    public var body: some View {
        #if os(tvOS)
        SettingsFormLayout(title: Text("Intros, credits & more"), rows: rows, showsBack: true)
        #else
        List {
            SettingsSectionGroup("Enable for") {
                SkipMarkerContentControls(model: model)
            }
            SettingsSectionGroup {
                ForEach(MediaSegment.Kind.skippable, id: \.self) { kind in
                    Button { selectedKind = kind } label: {
                        SettingsDisclosureLabel { Text(kind.settingsTitle) }
                    }
                    .accessibilityIdentifier("skip-marker-\(kind.rawValue)")
                }
            }
            SettingsSectionGroup {
                SkipMarkerCommunityControl(model: model)
            }
        }
        .settingsPageSurface()
        .navigationTitle("Intros, credits & more")
        .navigationDestination(item: $selectedKind) { kind in
            SkipMarkerContentSettingsView(model: model, kind: kind)
        }
        #endif
    }

    #if os(tvOS)
    private var rows: [SettingsSplitRow] {
        [
            SettingsSplitRow(id: "skip-content", title: "Enable for") {
                SettingsControlRows {
                    SkipMarkerContentControls(model: model)
                }
            },
            SettingsSplitRow(id: "skip-kinds", title: "Markers") {
                SettingsControlRows {
                    ForEach(MediaSegment.Kind.skippable, id: \.self) { kind in
                        SettingsPageLink {
                            SkipMarkerContentSettingsView(model: model, kind: kind)
                        } label: {
                            SettingsDisclosureLabel { Text(kind.settingsTitle) }
                                .settingsFormRowLayout()
                        }
                        .buttonStyle(SettingsFormButtonStyle())
                        .accessibilityIdentifier("skip-marker-\(kind.rawValue)")
                    }
                }
            }.labeledControl(),
            SettingsSplitRow(id: "skip-community", title: "Use community markers") {
                SkipMarkerCommunityControl(model: model)
            }.labeledControl()
        ]
    }
    #endif
}

public struct SkipMarkerContentSettingsView: View {
    @Bindable private var model: PlaybackSettingsModel
    private let kind: MediaSegment.Kind
    private let categories: [ContentCategory] = [.movie, .tvShow, .anime]

    public init(model: PlaybackSettingsModel, kind: MediaSegment.Kind) {
        self.model = model
        self.kind = kind
    }

    public var body: some View {
        #if os(tvOS)
        SettingsFormLayout(
            title: Text(kind.settingsTitle),
            rows: categories.map { category in
                SettingsSplitRow(id: "skip-\(category.rawValue)", title: category.displayName) {
                    controls(for: category)
                }.labeledControl()
            },
            showsBack: true
        )
        #else
        List {
            ForEach(categories, id: \.self) { category in
                SettingsSectionGroup {
                    controls(for: category)
                }
            }
        }
        .settingsPageSurface()
        .navigationTitle(Text(kind.settingsTitle))
        #endif
    }

    private func controls(for category: ContentCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SkipMarkerRuleControls(model: model, kind: kind, category: category)
                .disabled(!model.settings.skipContentCategories.contains(category))
            if !model.settings.skipContentCategories.contains(category) {
                Text("Disabled on the previous page.")
                    .settingsHelperText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SkipMarkerContentControls: View {
    @Bindable var model: PlaybackSettingsModel

    var body: some View {
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
}

private struct SkipMarkerCommunityControl: View {
    @Bindable var model: PlaybackSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use community markers", isOn: $model.settings.useCommunityMarkers)
                .accessibilityIdentifier("skip-community-markers")
            Text("From IntroDB and TheIntroDB when your server has none. Shares IMDb/TMDB IDs.")
                .settingsHelperText()
                .fixedSize(horizontal: false, vertical: true)
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
    let kind: MediaSegment.Kind
    let category: ContentCategory
    @Environment(\.locale) private var locale

    private var title: LocalizedStringResource { category.displayName }
    private var identifier: String { "\(kind.rawValue)-\(category.rawValue)" }
    private var behavior: Binding<SkipBehavior> {
        Binding(
            get: {
                let mode = model.settings.configuredSkipMode(for: kind, category: category)
                return mode == .off ? .off : mode.isAutomatic ? .automatic : .manual
            },
            set: { value in
                let mode: SkipIntrosMode = switch value {
                case .off: .off
                case .manual: .on
                case .automatic: model.settings.configuredSkipDelay(for: kind, category: category) == 0 ? .autoInstant : .autoDelay
                }
                model.settings.setConfiguredSkipMode(mode, for: kind, category: category)
            }
        )
    }
    private var delay: Binding<Int> {
        Binding(
            get: { model.settings.configuredSkipDelay(for: kind, category: category) },
            set: { model.settings.setSkipAutomaticDelay($0, for: kind, category: category) }
        )
    }

    var body: some View {
        SettingsControlRows(nonTVSpacing: 12) {
            #if os(tvOS)
            SettingsMenuRow(title: title, value: Text(behavior.wrappedValue.title)) {
                SkipBehaviorPicker(title: title, selection: behavior)
            }
            .accessibilityIdentifier("skip-behavior-\(identifier)")
            #else
            SkipBehaviorPicker(title: title, selection: behavior)
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
    @Binding var selection: SkipBehavior

    var body: some View {
        Picker(selection: $selection) {
            ForEach(SkipBehavior.allCases, id: \.self) { behavior in
                Text(behavior.title).tag(behavior)
            }
        } label: {
            Text(title)
        }
    }
}
#endif
