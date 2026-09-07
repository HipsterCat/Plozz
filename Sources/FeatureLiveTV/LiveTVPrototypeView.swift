#if DEBUG
import CoreUI
import CoreModels
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
    public let isExpanded: Bool
    public let returnToGuide: () -> Void
    public let playPauseRequest: Int
}

public struct LiveTVPrototypeView<PlayerContent: View>: View {
    @State private var model: LiveTVPrototypeModel
    @State private var preview: LiveTVPreviewController
    @State private var imports = LiveTVPrototypeImportModel()
    @State private var reloadRequest = 0
    @State private var sheet: PrototypeSheet?
    @State private var selectedChannelID: String?
    @State private var topRequest = 0
    @State private var railActive = false
    @State private var guideOffset: TimeInterval = 0
    @State private var pendingTuneID: String?
    @State private var playPauseRequest = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @ScaledMetric(relativeTo: .headline) private var stackedMetadataHeight = 66
    private let player: (LiveTVPrototypePlayback) -> PlayerContent

    public init(@ViewBuilder player: @escaping (LiveTVPrototypePlayback) -> PlayerContent) {
        self.player = player
        let arguments = ProcessInfo.processInfo.arguments
        let model = LiveTVPrototypeModel(
            now: Date(), scenario: .noGuide,
            isLargeCatalog: arguments.contains("--live-tv-5000"),
            channels: []
        )
        _model = State(initialValue: model)
        #if os(tvOS)
        _preview = State(initialValue: LiveTVPreviewController(model: model))
        #else
        _preview = State(initialValue: LiveTVPreviewController(model: model, followsFocus: false))
        #endif
    }

    public var body: some View {
        GeometryReader { geometry in
            let layout = PrototypePreviewLayout(
                size: geometry.size, largeText: typeSize.isAccessibilitySize,
                metadataHeight: stackedMetadataHeight
            )
            let fullFrame = CGRect(
                x: -geometry.safeAreaInsets.leading, y: -geometry.safeAreaInsets.top,
                width: geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing,
                height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            )
            let videoFrame = preview.isExpanded ? fullFrame : layout.videoFrame
            ZStack(alignment: .topLeading) {
                palette.backgroundBase.ignoresSafeArea()
                LinearGradient(
                    colors: [palette.backgroundSecondary, palette.backgroundBase],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: layout.heroHeight + PrototypeLayout.inset)

                // This is the only player construction site. Its identity is
                // unchanged when the guide moves away or another channel tunes.
                if let id = model.playingChannelID,
                   let channel = model.channel(id: id), let url = channel.streamURL {
                    player(LiveTVPrototypePlayback(
                        channel: channel, streamURL: url,
                        previousChannel: { changeChannel(by: -1) },
                        nextChannel: { changeChannel(by: 1) },
                        isExpanded: preview.isExpanded,
                        returnToGuide: { preview.returnToGuide() },
                        playPauseRequest: playPauseRequest
                    ))
                    .environment(\.themePalette, ThemePalette.dark)
                    .frame(width: videoFrame.width, height: videoFrame.height)
                    .clipped()
                    .position(
                        x: layoutDirection == .rightToLeft ? geometry.size.width - videoFrame.midX : videoFrame.midX,
                        y: videoFrame.midY
                    )
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: preview.isExpanded)
                }

                #if os(iOS)
                if let channel = heroChannel {
                    PrototypePreviewExpandButton { tune(channel.id) }
                        .frame(width: layout.videoFrame.width, height: layout.videoFrame.height)
                        .position(
                            x: layoutDirection == .rightToLeft
                                ? geometry.size.width - layout.videoFrame.midX : layout.videoFrame.midX,
                            y: layout.videoFrame.midY
                        )
                        .opacity(preview.isExpanded ? 0 : 1)
                        .disabled(preview.isExpanded)
                        .allowsHitTesting(!preview.isExpanded)
                        .accessibilityHidden(preview.isExpanded)
                }
                #endif

                HStack(alignment: .top, spacing: PrototypeLayout.gap) {
                    VStack(spacing: PrototypeLayout.gap) {
                        PrototypePreviewHero(
                            channel: heroChannel,
                            program: heroChannel.flatMap { model.currentProgram(for: $0.id) },
                            hasPlayer: model.playingChannelID != nil,
                            followsFocus: preview.followsFocus,
                            layout: layout,
                            watch: { if let id = heroChannel?.id { tune(id) } }
                        )
                        PrototypeNavigation(model: model)
                            .disabled(railActive)
                        PrototypeStatus(model: model, imports: imports)
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
                            model: model, imports: imports,
                            selectedID: $selectedChannelID, railActive: $railActive,
                            topRequest: topRequest, guideOffset: $guideOffset,
                            restoreFocusRequest: preview.focusRestoreRequest,
                            isPresented: !preview.isExpanded,
                            tune: tune,
                            details: { sheet = .program($0) },
                            openControls: { sheet = .filters },
                            isLoading: model.channels.isEmpty
                                && (imports.playlistPhase == .idle || imports.playlistPhase == .loading),
                            loadFailed: imports.playlistPhase == .failed,
                            reload: { reloadRequest += 1 }
                        )
                        .background(palette.backgroundBase)
                    }
                    .frame(width: layout.contentWidth)
                    #if os(tvOS)
                    .focusSection()
                    #endif
                    #if os(tvOS)
                    PrototypeTVControls(
                        model: model, active: $railActive,
                        search: { sheet = .search }, filters: { sheet = .filters },
                        sources: { sheet = .sources },
                        top: { topRequest += 1 },
                        followsFocus: preview.followsFocus,
                        togglePreview: { preview.setFollowsFocus(!preview.followsFocus) }
                    )
                    .frame(width: PrototypeLayout.controlsWidth)
                    #endif
                }
                .padding(PrototypeLayout.inset)
                .opacity(preview.isExpanded ? 0 : 1)
                .offset(y: preview.isExpanded && !reduceMotion ? geometry.size.height * 0.55 : 0)
                .disabled(preview.isExpanded)
                .allowsHitTesting(!preview.isExpanded)
                .accessibilityHidden(preview.isExpanded)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: preview.isExpanded)
            }
        }
        .environment(\.themePalette, palette)
        .tint(palette.accent)
        .foregroundStyle(palette.primaryText)
        #if os(tvOS)
        .onPlayPauseCommand {
            if !preview.isExpanded { playPauseRequest &+= 1 }
        }
        #endif
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
                    topRequest += 1
                },
                tune: { pendingTuneID = $0 }
            )
            .environment(\.themePalette, palette)
            .tint(palette.accent)
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
        .task(id: preview.pendingRequest) {
            guard let request = preview.pendingRequest else { return }
            do {
                try await Task.sleep(for: LiveTVPreviewController.settlingDelay)
            } catch is CancellationError {
                return
            } catch {
                assertionFailure("Unexpected preview timer failure: \(error)")
                return
            }
            guard !Task.isCancelled else { return }
            if preview.commitPreview(request) {
                let elapsed = request.focusedAt.duration(to: ContinuousClock.now).components
                let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
                HandoffDiagnostics.emit(
                    "LIVE_TV event=previewCommit settleMs=\(String(format: "%.0f", milliseconds))"
                )
            }
        }
        .task {
            while !Task.isCancelled {
                model.synchronizeClock()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: model.playingChannelID) { _, id in
            if id == nil { preview.playbackEnded() }
        }
        .onChange(of: selectedChannelID) { _, id in preview.focus(id) }
        .onChange(of: railActive) { _, _ in updatePreviewAvailability() }
        .onChange(of: sheet?.id) { _, _ in updatePreviewAvailability() }
        .onChange(of: scenePhase, initial: true) { _, _ in updatePreviewAvailability() }
        .onDisappear { preview.stop() }
    }

    private var palette: ThemePalette { colorScheme == .light ? .light : .dark }

    private var heroChannel: LiveTVPrototypeChannel? {
        (model.playingChannelID ?? selectedChannelID).flatMap { model.channel(id: $0) }
    }

    private func updatePreviewAvailability() {
        preview.setBrowsingActive(scenePhase == .active && sheet == nil && !railActive)
    }

    private func tune(_ id: String) {
        preview.watch(id)
        if !model.tuneFailed {
            selectedChannelID = id
            railActive = false
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

private struct PrototypeNavigation: View {
    @Bindable var model: LiveTVPrototypeModel

    var body: some View {
        HStack(spacing: PrototypeLayout.smallGap) {
            Text("Live TV").font(.title2.bold())
            Spacer()
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
