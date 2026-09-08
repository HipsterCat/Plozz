#if DEBUG && canImport(SwiftUI)
import CoreModels
import CoreUI
import Observation
import SwiftUI

/// Profile-scoped channel browsing preferences for Live TV.
public struct LiveTVSettingsView: View {
    private let store: any LiveTVViewSettingsStoring
    private let sourceManagement: (() -> AnyView)?
    @State private var settings: LiveTVViewSettings
    @State private var hiddenChannelsModel: LiveTVHiddenChannelsSettingsModel

    public init(
        store: any LiveTVViewSettingsStoring = LiveTVViewSettingsStore(),
        preferencesStore: any LiveTVPreferencesStoring = LiveTVPreferencesStore(),
        sourceManagement: (() -> AnyView)? = nil
    ) {
        self.store = store
        self.sourceManagement = sourceManagement
        self._settings = State(initialValue: store.load())
        self._hiddenChannelsModel = State(
            initialValue: LiveTVHiddenChannelsSettingsModel(store: preferencesStore)
        )
    }

    public var body: some View {
        #if os(tvOS)
        SettingsSplitLayout(title: "Live TV", rows: rows)
            .onAppear {
                hiddenChannelsModel.reload()
            }
            .onChange(of: settings) { _, settings in
                store.save(settings)
            }
        #elseif os(iOS)
        List {
            if sourceManagement != nil {
                Section {
                    NavigationLink {
                        sourceDestination
                    } label: {
                        Label("Manage sources", systemImage: "antenna.radiowaves.left.and.right")
                    }
                } header: {
                    Text("Sources")
                }
            }
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

            Section {
                NavigationLink {
                    LiveTVHiddenChannelsView(model: hiddenChannelsModel)
                } label: {
                    HiddenChannelsNavigationLabel(count: hiddenChannelsModel.hiddenChannels.count)
                }
            } header: {
                Text("Channels")
            }
        }
        .settingsPageSurface()
        .navigationTitle("Live TV")
        .onAppear {
            hiddenChannelsModel.reload()
        }
        .onChange(of: settings) { _, settings in
            store.save(settings)
        }
        #endif
    }

    @ViewBuilder
    private var sourceDestination: some View {
        if let sourceManagement {
            sourceManagement()
        }
    }

    #if os(tvOS)
    private var rows: [SettingsSplitRow] {
        let browsingRows = [
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
                description: "Preview the focused channel as you browse."
            ) {
                Toggle("Auto preview", isOn: $settings.autoPreview)
                    .toggleStyle(SettingsSwitchToggleStyle())
            },
            SettingsSplitRow(
                id: "keep-watching-while-browsing",
                title: "Keep watching while browsing",
                description: "After watching full screen, keep that channel playing while you browse. Turn off to preview the focused channel."
            ) {
                Toggle("Keep watching while browsing", isOn: $settings.keepWatchingWhileBrowsing)
                    .toggleStyle(SettingsSwitchToggleStyle())
                    .disabled(!settings.autoPreview)
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
            SettingsSplitRow(
                id: "hidden-channels",
                title: "Hidden channels",
                description: "Restore channels hidden from Live TV and Search."
            ) {
                NavigationLink {
                    LiveTVHiddenChannelsView(model: hiddenChannelsModel)
                } label: {
                    HiddenChannelsNavigationLabel(count: hiddenChannelsModel.hiddenChannels.count)
                }
                .buttonStyle(SettingsFocusButtonStyle())
            },
        ]
        guard sourceManagement != nil else { return browsingRows }
        return [
            SettingsSplitRow(
                id: "sources",
                title: "Sources",
                description: "Add, edit or pause IPTV playlists and connected Live TV servers."
            ) {
                NavigationLink {
                    sourceDestination
                } label: {
                    Label("Manage sources", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(SettingsFocusButtonStyle())
            }
        ] + browsingRows
    }
    #endif
}

private struct HiddenChannelsNavigationLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 16) {
            Label("Hidden channels", systemImage: "eye.slash")
            Spacer()
            if count > 0 {
                Text(count, format: .number)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct LiveTVHiddenChannelsView: View {
    let model: LiveTVHiddenChannelsSettingsModel

    var body: some View {
        List {
            LiveTVHiddenChannelsListContent(model: model)
        }
        #if os(iOS)
        .settingsPageSurface()
        #else
        .listStyle(.plain)
        .background { SettingsPageBackground() }
        #endif
        .navigationTitle("Hidden channels")
        .onAppear {
            model.reload()
        }
    }
}

private struct LiveTVHiddenChannelsListContent: View {
    let model: LiveTVHiddenChannelsSettingsModel

    var body: some View {
        if model.isLoading && !model.hasLoadedPreferences {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading hidden channels")
                }
            }
        } else if !model.hasLoadedPreferences {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Hidden channels couldn't be loaded.", systemImage: "exclamationmark.triangle.fill")
                    Button("Retry") {
                        model.retry()
                    }
                }
            }
        } else {
            if let issue = model.issue {
                LiveTVHiddenChannelsFailureSection(issue: issue) {
                    model.retry()
                }
            }

            if model.hiddenChannels.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No hidden channels",
                        systemImage: "eye",
                        description: Text("Channels you hide from Live TV will appear here.")
                    )
                }
            } else {
                Section {
                    ForEach(model.hiddenChannels) { channel in
                        HStack(spacing: 16) {
                            Text(channel.name)
                                .lineLimit(2)
                            Spacer()
                            Button("Restore") {
                                model.restoreChannel(id: channel.id)
                            }
                            .accessibilityLabel("Restore \(channel.name)")
                            .disabled(model.hasPendingChanges)
                        }
                    }
                }

                if model.hiddenChannels.count > 1 {
                    Section {
                        Button("Restore all") {
                            model.restoreAllChannels()
                        }
                        .disabled(model.hasPendingChanges)
                    }
                }
            }
        }
    }
}

private struct LiveTVHiddenChannelsFailureSection: View {
    let issue: LiveTVHiddenChannelsSettingsModel.Issue
    let retry: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                Button("Retry", action: retry)
            }
        }
    }

    private var message: LocalizedStringResource {
        switch issue {
        case .loadFailed:
            "Hidden channels couldn't be refreshed."
        case .saveFailed:
            "That change couldn't be saved."
        }
    }
}

@MainActor
@Observable
final class LiveTVHiddenChannelsSettingsModel {
    enum Issue: Equatable {
        case loadFailed
        case saveFailed
    }

    private enum PendingMutation: Equatable {
        case restore(String)
        case restoreAll
    }

    @ObservationIgnored
    private let store: any LiveTVPreferencesStoring
    private var preferences: LiveTVPreferences?
    @ObservationIgnored
    private var pendingMutation: PendingMutation?

    private(set) var isLoading = false
    private(set) var issue: Issue?

    var hiddenChannels: [LiveTVHiddenChannel] {
        preferences?.hiddenChannels ?? []
    }

    var hasLoadedPreferences: Bool {
        preferences != nil
    }

    var hasPendingChanges: Bool {
        pendingMutation != nil
    }

    init(store: any LiveTVPreferencesStoring) {
        self.store = store
    }

    func reload() {
        if let pendingMutation {
            apply(pendingMutation)
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            preferences = try store.load()
            issue = nil
        } catch {
            issue = .loadFailed
        }
    }

    func restoreChannel(id: String) {
        apply(.restore(id))
    }

    func restoreAllChannels() {
        apply(.restoreAll)
    }

    func retry() {
        reload()
    }

    private func apply(_ mutation: PendingMutation) {
        pendingMutation = mutation
        let current: LiveTVPreferences
        do {
            current = try store.load()
        } catch {
            issue = .loadFailed
            return
        }

        let updated: LiveTVPreferences
        switch mutation {
        case let .restore(id):
            updated = current.restoringChannel(id: id)
        case .restoreAll:
            updated = current.restoringAllChannels()
        }

        guard updated != current else {
            preferences = current
            pendingMutation = nil
            issue = nil
            return
        }

        do {
            try store.save(updated)
            preferences = updated
            pendingMutation = nil
            issue = nil
        } catch {
            preferences = current
            issue = .saveFailed
        }
    }
}
#endif
