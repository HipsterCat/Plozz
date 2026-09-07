#if DEBUG
import CoreUI
import FeatureLiveTVCore
import SwiftUI

#if os(tvOS)
struct PrototypeTVControls: View {
    @Bindable var model: LiveTVPrototypeModel
    @Binding var active: Bool
    let search: () -> Void
    let filters: () -> Void
    let sources: () -> Void
    let top: () -> Void
    @FocusState private var focused: Control?
    @Environment(\.themePalette) private var palette

    private enum Control: Hashable { case search, filters, sort, sources, top }

    var body: some View {
        VStack(alignment: .leading, spacing: PrototypeLayout.gap) {
            Text("Browse controls").font(.headline)
                .foregroundStyle(palette.secondaryText)
            Button(action: search) {
                Label("Search", systemImage: "magnifyingglass").frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($focused, equals: .search)
            Button(action: filters) {
                Label("Filters", systemImage: "line.3.horizontal.decrease")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($focused, equals: .filters)
            .disabled(!active)
            Button {
                model.sort = model.sort == .channelNumber ? .name : .channelNumber
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                    Text(model.sort.title).font(.caption).opacity(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($focused, equals: .sort)
            .disabled(!active)
            Button(action: sources) {
                Label("Sources", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($focused, equals: .sources)
            .disabled(!active)
            .accessibilityIdentifier("live-tv-sources")
            Button(action: top) {
                Label("Back to top", systemImage: "arrow.up.to.line")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($focused, equals: .top)
            .disabled(!active)
            Text("Press Right for controls.\nLeft returns to your channel.")
                .font(.caption).foregroundStyle(palette.secondaryText)
                .padding(.top, PrototypeLayout.gap)
            Spacer(minLength: 0)
        }
        .buttonStyle(PrototypeButtonStyle())
        .focusSection()
        .onChange(of: focused) { _, target in
            if target != nil { active = true }
        }
    }
}
#endif

#if os(iOS)
struct PrototypeTouchToolbar: View {
    @Bindable var model: LiveTVPrototypeModel
    let search: () -> Void
    let filters: () -> Void
    let sources: () -> Void
    let top: () -> Void

    var body: some View {
        HStack(spacing: PrototypeLayout.smallGap) {
            Button("Search", systemImage: "magnifyingglass", action: search)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Filters", systemImage: "line.3.horizontal.decrease", action: filters)
                .labelStyle(.iconOnly)
            Menu {
                Picker("Sort", selection: $model.sort) {
                    ForEach(LiveTVPrototypeSort.allCases) { sort in Text(sort.title).tag(sort) }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down").labelStyle(.iconOnly)
            }
            Button("Back to top", systemImage: "arrow.up.to.line", action: top)
                .labelStyle(.iconOnly)
            Button("Sources", systemImage: "antenna.radiowaves.left.and.right", action: sources)
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("live-tv-sources")
        }
        .font(.subheadline)
        .buttonStyle(PrototypeButtonStyle())
    }
}
#endif

struct PrototypeSheetContent: View {
    @Bindable var model: LiveTVPrototypeModel
    let imports: LiveTVPrototypeImportModel
    let destination: PrototypeSheet
    let reload: () -> Void
    let showGuide: () -> Void
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
                        .navigationTitle("Browse controls")
                case .sources:
                    PrototypeSourcesForm(model: model, imports: imports, reload: reload) {
                        showGuide()
                        dismiss()
                    }
                    .navigationTitle("Live TV sources")
                case .program(let program):
                    PrototypeProgramDetails(program: program, model: model) {
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
                            PrototypeStationMark(channel: channel, size: 32)
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
                Picker("Category", selection: $model.category) {
                    Text("All categories").tag(String?.none)
                    ForEach(model.categories, id: \.self) { category in
                        Text(category).tag(Optional(category))
                    }
                }
                Picker("Source", selection: $model.source) {
                    Text("All sources").tag(LiveTVPrototypeSource?.none)
                    ForEach(LiveTVPrototypeSource.allCases.filter { source in
                        model.channels.contains { $0.source == source }
                    }) { source in
                        Text(source.title).tag(Optional(source))
                    }
                }
                Toggle("Favorites only", isOn: $model.favoritesOnly)
                Toggle("With guide listings", isOn: $model.guideOnly)
                Picker("Sort", selection: $model.sort) {
                    ForEach(LiveTVPrototypeSort.allCases) { sort in Text(sort.title).tag(sort) }
                }
            }
            Section {
                Button("Clear filters") { model.resetFilters() }
                Text("\(model.visibleChannels.count) matching channels")
            }
        }
    }
}

private struct PrototypeSourcesForm: View {
    @Bindable var model: LiveTVPrototypeModel
    let imports: LiveTVPrototypeImportModel
    let reload: () -> Void
    let showGuide: () -> Void

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
                Text("EPGShare · US2").font(.headline)
                Text(imports.guideURL.absoluteString).font(.caption)
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
                Text("Only identified channel matches receive schedules. Unmatched channels stay watchable and show no invented program information.")
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
                Text("Repeats the imported channels into labeled copies; it does not add stations. Favorites and filters currently last until this preview closes.")
            }
            Section {
                Text("Playback uses AetherEngine without writing watched history. Plex, Jellyfin and Emby tuning are not connected yet.")
            }
        }
    }
}

private struct PrototypeProgramDetails: View {
    let program: LiveTVPrototypeProgram
    let model: LiveTVPrototypeModel
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
