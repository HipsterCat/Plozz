#if DEBUG
import CoreModels
import CoreUI
import FeatureLiveTVCore
import SwiftUI

public struct LiveTVSourcesView: View {
    private enum Removal {
        case playlist(LiveTVPlaylistSource)
        case server(LiveTVServerSource)
    }

    @State private var model: LiveTVSourceManagementModel
    @State private var pendingRemoval: Removal?
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
        serverChoices: [LiveTVServerChoice] = [],
        serverProviderResolver: LiveTVServerProviderResolver? = nil,
        connectServer: (() -> Void)? = nil,
        didConfigurePlaylist: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: LiveTVSourceManagementModel(store: store, canMutate: { false }))
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
            sourceList
        }
    }

    private var sourceList: some View {
        List {
            if let issue = model.loadIssue {
                Section {
                    Label {
                        Text(issue.message)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    Button("Retry") { model.reload() }
                }
            } else if !model.hasLoaded {
                ProgressView("Loading sources")
            } else {
                if browseSource != nil {
                    Section {
                        NavigationLink {
                            sourceFilterList
                        } label: {
                            HStack {
                                Text("Browse channels from")
                                Spacer()
                                if let name = selectedSourceName {
                                    Text(name).foregroundStyle(.secondary)
                                } else {
                                    Text("All sources").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !model.configuration.playlists.isEmpty {
                    Section {
                        ForEach(model.configuration.playlists) { source in
                            NavigationLink {
                                LiveTVPlaylistSourceDetails(
                                    model: model, imports: imports, sourceID: source.id,
                                    didConfigurePlaylist: didConfigurePlaylist
                                )
                            } label: {
                                LiveTVPlaylistSourceSummary(
                                    source: source,
                                    status: imports?.playlistSources.first { $0.id == source.id }
                                )
                            }
                            .contextMenu {
                                Button(source.isEnabled ? "Disable source" : "Enable source", systemImage: source.isEnabled ? "pause.circle" : "play.circle") {
                                    model.setPlaylistEnabled(source.id, enabled: !source.isEnabled)
                                }
                                Button("Remove source", systemImage: "trash", role: .destructive) {
                                    pendingRemoval = .playlist(source)
                                }
                            }
                        }
                    } header: {
                        Text("Your playlists")
                    } footer: {
                        Text("Enabled sources are combined in one guide. Disabling a source keeps its setup and channel preferences.")
                    }
                }

                if !model.configuration.servers.isEmpty {
                    Section("Connected servers") {
                        ForEach(model.configuration.servers) { source in
                            NavigationLink {
                                LiveTVServerSourceDetails(model: model, imports: imports, sourceID: source.id)
                            } label: {
                                LiveTVServerSourceSummary(
                                    source: source,
                                    status: imports?.serverSources.first { $0.id == source.id }
                                )
                            }
                            .contextMenu {
                                Button(source.isEnabled ? "Disable source" : "Enable source") {
                                    model.setServerEnabled(source.id, enabled: !source.isEnabled)
                                }
                                Button("Remove source", systemImage: "trash", role: .destructive) {
                                    pendingRemoval = .server(source)
                                }
                            }
                        }
                    }
                }
                Section {
                    NavigationLink {
                        playlistEditor
                    } label: {
                        Label("Add IPTV playlist", systemImage: "plus")
                    }
                    NavigationLink {
                        LiveTVServerSetupView(
                            sources: model, choices: serverChoices,
                            resolver: serverProviderResolver, connectServer: connectServer
                        )
                    } label: {
                        Label("Use a media server", systemImage: "server.rack")
                    }
                } header: {
                    Text("Add a source")
                } footer: {
                    Text("Add sources you have permission to access. Plozz doesn't provide channels.")
                }

                if let imports {
                    LiveTVGuideOverview(imports: imports)
                }
                if let refresh {
                    Section {
                        Button("Refresh sources", systemImage: "arrow.clockwise", action: refresh)
                            .disabled(imports?.isLoading == true)
                        if imports?.isLoading == true {
                            ProgressView("Refreshing sources")
                        }
                    }
                }
                Section {
                    LiveTVNoGuideExplanation()
                }
            }
        }
        #if os(iOS)
        .settingsPageSurface()
        #else
        .listStyle(.plain)
        .background { SettingsPageBackground() }
        #endif
        .navigationTitle("Live TV sources")
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
            Text("Its channels leave the guide. Other sources, Favorites and hidden-channel preferences are not erased.")
        }
    }

    private var selectedSourceName: String? {
        model.configuration.playlists.first { $0.id == sourceFilterID }?.name
            ?? model.configuration.servers.first { $0.id == sourceFilterID }?.name
    }

    private var playlistEditor: some View {
        LiveTVPlaylistEditor { input in
            try model.savePlaylist(input: input)
            didConfigurePlaylist()
        }
    }

    @ViewBuilder
    private var sourceFilterList: some View {
        if let browseSource {
            List {
                Button("All sources") { browseSource(nil) }
                    .accessibilityAddTraits(sourceFilterID == nil ? .isSelected : [])
                ForEach(model.configuration.playlists.filter(\.isEnabled)) { source in
                    Button(source.name) { browseSource(source.id) }
                        .accessibilityAddTraits(sourceFilterID == source.id ? .isSelected : [])
                }
                ForEach(model.configuration.servers.filter(\.isEnabled)) { source in
                    Button(source.name) { browseSource(source.id) }
                        .accessibilityAddTraits(sourceFilterID == source.id ? .isSelected : [])
                }
            }
            .navigationTitle("Browse sources")
        }
    }
}

private struct LiveTVGuideOverview: View {
    let imports: LiveTVPrototypeImportModel

    var body: some View {
        Section {
            Text("\(imports.matchedChannelCount) channels matched")
            Text("\(imports.programCount) program listings")
            if let start = imports.coverageStart, let end = imports.coverageEnd {
                Text(start..<end, format: .interval.day().month().hour().minute())
            }
        } header: {
            Text("Guide coverage")
        } footer: {
            Text("Coverage reflects loaded listings. Server guides load near the channels and times you browse; missing listings never prevent channel browsing.")
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
            List {
                Section {
                    Toggle("Enabled", isOn: Binding(
                        get: { source.isEnabled },
                        set: { model.setPlaylistEnabled(source.id, enabled: $0) }
                    ))
                } footer: {
                    Text("Disabling keeps the source and its channel preferences.")
                }
                if let imports {
                    if let status = imports.playlistSources.first(where: { $0.id == sourceID }) {
                        Section("Channels") {
                            LiveTVPlaylistImportStatus(status: status)
                        }
                    }
                    ForEach(imports.guideSources.filter { $0.playlistSourceID == sourceID }) { status in
                        Section {
                            PrototypeSourceAddress(url: status.source.url).font(.caption)
                            PrototypeGuideSourceStatus(
                                status: status, enabled: imports.enabledSourceIDs.contains(status.id)
                            )
                        } header: {
                            Text(status.source.name)
                        }
                    }
                } else {
                    Section {
                        Text("Open Live TV to load this source and see channel counts, guide matches and any connection issues.")
                    }
                }
                Section {
                    NavigationLink("Edit playlist and guides") {
                        LiveTVPlaylistSourceEditor(
                            model: model, source: source, didConfigurePlaylist: didConfigurePlaylist
                        )
                    }
                }
                Section {
                    Button("Remove source", role: .destructive) { confirmsRemoval = true }
                }
            }
            #if os(iOS)
            .settingsPageSurface()
            #else
            .listStyle(.plain)
            .background { SettingsPageBackground() }
            #endif
            .navigationTitle(source.name)
            .confirmationDialog("Remove this source?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Remove source", role: .destructive) {
                    let revision = model.mutationRevision
                    model.removePlaylist(source.id)
                    if revision != model.mutationRevision { dismiss() }
                }
            } message: {
                Text("Other sources and channel preferences are not erased.")
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
            Text("\(status.channelCount) channels")
            Text("\(status.entryCount) playlist entries")
            Text("\(status.skippedEntryCount) unsupported or duplicate entries skipped")
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
            List {
                Section {
                    Toggle("Enabled", isOn: Binding(
                        get: { source.isEnabled },
                        set: { model.setServerEnabled(source.id, enabled: $0) }
                    ))
                    NavigationLink("Rename source") {
                        LiveTVServerSourceRename(model: model, source: source)
                    }
                } footer: {
                    Text("This source uses the connected account's Live TV permissions. It does not use another user's credentials.")
                }
                if let status = imports?.serverSources.first(where: { $0.id == sourceID }) {
                    Section("Live TV status") {
                        LiveTVServerSourceSummary(source: source, status: status)
                        Text("\(status.channelCount) channels")
                        Text("\(status.programCount) loaded program listings")
                        if let date = status.lastGuideRefresh {
                            Text("Guide refreshed: \(date, format: .dateTime.month().day().hour().minute())")
                                .font(.caption)
                        }
                    }
                } else {
                    Section {
                        Text("Open Live TV to check this server's channels and guide availability.")
                    }
                }
                Section {
                    Button("Remove source", role: .destructive) { confirmsRemoval = true }
                }
            }
            #if os(iOS)
            .settingsPageSurface()
            #else
            .listStyle(.plain)
            .background { SettingsPageBackground() }
            #endif
            .navigationTitle(source.name)
            .confirmationDialog("Remove this source?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Remove source", role: .destructive) {
                    let revision = model.mutationRevision
                    model.removeServer(source.id)
                    if revision != model.mutationRevision { dismiss() }
                }
            } message: {
                Text("This removes it from Live TV, not from your connected accounts.")
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
        Form {
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
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.utf8.count > 512)
        }
        #if os(iOS)
        .settingsPageSurface()
        #else
        .listStyle(.plain)
        .background { SettingsPageBackground() }
        #endif
        .navigationTitle("Rename source")
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
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(source.name).font(.headline).lineLimit(2)
                Spacer()
                if !source.isEnabled {
                    Text("Disabled").font(.caption).foregroundStyle(palette.secondaryText)
                }
            }
            if let host = source.playlistURL.host {
                Text(host).font(.caption).foregroundStyle(palette.secondaryText).privacySensitive()
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
                Text("No guide added").font(.caption).foregroundStyle(palette.secondaryText)
            } else {
                Text("\(source.guideURLs.count) guide sources").font(.caption).foregroundStyle(palette.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
