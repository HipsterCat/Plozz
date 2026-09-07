#if DEBUG
import CoreUI
import FeatureLiveTVCore
import SwiftUI

struct PrototypeBrowseToolbar: View {
    @Bindable var model: LiveTVPrototypeModel
    @Binding var active: Bool
    let focusRequest: Int
    let compact: Bool
    let search: () -> Void
    let filters: () -> Void
    let more: () -> Void
    @FocusState private var focused: Control?
    @Environment(\.themePalette) private var palette

    private enum Control: Hashable { case search, filters, more }

    var body: some View {
        HStack(spacing: PrototypeLayout.gap) {
            HStack(spacing: PrototypeLayout.smallGap) {
                Button(action: search) {
                    Label("Search", systemImage: "magnifyingglass")
                        .labelStyle(PrototypeToolbarLabelStyle(compact: compact))
                        .padding(.horizontal, compact ? 12 : 20)
                        .frame(minWidth: 44, minHeight: PrototypeLayout.controlHeight)
                }
                .focused($focused, equals: .search)
                .buttonStyle(PrototypeButtonStyle(selected: !model.query.isEmpty, padded: false, surface: .control))
                .accessibilityValue(model.query)
                .accessibilityIdentifier("live-tv-search")
                Button(action: filters) {
                    HStack(spacing: 8) {
                        if let category = model.category { Text(category) }
                        else { Text("Categories") }
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, compact ? 12 : 20)
                    .frame(minHeight: PrototypeLayout.controlHeight)
                    .frame(maxWidth: compact ? .infinity : 280)
                }
                .focused($focused, equals: .filters)
                .buttonStyle(PrototypeButtonStyle(
                    selected: model.category != nil || model.guideOnly || model.source != nil,
                    padded: false, surface: .control
                ))
                .accessibilityIdentifier("live-tv-category")
                Button(action: more) {
                    Label("More", systemImage: "ellipsis")
                        .labelStyle(PrototypeToolbarLabelStyle(compact: compact))
                        .padding(.horizontal, compact ? 12 : 20)
                        .frame(minWidth: 44, minHeight: PrototypeLayout.controlHeight)
                }
                .focused($focused, equals: .more)
                .accessibilityIdentifier("live-tv-options")
            }
            .padding(PrototypeLayout.controlInset)
            .background { PrototypeControlSurface() }
            if !compact {
                Spacer(minLength: 0)
                Text(model.now, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .buttonStyle(PrototypeButtonStyle(padded: false, surface: .control))
        .focusEffectDisabled()
        #if os(tvOS)
        .focusSection()
        #endif
        .onChange(of: focused) { _, target in
            if target != nil { active = true }
        }
        .onChange(of: focusRequest) { _, _ in focused = .search }
    }
}

private struct PrototypeToolbarLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
            if !compact { configuration.title }
        }
    }
}

struct PrototypeSheetContent: View {
    @Bindable var model: LiveTVPrototypeModel
    let imports: LiveTVPrototypeImportModel
    let destination: PrototypeSheet
    let reload: () -> Void
    let followsFocus: Bool
    let togglePreview: () -> Void
    let top: () -> Void
    let showGuide: () -> Void
    @Binding var guideOffset: TimeInterval
    let goToNow: () -> Void
    let guideStart: Date
    let tune: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            Group {
                switch destination {
                case .search:
                    PrototypeSearchForm(model: model) { id in
                        tune(id)
                        dismiss()
                    }
                        .navigationTitle("Search channels")
                case .filters:
                    PrototypeFilterForm(model: model)
                        .navigationTitle("Filter channels")
                case .options:
                    PrototypeOptionsForm(
                        model: model, imports: imports, reload: reload,
                        followsFocus: followsFocus, togglePreview: togglePreview,
                        top: top, showGuide: showGuide,
                        guideOffset: $guideOffset, goToNow: goToNow, guideStart: guideStart, tune: tune
                    )
                    .navigationTitle("Live TV")
                case .sources:
                    PrototypeSourcesForm(model: model, imports: imports, reload: reload) {
                        showGuide()
                        dismiss()
                    }
                    .navigationTitle("Live TV sources")
                case .program(let program):
                    PrototypeProgramDetails(
                        program: program, model: model,
                        guideSourceName: imports.guideSources.first {
                            $0.id == imports.selectedSourceByChannel[program.channelID]
                        }?.source.name
                    ) {
                        tune(program.channelID)
                        dismiss()
                    }
                    .navigationTitle("Program details")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .background(palette.backgroundBase)
        }
    }
}

private struct PrototypeOptionsForm: View {
    @Bindable var model: LiveTVPrototypeModel
    let imports: LiveTVPrototypeImportModel
    let reload: () -> Void
    let followsFocus: Bool
    let togglePreview: () -> Void
    let top: () -> Void
    let showGuide: () -> Void
    @Binding var guideOffset: TimeInterval
    let goToNow: () -> Void
    let guideStart: Date
    let tune: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    PrototypeSearchForm(model: model) { id in
                        tune(id)
                        dismiss()
                    }
                    .navigationTitle("Search channels")
                } label: {
                    Label("Search channels", systemImage: "magnifyingglass")
                }
                NavigationLink {
                    PrototypeFilterForm(model: model).navigationTitle("Filter channels")
                } label: {
                    Label("Filter channels", systemImage: "line.3.horizontal.decrease")
                }
                PrototypeSelectionLink(
                    title: "Sort", selection: $model.sort, options: LiveTVPrototypeSort.allCases
                ) { Text($0.title) }
                Toggle("Auto preview", isOn: Binding(
                    get: { followsFocus },
                    set: { if $0 != followsFocus { togglePreview() } }
                ))
                Button("Back to top", systemImage: "arrow.up.to.line") {
                    top()
                    dismiss()
                }
            } footer: {
                Text("Auto preview follows channel focus. Turn it off to keep your current channel playing while you browse.")
            }
            if model.guideChannelCount > 0 {
                Section("Guide time") {
                    Text(guideStart, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    Button("Earlier", systemImage: "chevron.backward") {
                        guideOffset = max(-86_400, guideOffset - 7_200)
                        dismiss()
                    }
                    .disabled(guideOffset <= -86_400)
                    Button("Now", systemImage: "clock") {
                        goToNow()
                        dismiss()
                    }
                    Button("Later", systemImage: "chevron.forward") {
                        guideOffset = min(604_800, guideOffset + 7_200)
                        dismiss()
                    }
                    .disabled(guideOffset >= 604_800)
                }
            }
            Section {
                NavigationLink {
                    PrototypeSourcesForm(model: model, imports: imports, reload: reload) {
                        showGuide()
                        dismiss()
                    }
                    .navigationTitle("Live TV sources")
                } label: {
                    Label("Sources", systemImage: "antenna.radiowaves.left.and.right")
                }
                .accessibilityIdentifier("live-tv-sources")
                Text("\(model.visibleChannels.count) of \(model.channels.count) channels")
                PrototypeImportStatus(imports: imports, listedChannels: model.guideChannelCount)
            }
        }
    }
}

private struct PrototypeSearchForm: View {
    @Bindable var model: LiveTVPrototypeModel
    let tune: (String) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Name, number, category or source", text: $model.query)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("live-tv-search-field")
                if !model.query.isEmpty {
                    Button("Clear search") { model.query = "" }
                }
            } footer: {
                Text("Channel search works even when there is no program guide.")
            }
            Section {
                Text("\(model.visibleChannels.count) matching channels")
                ForEach(model.visibleChannels.prefix(8)) { channel in
                    Button { tune(channel.id) } label: {
                        HStack {
                            PrototypeStationMark(channel: channel, size: 48)
                            Text(channel.name)
                            Spacer()
                            Text(channel.number, format: .number.grouping(.never)).monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

private struct PrototypeFilterForm: View {
    @Bindable var model: LiveTVPrototypeModel

    var body: some View {
        Form {
            Section {
                TextField("Search channels", text: $model.query).autocorrectionDisabled()
                PrototypeSelectionLink(
                    title: "Category", selection: $model.category,
                    options: [nil] + model.categories.map(Optional.some)
                ) { category in
                    if let category { Text(category) }
                    else { Text("All categories") }
                }
                PrototypeSelectionLink(
                    title: "Source", selection: $model.source,
                    options: [nil] + LiveTVPrototypeSource.allCases.filter { source in
                        model.channels.contains { $0.source == source }
                    }.map(Optional.some)
                ) { source in
                    if let source { Text(source.title) }
                    else { Text("All sources") }
                }
                Toggle("Favorites only", isOn: $model.favoritesOnly)
                Toggle("With guide listings", isOn: $model.guideOnly)
                PrototypeSelectionLink(
                    title: "Sort", selection: $model.sort, options: LiveTVPrototypeSort.allCases
                ) { Text($0.title) }
            }
            Section {
                Button("Clear filters") { model.resetFilters() }
                Text("\(model.visibleChannels.count) matching channels")
            }
        }
    }
}

struct PrototypeSelectionLink<Option: Hashable, OptionLabel: View>: View {
    let title: LocalizedStringKey
    @Binding var selection: Option
    let options: [Option]
    @ViewBuilder let optionLabel: (Option) -> OptionLabel

    var body: some View {
        NavigationLink {
            PrototypeSelectionList(selection: $selection, options: options, optionLabel: optionLabel)
                .navigationTitle(title)
        } label: {
            HStack {
                Text(title)
                Spacer()
                optionLabel(selection).foregroundStyle(.secondary)
            }
        }
    }
}

struct PrototypeSelectionList<Option: Hashable, OptionLabel: View>: View {
    @Binding var selection: Option
    let options: [Option]
    @ViewBuilder let optionLabel: (Option) -> OptionLabel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(options, id: \.self) { option in
            Button {
                selection = option
                dismiss()
            } label: {
                HStack {
                    optionLabel(option)
                    Spacer()
                    if option == selection {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .accessibilityAddTraits(option == selection ? .isSelected : [])
        }
    }
}

private struct PrototypeSourcesForm: View {
    @Bindable var model: LiveTVPrototypeModel
    let imports: LiveTVPrototypeImportModel
    let reload: () -> Void
    let showGuide: () -> Void
    @State private var selectionFailed = false

    var body: some View {
        Form {
            Section {
                Text("iptv-org · United States").font(.headline)
                Text(imports.playlistURL.absoluteString).font(.caption)
                Text("\(imports.entryCount) playlist entries")
                Text("\(imports.skippedEntryCount) unsupported or duplicate entries skipped")
            } header: {
                Text("Channels")
            } footer: {
                Text("Stream variants can share a station name. Availability varies by channel and region.")
            }
            Section {
                Text("\(imports.matchedChannelCount) channel matches")
                Text("\(model.guideChannelCount) channels with listings · \(imports.programCount) programs")
                if let start = imports.coverageStart, let end = imports.coverageEnd {
                    Text(start..<end, format: .interval.day().month().hour().minute())
                }
                if let date = imports.lastGuideRefresh {
                    Text("Last refreshed: \(date, format: .dateTime.month().day().hour().minute())")
                }
                Button("Show channels with guide listings", systemImage: "calendar", action: showGuide)
                    .disabled(model.guideChannelCount == 0)
            } header: {
                Text("Program guide")
            } footer: {
                Text("Each channel uses one guide. Exact channel IDs take priority; equally strong matches prefer available listings, then the source order below. Unknown channels remain watchable.")
            }
            ForEach(imports.guideSources) { status in
                Section {
                    Toggle(isOn: Binding(
                        get: { imports.enabledSourceIDs.contains(status.id) },
                        set: { enabled in
                            do {
                                try imports.setSourceEnabled(status.id, enabled: enabled, into: model)
                                reload()
                            } catch {
                                selectionFailed = true
                            }
                        }
                    )) {
                        Text(status.source.name).font(.headline)
                    }
                    .accessibilityIdentifier("live-tv-guide-source-\(status.id)")
                    Text(status.source.url.absoluteString).font(.caption)
                    PrototypeGuideSourceStatus(
                        status: status, enabled: imports.enabledSourceIDs.contains(status.id)
                    )
                }
            }
            Section {
                PrototypeImportStatus(imports: imports, listedChannels: model.guideChannelCount)
                if imports.playlistPhase == .failed {
                    if let failure = imports.playlistFailure { Text(failure.userDescription) }
                    Text("The playlist could not be loaded. Check your connection and retry. Any previously loaded channels remain available.")
                }
                if imports.guidePhase == .failed {
                    if let failure = imports.guideFailure { Text(failure.userDescription) }
                    Text("The guide could not be loaded or parsed. Retry later; this does not prevent watching channels.")
                }
                Button("Reload sources", systemImage: "arrow.clockwise", action: reload)
                    .disabled(imports.isLoading)
            }
            Section {
                Toggle("5,000 rows for scrolling", isOn: $model.isLargeCatalog)
            } header: {
                Text("Browse testing")
            } footer: {
                Text("Repeats the imported channels into labeled copies; it does not add stations. Favorites, filters and guide source choices currently last until this preview closes.")
            }
            Section {
                Text("Playback uses AetherEngine without writing watched history. Plex, Jellyfin and Emby tuning are not connected yet.")
            }
        }
        .alert("Guide selection could not be applied", isPresented: $selectionFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Reload the sources and try again. Your channels remain available.")
        }
    }
}

private struct PrototypeGuideSourceStatus: View {
    let status: LiveTVGuideSourceStatus
    let enabled: Bool

    var body: some View {
        if !enabled {
            Text("Disabled")
        } else {
            switch status.phase {
            case .idle:
                Text("Waiting to load")
            case .loading:
                Label("Loading guide", systemImage: "arrow.down.circle")
            case .loaded:
                Text("\(status.matchedChannelCount) channel matches · \(status.programCount) programs")
            case .failed:
                if let failure = status.failure { Text(failure.userDescription) }
                if status.lastRefresh != nil { Text("Keeping previously loaded listings") }
            }
            if let date = status.lastRefresh {
                Text("Last refreshed: \(date, format: .dateTime.month().day().hour().minute())")
                    .font(.caption)
            }
        }
    }
}

private struct PrototypeProgramDetails: View {
    let program: LiveTVPrototypeProgram
    let model: LiveTVPrototypeModel
    let guideSourceName: String?
    let tune: () -> Void

    var body: some View {
        Form {
            Section {
                Text(program.title).font(.title2.bold())
                Text(program.subtitle)
                Text(program.start, format: .dateTime.month().day().hour().minute())
                if let channel = model.channel(id: program.channelID) {
                    Label(channel.name, systemImage: channel.symbol)
                }
                if let guideSourceName { Text("Guide: \(guideSourceName)").font(.caption) }
            } footer: {
                Text("Watching tunes the channel live, not this program from the beginning.")
            }
            Section {
                Button("Watch channel live", systemImage: "play.fill", action: tune)
                Button(
                    model.favoriteIDs.contains(program.channelID) ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: "star"
                ) { model.toggleFavorite(program.channelID) }
            }
        }
    }
}
#endif
