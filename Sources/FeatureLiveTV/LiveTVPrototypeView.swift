#if DEBUG
import CoreUI
import FeatureLiveTVCore
import SwiftUI

public enum LiveTVPrototypeEntry {
    public static var isEnabled: Bool { LiveTVPrototypeLaunch.isEnabled() }
}

public struct LiveTVPrototypePlayback {
    public let channel: LiveTVPrototypeChannel
    public let streamURL: URL
    public let previousChannel: () -> Void
    public let nextChannel: () -> Void
}

public struct LiveTVPrototypeView<PlayerContent: View>: View {
    @State private var model: LiveTVPrototypeModel
    @State private var imports = LiveTVPrototypeImportModel()
    @State private var reloadRequest = 0
    @State private var tab: PrototypeTab = .channels
    @State private var sheet: PrototypeSheet?
    @State private var showingPlayer = false
    @State private var selectedChannelID: String?
    @State private var topRequest = 0
    @State private var railActive = false
    @State private var guideOffset: TimeInterval = 0
    @State private var pendingTuneID: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private let player: (LiveTVPrototypePlayback) -> PlayerContent

    public init(@ViewBuilder player: @escaping (LiveTVPrototypePlayback) -> PlayerContent) {
        self.player = player
        let arguments = ProcessInfo.processInfo.arguments
        _model = State(initialValue: LiveTVPrototypeModel(
            now: Date(), scenario: .noGuide,
            isLargeCatalog: arguments.contains("--live-tv-5000"),
            channels: []
        ))
        _tab = State(initialValue: arguments.contains("--live-tv-guide") ? .guide : .channels)
    }

    public var body: some View {
        GeometryReader { geometry in
            let wide = usesInspector(width: geometry.size.width)
            VStack(spacing: PrototypeLayout.gap) {
                PrototypeHeader()
                PrototypeNavigation(model: model, tab: $tab)
                PrototypeStatus(model: model, imports: imports)
                HStack(alignment: .top, spacing: PrototypeLayout.gap) {
                    VStack(spacing: PrototypeLayout.gap) {
                        #if os(iOS)
                        PrototypeTouchToolbar(
                            model: model,
                            search: { sheet = .search },
                            filters: { sheet = .filters },
                            sources: { sheet = .sources },
                            top: { topRequest += 1 }
                        )
                        #endif
                        PrototypeBrowser(
                            model: model, imports: imports, guide: tab == .guide,
                            selectedID: $selectedChannelID, railActive: $railActive,
                            topRequest: topRequest, guideOffset: $guideOffset,
                            tune: {
                                selectedChannelID = $0
                                if !wide { tune($0) }
                            },
                            details: { sheet = .program($0) },
                            openControls: { sheet = .filters },
                            isLoading: model.channels.isEmpty
                                && (imports.playlistPhase == .idle || imports.playlistPhase == .loading),
                            loadFailed: imports.playlistPhase == .failed,
                            reload: { reloadRequest += 1 }
                        )
                    }
                    #if os(tvOS)
                    PrototypeTVControls(
                        model: model, active: $railActive,
                        search: { sheet = .search }, filters: { sheet = .filters },
                        sources: { sheet = .sources },
                        top: { topRequest += 1 }
                    )
                    .frame(width: PrototypeLayout.controlsWidth)
                    #else
                    if wide {
                        PrototypeInspector(
                            model: model, selectedID: selectedChannelID,
                            watch: { tune($0) }
                        )
                        .frame(width: min(390, geometry.size.width * 0.35))
                    }
                    #endif
                }
            }
            .padding(PrototypeLayout.inset)
            .background(
                LinearGradient(
                    colors: [palette.backgroundBase, palette.backgroundSecondary],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()
            )
        }
        .environment(\.themePalette, palette)
        .tint(palette.accent)
        .foregroundStyle(palette.primaryText)
        .sheet(item: $sheet, onDismiss: {
            if let id = pendingTuneID {
                pendingTuneID = nil
                tune(id)
            }
        }) { destination in
            PrototypeSheetContent(
                model: model, imports: imports, destination: destination,
                reload: { reloadRequest += 1 },
                showGuide: {
                    model.guideOnly = true
                    tab = .guide
                    topRequest += 1
                },
                tune: { pendingTuneID = $0 }
            )
            .environment(\.themePalette, palette)
            .tint(palette.accent)
        }
        .fullScreenCover(isPresented: $showingPlayer, onDismiss: { model.stop() }) {
            if let id = model.playingChannelID,
               let channel = model.channel(id: id), let url = channel.streamURL {
                player(LiveTVPrototypePlayback(
                    channel: channel, streamURL: url,
                    previousChannel: { changeChannel(by: -1) },
                    nextChannel: { changeChannel(by: 1) }
                ))
                .id(channel.id)
                .environment(\.themePalette, ThemePalette.dark)
            }
        }
        .alert("All tuners are busy", isPresented: Binding(
            get: { model.tuneFailed },
            set: { if !$0 { model.clearTuneFailure() } }
        )) {
            Button("OK", role: .cancel) { model.clearTuneFailure() }
        } message: {
            Text("Demo scenario: another viewer is using the tuner. Your current channel has not changed.")
        }
        .task(id: reloadRequest) {
            await imports.reload(into: model)
        }
        .task {
            while !Task.isCancelled {
                model.synchronizeClock()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: model.playingChannelID) { _, id in
            if id == nil { showingPlayer = false }
        }
    }

    private var palette: ThemePalette { colorScheme == .light ? .light : .dark }

    private func usesInspector(width: CGFloat) -> Bool {
        #if os(tvOS)
        false
        #else
        width >= 980 && !typeSize.isAccessibilitySize
        #endif
    }

    private func tune(_ id: String) {
        model.tune(id)
        if !model.tuneFailed {
            selectedChannelID = id
            showingPlayer = true
        }
    }

    private func changeChannel(by offset: Int) {
        guard !model.visibleChannels.isEmpty,
              let index = model.visibleChannels.firstIndex(where: { $0.id == model.playingChannelID })
        else { return }
        let count = model.visibleChannels.count
        tune(model.visibleChannels[(index + offset + count) % count].id)
    }
}

private struct PrototypeHeader: View {
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
                Text("Live TV").font(.largeTitle.bold())
                Text("US public playlist · Live streams")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: PrototypeLayout.smallGap)
        }
    }
}

private struct PrototypeNavigation: View {
    @Bindable var model: LiveTVPrototypeModel
    @Binding var tab: PrototypeTab

    var body: some View {
        HStack(spacing: PrototypeLayout.smallGap) {
            Picker("View", selection: $tab) {
                ForEach(PrototypeTab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            #if os(tvOS)
            .frame(maxWidth: 460)
            #endif
            .accessibilityIdentifier("live-tv-view-mode")
            Button {
                model.favoritesOnly.toggle()
            } label: {
                Label("Favorites", systemImage: model.favoritesOnly ? "star.fill" : "star")
                    #if os(iOS)
                    .labelStyle(.iconOnly)
                    #endif
            }
            .buttonStyle(PrototypeButtonStyle(selected: model.favoritesOnly))
            .accessibilityAddTraits(model.favoritesOnly ? .isSelected : [])
            .accessibilityIdentifier("live-tv-favorites-filter")
            #if os(tvOS)
            Spacer()
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.title3.monospacedDigit())
            }
            #endif
        }
    }
}

private struct PrototypeStatus: View {
    let model: LiveTVPrototypeModel
    let imports: LiveTVPrototypeImportModel
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.visibleChannels.count) of \(model.channels.count) channels").fontWeight(.medium)
                if !model.query.isEmpty { Text("Search: \(model.query)").lineLimit(1) }
                if let category = model.category { Text(category).lineLimit(1) }
                if model.guideOnly { Text("With guide listings") }
            }
            Spacer()
            if model.isLargeCatalog {
                Text("Repeated channels · Scrolling test")
            } else {
                PrototypeImportStatus(imports: imports, listedChannels: model.guideChannelCount)
            }
        }
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
        .accessibilityElement(children: .combine)
    }
}

struct PrototypeImportStatus: View {
    let imports: LiveTVPrototypeImportModel
    let listedChannels: Int

    var body: some View {
        if imports.playlistPhase == .loading || imports.playlistPhase == .idle {
            Label("Loading playlist", systemImage: "arrow.down.circle")
        } else if imports.playlistPhase == .failed {
            Label("Playlist update failed · Open Sources", systemImage: "wifi.exclamationmark")
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                if imports.enabledSourceIDs.isEmpty {
                    Text("Guide sources off · Channels ready")
                } else {
                    switch imports.guidePhase {
                    case .idle:
                        Label("Guide not loaded · Open Sources", systemImage: "calendar")
                    case .loading:
                        Text("Loading guides · \(imports.completedSourceCount) of \(imports.enabledSourceIDs.count) sources")
                        Text("\(listedChannels) channels with listings so far")
                    case .failed:
                        Label("Guide update failed · Channels ready", systemImage: "wifi.exclamationmark")
                    case .loaded:
                        if let end = imports.coverageEnd, end < Date() {
                            Label("Guide listings are out of date", systemImage: "clock.badge.exclamationmark")
                        } else {
                            Text("Guide listings for \(listedChannels) channels")
                        }
                    }
                    if imports.failedSourceCount > 0 {
                        Text("\(imports.failedSourceCount) guide sources unavailable · Open Sources")
                    }
                }
            }
        }
    }
}
#endif
