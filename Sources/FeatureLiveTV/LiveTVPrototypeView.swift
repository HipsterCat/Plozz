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
            channels: LiveTVPrototypeCatalog.channels
        ))
        _tab = State(initialValue: arguments.contains("--live-tv-guide") ? .guide : .channels)
    }

    public var body: some View {
        GeometryReader { geometry in
            let wide = usesInspector(width: geometry.size.width)
            VStack(spacing: PrototypeLayout.gap) {
                PrototypeHeader(model: model) { sheet = .demo }
                PrototypeNavigation(model: model, tab: $tab)
                PrototypeStatus(model: model)
                HStack(alignment: .top, spacing: PrototypeLayout.gap) {
                    VStack(spacing: PrototypeLayout.gap) {
                        #if os(iOS)
                        PrototypeTouchToolbar(
                            model: model,
                            search: { sheet = .search },
                            filters: { sheet = .filters },
                            top: { topRequest += 1 }
                        )
                        #endif
                        PrototypeBrowser(
                            model: model, guide: tab == .guide,
                            selectedID: $selectedChannelID, railActive: $railActive,
                            topRequest: topRequest, guideOffset: $guideOffset,
                            tune: {
                                selectedChannelID = $0
                                if !wide { tune($0) }
                            },
                            details: { sheet = .program($0) },
                            openControls: { sheet = .filters },
                            browseChannels: { tab = .channels }
                        )
                    }
                    #if os(tvOS)
                    if tab != .guide {
                        PrototypeTVControls(
                            model: model, active: $railActive,
                            search: { sheet = .search }, filters: { sheet = .filters },
                            top: { topRequest += 1 }
                        )
                        .frame(width: PrototypeLayout.controlsWidth)
                    }
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
            PrototypeSheetContent(model: model, destination: destination) { id in
                pendingTuneID = id
            }
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
        .onChange(of: tab) { _, value in
            model.favoritesOnly = value == .favorites
            railActive = false
        }
        .onChange(of: model.favoritesOnly) { _, enabled in
            if !enabled && tab == .favorites { tab = .channels }
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
    let model: LiveTVPrototypeModel
    let demo: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
                Text("Live TV").font(.largeTitle.bold())
                Text("Public channels · Live streams")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: PrototypeLayout.smallGap)
            Button(action: demo) {
                Label("Preview options", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(PrototypeButtonStyle())
            .accessibilityIdentifier("live-tv-demo")
        }
    }
}

private struct PrototypeNavigation: View {
    let model: LiveTVPrototypeModel
    @Binding var tab: PrototypeTab

    var body: some View {
        HStack(spacing: PrototypeLayout.smallGap) {
            ForEach(PrototypeTab.allCases) { item in
                Button { tab = item } label: {
                    Text(item.title)
                        #if os(iOS)
                        .frame(maxWidth: .infinity)
                        #endif
                }
                .buttonStyle(PlozzSeasonTabStyle(isSelected: tab == item))
                .accessibilityAddTraits(tab == item ? .isSelected : [])
                .accessibilityIdentifier("live-tv-tab-\(item.rawValue)")
            }
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
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(alignment: .top) {
            Text("\(model.visibleChannels.count) channels").fontWeight(.medium)
            Spacer()
            if model.isLargeCatalog {
                Text("Repeated channels · Scrolling test")
            } else if model.scenario == .staleGuide {
                Label("Guide may be out of date", systemImage: "clock.badge.exclamationmark")
            } else if model.scenario == .failedGuide {
                Label("Guide unavailable", systemImage: "wifi.exclamationmark")
            } else {
                Text("No guide connected")
            }
        }
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
        .accessibilityElement(children: .combine)
    }
}
#endif
