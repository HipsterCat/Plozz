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
    @State private var controlsActive = false
    @State private var guideHasFocus = false
    @State private var toolbarFocusRequest = 0
    @State private var focusedProgram: LiveTVPrototypeProgram?
    @State private var loadedRequest: Int?
    @State private var guideOffset: TimeInterval = 0
    @State private var pendingTuneID: String?
    @State private var playPauseRequest = 0
    @Environment(\.themePalette) private var palette
    @Environment(\.plozzNavigationContentInset) private var navigationInset
    @Environment(\.plozzReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    private let isActive: Bool
    private let onExpandedChange: (Bool) -> Void
    private let player: (LiveTVPrototypePlayback) -> PlayerContent

    public init(
        isActive: Bool = true,
        onExpandedChange: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder player: @escaping (LiveTVPrototypePlayback) -> PlayerContent
    ) {
        self.isActive = isActive
        self.onExpandedChange = onExpandedChange
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
                size: geometry.size, safeAreaInsets: geometry.safeAreaInsets,
                navigationInset: navigationInset, largeText: typeSize.isAccessibilitySize
            )
            let videoFrame = preview.isExpanded ? layout.bounds : layout.videoFrame
            ZStack(alignment: .topLeading) {
                palette.backgroundBase.ignoresSafeArea()

                // This is the only player construction site. Its identity is
                // unchanged when the guide moves away or another channel tunes.
                if let id = model.playingChannelID,
                   let channel = model.channel(id: id), let url = channel.streamURL {
                    player(LiveTVPrototypePlayback(
                        channel: channel, streamURL: url,
                        previousChannel: { changeChannel(by: -1) },
                        nextChannel: { changeChannel(by: 1) },
                        isExpanded: preview.isExpanded,
                        returnToGuide: returnToGuide,
                        playPauseRequest: playPauseRequest
                    ))
                    .environment(\.themePalette, ThemePalette.dark)
                    .frame(width: videoFrame.width, height: videoFrame.height)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: palette.backgroundBase, location: 0),
                                .init(color: .clear, location: 0.28),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .opacity(preview.isExpanded || layout.compact ? 0 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    .position(
                        x: layoutDirection == .rightToLeft ? geometry.size.width - videoFrame.midX : videoFrame.midX,
                        y: videoFrame.midY
                    )
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: preview.isExpanded)
                }

                PrototypePreviewScrim(layout: layout, reduceTransparency: reduceTransparency)
                    .frame(width: layout.bounds.width, height: layout.bounds.height)
                    .position(
                        x: layoutDirection == .rightToLeft
                            ? geometry.size.width - layout.bounds.midX : layout.bounds.midX,
                        y: layout.bounds.midY
                    )
                    .opacity(preview.isExpanded ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: preview.isExpanded)

                VStack(spacing: PrototypeLayout.sectionGap) {
                    PrototypePreviewHero(
                        channel: heroChannel,
                        program: heroProgram,
                        isPlaying: heroChannel?.id == model.playingChannelID && model.playingChannelID != nil,
                        layout: layout,
                        watch: { if let id = heroChannel?.id { tune(id) } }
                    )
                    PrototypeBrowseToolbar(
                        model: model, active: $controlsActive,
                        focusRequest: toolbarFocusRequest,
                        compact: layout.contentFrame.width < 650,
                        search: { sheet = .search },
                        filters: { sheet = .filters },
                        more: { sheet = .options }
                    )
                    .disabled(preview.isRestoringGuideFocus)
                    PrototypeBrowser(
                        model: model, imports: imports,
                        selectedID: $selectedChannelID, railActive: $controlsActive,
                        focusedProgram: $focusedProgram,
                        hasFocus: $guideHasFocus,
                        topRequest: topRequest, guideOffset: $guideOffset,
                        restoreFocusRequest: preview.focusRestoreRequest,
                        isPresented: !preview.isExpanded,
                        isRestoringFocus: preview.isRestoringGuideFocus,
                        focusRestored: { preview.completeGuideFocusRestore($0) },
                        tune: tune,
                        details: { sheet = .program($0) },
                        openControls: { sheet = .options },
                        openToolbar: {
                            guard !preview.isRestoringGuideFocus else { return }
                            controlsActive = true
                            toolbarFocusRequest &+= 1
                        },
                        isLoading: model.channels.isEmpty
                            && (imports.playlistPhase == .idle || imports.playlistPhase == .loading),
                        loadFailed: imports.playlistPhase == .failed,
                        reload: { reloadRequest += 1 }
                    )
                }
                #if os(tvOS)
                .focusSection()
                #endif
                .frame(width: layout.contentFrame.width, height: layout.contentFrame.height)
                .position(
                    x: layoutDirection == .rightToLeft
                        ? geometry.size.width - layout.contentFrame.midX : layout.contentFrame.midX,
                    y: layout.contentFrame.midY
                )
                .opacity(preview.isExpanded ? 0 : 1)
                .offset(y: preview.isExpanded && !reduceMotion ? geometry.size.height * 0.55 : 0)
                .disabled(preview.isExpanded || !isActive)
                .allowsHitTesting(!preview.isExpanded && isActive)
                .accessibilityHidden(preview.isExpanded || !isActive)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: preview.isExpanded)
            }
        }
        .environment(\.themePalette, palette)
        .tint(palette.accent)
        .foregroundStyle(palette.primaryText)
        #if os(tvOS)
        .onPlayPauseCommand {
            if isActive && !preview.isExpanded { playPauseRequest &+= 1 }
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
                followsFocus: preview.followsFocus,
                togglePreview: { preview.setFollowsFocus(!preview.followsFocus) },
                top: { topRequest += 1 },
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
        .task(id: isActive ? reloadRequest : -1) {
            guard isActive, loadedRequest != reloadRequest else { return }
            await imports.reload(into: model)
            if !Task.isCancelled { loadedRequest = reloadRequest }
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
        .task(id: isActive) {
            while isActive && !Task.isCancelled {
                model.synchronizeClock()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: model.playingChannelID) { _, id in
            if id == nil { preview.playbackEnded() }
        }
        .onChange(of: selectedChannelID) { _, id in preview.focus(id) }
        .onChange(of: controlsActive) { _, _ in updatePreviewAvailability() }
        .onChange(of: guideHasFocus) { _, _ in updatePreviewAvailability() }
        .onChange(of: sheet?.id) { _, _ in updatePreviewAvailability() }
        .onChange(of: scenePhase, initial: true) { _, _ in updatePreviewAvailability() }
        .onChange(of: isActive, initial: true) { _, active in
            if !active {
                pendingTuneID = nil
                sheet = nil
                preview.stop()
            }
            updatePreviewAvailability()
            if active { preview.focus(selectedChannelID) }
        }
        .onChange(of: preview.isExpanded || preview.isRestoringGuideFocus) { _, hidesChrome in
            onExpandedChange(hidesChrome)
        }
        .onDisappear {
            preview.stop()
            onExpandedChange(false)
        }
    }

    private var heroChannel: LiveTVPrototypeChannel? {
        (selectedChannelID ?? model.playingChannelID).flatMap { model.channel(id: $0) }
    }

    private var heroProgram: LiveTVPrototypeProgram? {
        if let focusedProgram, focusedProgram.channelID == heroChannel?.id { return focusedProgram }
        return heroChannel.flatMap { model.currentProgram(for: $0.id) }
    }

    private func updatePreviewAvailability() {
        #if os(tvOS)
        let canFollowFocus = guideHasFocus
        #else
        let canFollowFocus = true
        #endif
        preview.setBrowsingActive(
            isActive && scenePhase == .active && sheet == nil && !controlsActive && canFollowFocus
        )
    }

    private func returnToGuide() {
        model.synchronizeClock()
        controlsActive = false
        #if os(tvOS)
        preview.returnToGuide()
        #else
        preview.returnToGuide(restoresFocus: false)
        #endif
    }

    private func tune(_ id: String) {
        guard isActive else {
            HandoffDiagnostics.emit("LIVE_TV event=watchIgnored reason=inactiveDestination")
            return
        }
        preview.watch(id)
        if !model.tuneFailed {
            selectedChannelID = id
            focusedProgram = nil
            controlsActive = false
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
