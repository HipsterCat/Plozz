#if DEBUG
import CoreModels
import CoreUI
import FeatureLiveTVCore
import SwiftUI

public struct LiveTVSourcesView: View {
    public enum Presentation { case page, settingsPane }

    @State private var model: LiveTVSourceManagementModel
    @State private var pendingRemoval: LiveTVSourceRemoval?
    private let presentation: Presentation
    private let imports: LiveTVPrototypeImportModel?
    private let refresh: (() -> Void)?
    private let serverChoices: [LiveTVServerChoice]
    private let serverProviderResolver: LiveTVServerProviderResolver?
    private let connectServer: (() -> Void)?
    private let sourceFilterID: String?
    private let browseSource: ((String?) -> Void)?
    private let didConfigurePlaylist: () -> Void

    public init(
        store: any LiveTVSourcesStoring,
        presentation: Presentation = .page,
        serverChoices: [LiveTVServerChoice] = [],
        serverProviderResolver: LiveTVServerProviderResolver? = nil,
        connectServer: (() -> Void)? = nil,
        didConfigurePlaylist: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: LiveTVSourceManagementModel(store: store, canMutate: { false }))
        self.presentation = presentation
        imports = nil
        refresh = nil
        self.serverChoices = serverChoices
        self.serverProviderResolver = serverProviderResolver
        self.connectServer = connectServer
        sourceFilterID = nil
        browseSource = nil
        self.didConfigurePlaylist = didConfigurePlaylist
    }

    init(
        model: LiveTVSourceManagementModel,
        imports: LiveTVPrototypeImportModel,
        refresh: @escaping () -> Void,
        serverChoices: [LiveTVServerChoice] = [],
        serverProviderResolver: LiveTVServerProviderResolver? = nil,
        connectServer: (() -> Void)? = nil,
        sourceFilterID: String? = nil,
        browseSource: ((String?) -> Void)? = nil,
        didConfigurePlaylist: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        presentation = .page
        self.imports = imports
        self.refresh = refresh
        self.serverChoices = serverChoices
        self.serverProviderResolver = serverProviderResolver
        self.connectServer = connectServer
        self.sourceFilterID = sourceFilterID
        self.browseSource = browseSource
        self.didConfigurePlaylist = didConfigurePlaylist
    }

    public var body: some View {
        LiveTVSourceAccessGate(model: model) {
            let content = LiveTVSourcesContent(
                model: model, imports: imports, refresh: refresh,
                serverChoices: serverChoices, serverProviderResolver: serverProviderResolver,
                connectServer: connectServer, sourceFilterID: sourceFilterID,
                browseSource: browseSource, didConfigurePlaylist: didConfigurePlaylist,
                removeSource: { pendingRemoval = $0 }
            )
            if presentation == .settingsPane {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
            } else {
                LiveTVSettingsPage(title: "Sources") {
                    content
                }
            }
        }
        .task { model.reload() }
        .alert("Source changes couldn't be saved", isPresented: Binding(
            get: { model.mutationIssue != nil },
            set: { if !$0 { model.mutationIssue = nil } }
        )) {
            Button("OK", role: .cancel) { model.mutationIssue = nil }
        } message: {
            if let issue = model.mutationIssue { Text(issue.message) }
        }
        .confirmationDialog("Remove this source?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            if let removal = pendingRemoval {
                Button("Remove source", role: .destructive) {
                    switch removal {
                    case .playlist(let source): model.removePlaylist(source.id)
                    case .server(let source): model.removeServer(source.id)
                    }
                    pendingRemoval = nil
                }
            }
        } message: {
            Text("Its channels leave the guide. Channel preferences are kept.")
        }
    }
}

private enum LiveTVSourceRemoval {
    case playlist(LiveTVPlaylistSource)
    case server(LiveTVServerSource)
}

private struct LiveTVSourcesContent: View {
    let model: LiveTVSourceManagementModel
    let imports: LiveTVPrototypeImportModel?
    let refresh: (() -> Void)?
    let serverChoices: [LiveTVServerChoice]
    let serverProviderResolver: LiveTVServerProviderResolver?
    let connectServer: (() -> Void)?
    let sourceFilterID: String?
    let browseSource: ((String?) -> Void)?
    let didConfigurePlaylist: () -> Void
    let removeSource: (LiveTVSourceRemoval) -> Void

    var body: some View {
        if let issue = model.loadIssue {
            SettingsSectionGroup {
                Label {
                    Text(issue.message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                Button("Retry") { model.reload() }
                    .buttonStyle(SettingsFocusButtonStyle(size: .contained))
            }
        } else if !model.hasLoaded {
            ProgressView("Loading sources")
        } else {
            if browseSource != nil {
                SettingsSectionGroup {
                    NavigationLink {
                        LiveTVSourceFilterList(
                            configuration: model.configuration,
                            sourceFilterID: sourceFilterID, browseSource: browseSource
                        )
                    } label: {
                        SettingsRowLabel(icon: "line.3.horizontal.decrease", title: "Browse channels from", trailing: {
                            if let name = selectedSourceName {
                                Text(name).settingsRowSecondary()
                            } else {
                                Text("All sources").settingsRowSecondary()
                            }
                        })
                    }
                    .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                }
            }
            ForEach(model.configuration.playlists) { source in
                SettingsSectionGroup(verbatim: source.name) {
                    Toggle("Enabled", isOn: Binding(
                        get: { source.isEnabled },
                        set: { model.setPlaylistEnabled(source.id, enabled: $0) }
                    ))
                    .accessibilityIdentifier("live-tv-source-enabled-\(source.id)")
                    NavigationLink {
                        LiveTVPlaylistSourceEditor(
                            model: model, source: source, didConfigurePlaylist: didConfigurePlaylist
                        )
                    } label: {
                        SettingsRowLabel(icon: "list.bullet.rectangle", title: "Playlist and guides")
                    }
                    .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                    .accessibilityIdentifier("live-tv-edit-source-\(source.id)")
                    if let imports {
                        NavigationLink {
                            LiveTVPlaylistSourceDetails(
                                model: model, imports: imports, sourceID: source.id,
                                didConfigurePlaylist: didConfigurePlaylist
                            )
                        } label: {
                            LiveTVPlaylistSourceSummary(
                                source: source,
                                status: imports.playlistSources.first { $0.id == source.id }
                            )
                        }
                        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                    }
                    Button(role: .destructive) {
                        removeSource(.playlist(source))
                    } label: {
                        SettingsRowLabel(icon: "trash", title: "Remove source")
                    }
                    .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                    .accessibilityIdentifier("live-tv-remove-source-\(source.id)")
                }
            }

            ForEach(model.configuration.servers) { source in
                SettingsSectionGroup(verbatim: source.name) {
                    Toggle("Enabled", isOn: Binding(
                        get: { source.isEnabled },
                        set: { model.setServerEnabled(source.id, enabled: $0) }
                    ))
                    NavigationLink {
                        LiveTVServerSourceRename(model: model, source: source)
                    } label: {
                        SettingsRowLabel(icon: "pencil", title: "Rename source")
                    }
                    .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                    if let imports {
                        NavigationLink {
                            LiveTVServerSourceDetails(model: model, imports: imports, sourceID: source.id)
                        } label: {
                            LiveTVServerSourceSummary(
                                source: source,
                                status: imports.serverSources.first { $0.id == source.id }
                            )
                        }
                        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                    }
                    Button(role: .destructive) {
                        removeSource(.server(source))
                    } label: {
                        SettingsRowLabel(icon: "trash", title: "Remove source")
                    }
                    .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                }
            }
            SettingsSectionGroup {
                NavigationLink {
                    LiveTVPlaylistEditor { input in
                        try model.savePlaylist(input: input)
                        didConfigurePlaylist()
                    }
                } label: {
                    SettingsRowLabel(icon: "plus", title: "Add IPTV playlist")
                }
                .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                NavigationLink {
                    LiveTVServerSetupView(
                        sources: model, choices: serverChoices,
                        resolver: serverProviderResolver, connectServer: connectServer
                    )
                } label: {
                    SettingsRowLabel(icon: "server.rack", title: "Use a media server")
                }
                .buttonStyle(SettingsFocusButtonStyle(size: .contained))
            }

            if let imports {
                LiveTVGuideOverview(imports: imports)
            }
            if let refresh {
                SettingsSectionGroup {
                    Button("Refresh sources", systemImage: "arrow.clockwise", action: refresh)
                        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                        .disabled(imports?.isLoading == true)
                    if imports?.isLoading == true {
                        ProgressView("Refreshing sources")
                    }
                }
            }
        }
    }

    private var selectedSourceName: String? {
        model.configuration.playlists.first { $0.id == sourceFilterID }?.name
            ?? model.configuration.servers.first { $0.id == sourceFilterID }?.name
    }
}

private struct LiveTVSourceFilterList: View {
    let configuration: LiveTVSourcesConfiguration
    let sourceFilterID: String?
    let browseSource: ((String?) -> Void)?

    var body: some View {
        if let browseSource {
            LiveTVSettingsPage(title: "Browse sources") {
                SettingsSectionGroup {
                    Button {
                        browseSource(nil)
                    } label: {
                        SettingsRowLabel(icon: nil, title: "All sources", trailing: {
                            if sourceFilterID == nil { SettingsSelectionIndicator() }
                        })
                    }
                    .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                    .accessibilityAddTraits(sourceFilterID == nil ? .isSelected : [])
                    ForEach(configuration.playlists.filter(\.isEnabled)) { source in
                        Button {
                            browseSource(source.id)
                        } label: {
                            SettingsRowLabel(icon: nil, title: Text(source.name), trailing: {
                                if sourceFilterID == source.id { SettingsSelectionIndicator() }
                            })
                        }
                        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                        .accessibilityAddTraits(sourceFilterID == source.id ? .isSelected : [])
                    }
                    ForEach(configuration.servers.filter(\.isEnabled)) { source in
                        Button {
                            browseSource(source.id)
                        } label: {
                            SettingsRowLabel(icon: nil, title: Text(source.name), trailing: {
                                if sourceFilterID == source.id { SettingsSelectionIndicator() }
                            })
                        }
                        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                        .accessibilityAddTraits(sourceFilterID == source.id ? .isSelected : [])
                    }
                }
            }
        }
    }
}

private struct LiveTVGuideOverview: View {
    let imports: LiveTVPrototypeImportModel

    var body: some View {
        SettingsSectionGroup("Guide coverage") {
            Text("\(imports.matchedChannelCount) channels matched")
            Text("\(imports.programCount) program listings")
            if let start = imports.coverageStart, let end = imports.coverageEnd {
                Text(start..<end, format: .interval.day().month().hour().minute())
            }
        }
    }
}

private struct LiveTVPlaylistSourceDetails: View {
    let model: LiveTVSourceManagementModel
    let imports: LiveTVPrototypeImportModel?
    let sourceID: String
    let didConfigurePlaylist: () -> Void
    @State private var confirmsRemoval = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let source = model.configuration.playlists.first(where: { $0.id == sourceID }) {
            LiveTVSettingsPage(title: "Source details") {
                SettingsSectionGroup(verbatim: source.name) {
                    Toggle("Enabled", isOn: Binding(
                        get: { source.isEnabled },
                        set: { model.setPlaylistEnabled(source.id, enabled: $0) }
                    ))
                }
                if let imports {
                    if let status = imports.playlistSources.first(where: { $0.id == sourceID }) {
                        SettingsSectionGroup("Channels") {
                            LiveTVPlaylistImportStatus(status: status)
                        }
                    }
                    ForEach(imports.guideSources.filter { $0.playlistSourceID == sourceID }) { status in
                        SettingsSectionGroup(verbatim: status.source.name) {
                            PrototypeSourceAddress(url: status.source.url).font(.caption)
                            PrototypeGuideSourceStatus(
                                status: status, enabled: imports.enabledSourceIDs.contains(status.id)
                            )
                        }
                    }
                }
                SettingsSectionGroup {
                    NavigationLink("Edit playlist and guides") {
                        LiveTVPlaylistSourceEditor(
                            model: model, source: source, didConfigurePlaylist: didConfigurePlaylist
                        )
                    }
                    .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                }
                SettingsSectionGroup {
                    Button("Remove source", role: .destructive) { confirmsRemoval = true }
                        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                }
            }
            .confirmationDialog("Remove this source?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Remove source", role: .destructive) {
                    let revision = model.mutationRevision
                    model.removePlaylist(source.id)
                    if revision != model.mutationRevision { dismiss() }
                }
            } message: {
                Text("Channel preferences are kept.")
            }
        } else {
            ContentUnavailableView("Source removed", systemImage: "list.bullet.rectangle")
        }
    }
}

private struct LiveTVPlaylistImportStatus: View {
    let status: LiveTVPlaylistSourceStatus

    var body: some View {
        if status.phase == .loading {
            ProgressView("Loading channels")
        } else if status.phase == .idle {
            Text("Ready to load")
        }
        if let failure = status.failure {
            Text(failure.userDescription)
            if status.lastRefresh != nil { Text("Keeping previously loaded channels") }
        }
        if status.lastRefresh != nil {
            if status.skippedEntryCount > 0 {
                Text("\(status.skippedEntryCount) unsupported or duplicate entries skipped")
            }
        }
        if let date = status.lastRefresh {
            Text("Last refreshed: \(date, format: .dateTime.month().day().hour().minute())")
                .font(.caption)
        }
    }
}

private struct LiveTVServerSourceDetails: View {
    let model: LiveTVSourceManagementModel
    let imports: LiveTVPrototypeImportModel?
    let sourceID: String
    @State private var confirmsRemoval = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let source = model.configuration.servers.first(where: { $0.id == sourceID }) {
            LiveTVSettingsPage(title: "Source details") {
                SettingsSectionGroup(verbatim: source.name) {
                    Toggle("Enabled", isOn: Binding(
                        get: { source.isEnabled },
                        set: { model.setServerEnabled(source.id, enabled: $0) }
                    ))
                    NavigationLink("Rename source") {
                        LiveTVServerSourceRename(model: model, source: source)
                    }
                    .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                }
                if let status = imports?.serverSources.first(where: { $0.id == sourceID }) {
                    SettingsSectionGroup("Live TV status") {
                        LiveTVServerSourceSummary(source: source, status: status)
                        Text("\(status.channelCount) channels")
                        Text("\(status.programCount) loaded program listings")
                        if let date = status.lastGuideRefresh {
                            Text("Guide refreshed: \(date, format: .dateTime.month().day().hour().minute())")
                                .font(.caption)
                        }
                    }
                }
                SettingsSectionGroup {
                    Button("Remove source", role: .destructive) { confirmsRemoval = true }
                        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                }
            }
            .confirmationDialog("Remove this source?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Remove source", role: .destructive) {
                    let revision = model.mutationRevision
                    model.removeServer(source.id)
                    if revision != model.mutationRevision { dismiss() }
                }
            } message: {
                Text("The server account stays connected.")
            }
        } else {
            ContentUnavailableView("Source removed", systemImage: "server.rack")
        }
    }
}

private struct LiveTVServerSourceRename: View {
    let model: LiveTVSourceManagementModel
    @State private var original: LiveTVServerSource
    @State private var name: String
    @State private var failure: LiveTVSourceManagementModel.Issue?
    @Environment(\.dismiss) private var dismiss

    init(model: LiveTVSourceManagementModel, source: LiveTVServerSource) {
        self.model = model
        _original = State(initialValue: source)
        _name = State(initialValue: source.name)
    }

    var body: some View {
        LiveTVSettingsPage(title: "Rename source") {
            SettingsSectionGroup {
                TextField("Source name", text: $name)
                if let failure { Text(failure.message) }
                Button("Save name") {
                    do {
                        try model.renameServer(original, name: name)
                        dismiss()
                    } catch LiveTVSourceManagementModel.MutationError.changedSource {
                        failure = .changedSource
                    } catch LiveTVSourceManagementModel.MutationError.accessDenied {
                        failure = .accessDenied
                    } catch {
                        failure = .save
                    }
                }
                .buttonStyle(SettingsFocusButtonStyle(size: .contained))
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.utf8.count > 512)
            }
        }
    }
}

private struct LiveTVPlaylistSourceEditor: View {
    let model: LiveTVSourceManagementModel
    @State private var source: LiveTVPlaylistSource
    let didConfigurePlaylist: () -> Void

    init(
        model: LiveTVSourceManagementModel,
        source: LiveTVPlaylistSource,
        didConfigurePlaylist: @escaping () -> Void
    ) {
        self.model = model
        _source = State(initialValue: source)
        self.didConfigurePlaylist = didConfigurePlaylist
    }

    var body: some View {
        LiveTVPlaylistEditor(
            name: source.name, playlistURL: source.playlistURL, guideURLs: source.guideURLs,
            isEditing: true
        ) { input in
            try model.savePlaylist(input: input, replacing: source)
            didConfigurePlaylist()
        }
    }
}

private struct LiveTVServerSourceSummary: View {
    let source: LiveTVServerSource
    let status: LiveTVServerSourceStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source.name).font(.headline)
            if !source.isEnabled {
                Text("Disabled").font(.caption)
            } else if let status {
                if let failure = status.failure {
                    Text(failure.userDescription).font(.caption)
                } else if let availability = status.availability {
                    LiveTVServerAvailabilitySummary(availability: availability)
                } else if status.phase == .loading {
                    ProgressView("Loading channels")
                } else {
                    Text("Ready to load").font(.caption)
                }
                if let failure = status.guideFailure {
                    Text(failure.userDescription).font(.caption)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LiveTVPlaylistSourceSummary: View {
    let source: LiveTVPlaylistSource
    let status: LiveTVPlaylistSourceStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(source.name).font(.headline).lineLimit(2)
                Spacer()
                if !source.isEnabled {
                    Text("Disabled").font(.caption).settingsRowSecondary()
                }
            }
            if let host = source.playlistURL.host {
                Text(host).font(.caption).settingsRowSecondary().privacySensitive()
            }
            if source.isEnabled, let status {
                switch status.phase {
                case .idle:
                    Text("Ready to load").font(.caption)
                case .loading:
                    ProgressView("Loading channels")
                case .loaded:
                    Text("\(status.channelCount) channels").font(.caption)
                case .failed:
                    Label("Refresh failed", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                }
            }
            if source.guideURLs.isEmpty {
                Text("No guide added").font(.caption).settingsRowSecondary()
            } else {
                Text("\(source.guideURLs.count) guide sources").font(.caption).settingsRowSecondary()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
