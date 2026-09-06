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
    let top: () -> Void
    @FocusState private var focused: Control?
    @Environment(\.themePalette) private var palette

    private enum Control: Hashable { case search, filters, sort, top }

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
        }
        .font(.subheadline)
        .buttonStyle(PrototypeButtonStyle())
    }
}
#endif

struct PrototypeSheetContent: View {
    @Bindable var model: LiveTVPrototypeModel
    let destination: PrototypeSheet
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
                case .demo:
                    PrototypeDemoForm(model: model)
                        .navigationTitle("Live TV preview")
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

private struct PrototypeDemoForm: View {
    @Bindable var model: LiveTVPrototypeModel

    var body: some View {
        Form {
            Section {
                Toggle("5,000 rows for scrolling", isOn: $model.isLargeCatalog)
            } header: {
                Text("Browse testing")
            } footer: {
                Text("The large list repeats these same real channels; it does not add 5,000 unique stations. Favorites last until this preview closes.")
            }
            Section {
                Text("These public HLS channels use Plozz's existing playback engine. Channel availability can change or vary by region.")
                Text("No guide is connected, so no program titles or schedules are invented. Plex, Jellyfin and Emby tuning are not connected yet.")
            } header: {
                Text("Real playback")
            }
            Section {
                Text("This isolated preview does not sign into media servers or write watched history. Playlist import, XMLTV, Picture in Picture and AirPlay integration are still planned.")
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
                Text("Demo schedule. Watching tunes the channel live, not this program from the beginning.")
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
