#if DEBUG && canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

/// Profile-scoped channel browsing preferences for Live TV.
public struct LiveTVSettingsView: View {
    private let store: any LiveTVViewSettingsStoring
    @State private var settings: LiveTVViewSettings

    public init(store: any LiveTVViewSettingsStoring = LiveTVViewSettingsStore()) {
        self.store = store
        self._settings = State(initialValue: store.load())
    }

    public var body: some View {
        #if os(tvOS)
        SettingsSplitLayout(title: "Live TV", rows: rows)
            .onChange(of: settings) { _, settings in
                store.save(settings)
            }
        #elseif os(iOS)
        List {
            Section {
                Picker("Sort", selection: $settings.sortByName) {
                    Text("Channel number").tag(false)
                    Text("Name").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Channel order")
            }

            Section {
                Toggle("Favorites only", isOn: $settings.favoritesOnly)
                Toggle("With guide listings", isOn: $settings.guideOnly)
            } header: {
                Text("Filters")
            }
        }
        .settingsPageSurface()
        .navigationTitle("Live TV")
        .onChange(of: settings) { _, settings in
            store.save(settings)
        }
        #endif
    }

    #if os(tvOS)
    private var rows: [SettingsSplitRow] {
        [
            SettingsSplitRow(
                id: "sort",
                title: "Sort",
                description: "Choose how channels are ordered."
            ) {
                SettingsSegmentedPicker(
                    options: [false, true],
                    selection: $settings.sortByName,
                    title: { $0 ? "Name" : "Channel number" }
                )
            },
            SettingsSplitRow(
                id: "auto-preview",
                title: "Auto preview",
                description: "Preview channels as you browse. Choosing Watch keeps that channel playing until you leave Live TV."
            ) {
                Toggle("Auto preview", isOn: $settings.autoPreview)
                    .toggleStyle(SettingsSwitchToggleStyle())
            },
            SettingsSplitRow(
                id: "favorites-only",
                title: "Favorites only",
                description: "Show only channels marked as favorites."
            ) {
                Toggle("Favorites only", isOn: $settings.favoritesOnly)
                    .toggleStyle(SettingsSwitchToggleStyle())
            },
            SettingsSplitRow(
                id: "with-guide-listings",
                title: "With guide listings",
                description: "Show only channels with available guide listings."
            ) {
                Toggle("With guide listings", isOn: $settings.guideOnly)
                    .toggleStyle(SettingsSwitchToggleStyle())
            },
        ]
    }
    #endif
}
#endif
