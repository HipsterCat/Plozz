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
    public let playbackStarted: () -> Void
}

private struct PrototypeSearchBookmark {
    let row: LiveTVGuideRowID?
    let guideOffset: TimeInterval
    let timeAnchor: Date
    let timelineOffset: CGFloat
}

public struct LiveTVPrototypeView<PlayerContent: View>: View {
    @State private var model: LiveTVPrototypeModel
    @State private var preview: LiveTVPreviewController
    @State private var imports = LiveTVPrototypeImportModel()
    @State private var reloadRequest = 0
    @State private var sheet: PrototypeSheet?
    @State private var selectedChannelID: String?
    @State private var selectedRowID: LiveTVGuideRowID?
    @State private var isSearching = false
    @State private var searchFocusRequest = 0
    @State private var searchOrigin: PrototypeSearchBookmark?
    @State private var topRequest = 0
    @State private var nowRequest = 0
    @State private var channelSequence = LiveTVChannelSequence(channels: [])
    @State private var controlsActive = false
    @State private var guideHasFocus = false
    @State private var toolbarFocusRequest = 0
    @State private var focusedProgram: LiveTVPrototypeProgram?
    @State private var loadedRequest: Int?
    @State private var guideOffset: TimeInterval = 0
    @State private var timelineOffset: CGFloat = 0
    @State private var timeAnchor = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 1_800) * 1_800)
    @State private var pendingTuneID: String?
    @State private var playPauseRequest = 0
    @Environment(\.themePalette) private var palette
    @Environment(\.plozzNavigationContentInset) private var navigationInset
    @Environment(\.plozzReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.locale) private var locale
    private let isActive: Bool
    private let viewSettingsStore: (any LiveTVViewSettingsStoring)?
    private let onExpandedChange: (Bool) -> Void
    private let player: (LiveTVPrototypePlayback) -> PlayerContent

    public init(
        isActive: Bool = true,
        preferencesStore: (any LiveTVPreferencesStoring)? = nil,
        viewSettingsStore: (any LiveTVViewSettingsStoring)? = nil,
        onExpandedChange: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder player: @escaping (LiveTVPrototypePlayback) -> PlayerContent
    ) {
        self.isActive = isActive
        self.viewSettingsStore = viewSettingsStore
        self.onExpandedChange = onExpandedChange
        self.player = player
        let arguments = ProcessInfo.processInfo.arguments
        let model = LiveTVPrototypeModel(
            now: Date(), scenario: .noGuide,
            isLargeCatalog: arguments.contains("--live-tv-5000"),
            channels: [], preferencesStore: preferencesStore
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
                navigationInset: navigationInset, largeText: typeSize.isAccessibilitySize,
                isSearching: isSearching
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
                        playPauseRequest: playPauseRequest,
                        playbackStarted: { confirmWatching(channel) }
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

                guideContent(layout, canvasWidth: geometry.size.width)
                #if os(tvOS)
                .focusSection()
                #endif
                .frame(width: geometry.size.width, height: geometry.size.height)
                .opacity(preview.isExpanded ? 0 : 1)
                .offset(y: preview.isExpanded && !reduceMotion ? geometry.size.height * 0.55 : 0)
                .disabled(preview.isExpanded || !isActive)
                .allowsHitTesting(!preview.isExpanded && isActive)
                .accessibilityHidden(preview.isExpanded || !isActive)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: preview.isExpanded)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isSearching)
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
                showGuide: {
                    model.guideOnly = true
                    topRequest += 1
                },
                guideOffset: Binding(
                    get: { guideOffset },
                    set: { guideOffset = $0; timelineOffset = 0 }
                ),
                goToNow: { nowRequest += 1 },
                guideStart: timeAnchor.addingTimeInterval(guideOffset),
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
        .alert("Live TV history unavailable", isPresented: Binding(
            get: { isActive && model.preferencesIssue != nil },
            set: { if !$0 { model.dismissPreferencesIssue() } }
        )) {
            Button("Retry") { model.retryPreferences() }
            Button("Not now", role: .cancel) { model.dismissPreferencesIssue() }
        } message: {
            if model.preferencesIssue == .loadFailed {
                Text("Your Favorites and recently watched channels could not be loaded. Retry before making changes. Your saved history has not been replaced.")
            } else {
                Text("The change to your Favorites or recently watched channels could not be saved. Retry to keep it across sessions.")
            }
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
        .onChange(of: model.sort) { _, _ in persistViewFilters() }
        .onChange(of: model.favoritesOnly) { _, _ in persistViewFilters() }
        .onChange(of: model.guideOnly) { _, _ in persistViewFilters() }
        .onChange(of: controlsActive) { _, _ in updatePreviewAvailability() }
        .onChange(of: guideHasFocus) { _, _ in updatePreviewAvailability() }
        .onChange(of: sheet?.id) { _, _ in
            updatePreviewAvailability()
            focusInitialChannelIfNeeded()
        }
        .onChange(of: model.guideChannels.first?.id, initial: true) { _, _ in
            focusInitialChannelIfNeeded()
        }
        .onChange(of: scenePhase, initial: true) { _, _ in updatePreviewAvailability() }
        .onChange(of: isActive, initial: true) { _, active in
            if !active {
                pendingTuneID = nil
                sheet = nil
                preview.stop()
            }
            if active { applyViewSettings() }
            updatePreviewAvailability()
            if active { preview.focus(selectedChannelID) }
            focusInitialChannelIfNeeded()
        }
        .onChange(of: hidesAppNavigation, initial: true) { _, hidesChrome in
            onExpandedChange(hidesChrome)
        }
        .onDisappear {
            preview.stop()
            onExpandedChange(false)
        }
    }

    @ViewBuilder
    private func guideContent(_ layout: PrototypePreviewLayout, canvasWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            #if os(tvOS)
            if isSearching {
                PrototypeGuidePlacement(frame: layout.bounds, canvasWidth: canvasWidth) {
                    PrototypeNativeSearch(
                        query: $model.query, restoresGuideFocus: preview.isRestoringGuideFocus,
                        isPresented: isActive && !preview.isExpanded && sheet == nil,
                        close: closeSearch, editing: { controlsActive = true }
                    ) { dismissSearch in
                        VStack(alignment: .leading, spacing: PrototypeLayout.smallGap) {
                            PrototypeSearchSummary(channelCount: model.visibleChannels.count, category: model.category)
                            guideBrowser(closeSearch: dismissSearch)
                        }
                        .ignoresSafeArea(.container, edges: [.bottom, .trailing])
                        .environment(\.themePalette, palette)
                        .environment(\.plozzReduceTransparency, reduceTransparency)
                        .environment(\.dynamicTypeSize, typeSize)
                        .environment(\.layoutDirection, layoutDirection)
                        .environment(\.locale, locale)
                    }
                }
                .transition(.opacity)
            } else {
                PrototypeGuidePlacement(frame: layout.contentFrame, canvasWidth: canvasWidth) {
                    browsingContent(layout)
                }
                .transition(.opacity)
            }
            #else
            PrototypeGuidePlacement(frame: layout.contentFrame, canvasWidth: canvasWidth) {
                browsingContent(layout)
            }
            #endif
        }
    }

    private func browsingContent(_ layout: PrototypePreviewLayout) -> some View {
        VStack(spacing: PrototypeLayout.sectionGap) {
            ZStack(alignment: .bottomLeading) {
                PrototypePreviewHero(
                    channel: heroChannel, program: heroProgram, layout: layout,
                    watch: { if let id = heroChannel?.id { tune(id) } }
                )
                .opacity(isSearching ? 0 : 1)
                .allowsHitTesting(!isSearching)
                .accessibilityHidden(isSearching)
                #if os(iOS)
                if isSearching {
                    PrototypeSearchHeader(
                        query: $model.query, channelCount: model.visibleChannels.count,
                        category: model.category, focusRequest: searchFocusRequest,
                        browse: enterGuide, close: closeSearch,
                        focusChanged: { if $0 { controlsActive = true } }
                    )
                    .frame(maxWidth: min(layout.contentFrame.width, 1_200), alignment: .leading)
                    .disabled(blocksBrowseControls)
                    .transition(.opacity)
                }
                #endif
            }
            .frame(height: layout.heroHeight, alignment: .bottomLeading)
            HStack(alignment: .top, spacing: PrototypeLayout.sectionGap) {
                if layout.sidebarWidth > 0 {
                    PrototypeBrowseSidebar(
                        model: model, active: $controlsActive,
                        focusRequest: toolbarFocusRequest, isSearching: isSearching,
                        search: { if isSearching { closeSearch() } else { openSearch() } },
                        enterGuide: enterGuide
                    )
                    .frame(width: layout.sidebarWidth)
                    .disabled(blocksBrowseControls)
                }
                VStack(spacing: PrototypeLayout.sectionGap) {
                    if layout.sidebarWidth == 0 {
                        PrototypeBrowseToolbar(
                            model: model, active: $controlsActive,
                            focusRequest: toolbarFocusRequest,
                            compact: layout.contentFrame.width < 650,
                            isSearching: isSearching,
                            search: { if isSearching { closeSearch() } else { openSearch() } },
                            filters: { sheet = .filters }
                        )
                        .disabled(blocksBrowseControls)
                    }
                    guideBrowser(closeSearch: closeSearch)
                }
                .frame(width: layout.guideWidth + layout.guideTrailingExtension)
                .padding(.trailing, -layout.guideTrailingExtension)
                .padding(.bottom, -layout.guideBottomExtension)
            }
        }
    }

    private func guideBrowser(closeSearch: @escaping () -> Void) -> some View {
        PrototypeBrowser(
            model: model, imports: imports,
            selectedID: $selectedChannelID, selectedRowID: $selectedRowID,
            railActive: $controlsActive, focusedProgram: $focusedProgram, hasFocus: $guideHasFocus,
            topRequest: topRequest, nowRequest: nowRequest, guideOffset: $guideOffset,
            timeAnchor: $timeAnchor, timelineOffset: $timelineOffset,
            restoreFocusRequest: preview.focusRestoreRequest,
            isPresented: !preview.isExpanded, isRestoringFocus: preview.isRestoringGuideFocus,
            restoresPlaybackFocus: preview.restoresPlaybackFocus, watchOrigin: preview.watchOrigin,
            focusRestored: { preview.completeGuideFocusRestore($0) },
            tune: { tune($0.channelID, origin: $0) },
            details: { sheet = .program($0) }, openControls: openSearch,
            openSources: { sheet = .sources }, openGuideTime: { sheet = .guideTime },
            openToolbar: {
                guard !preview.isRestoringGuideFocus else { return }
                if isSearching {
                    closeSearch()
                    return
                }
                controlsActive = true
                toolbarFocusRequest &+= 1
            },
            isLoading: model.channels.isEmpty && (imports.playlistPhase == .idle || imports.playlistPhase == .loading),
            loadFailed: imports.playlistPhase == .failed,
            reload: { reloadRequest += 1 }
        )
    }

    private var hidesAppNavigation: Bool {
        #if os(tvOS)
        preview.suppressesNavigation(isActive: isActive, isSearching: isSearching)
        #else
        preview.suppressesNavigation(isActive: isActive)
        #endif
    }

    private var blocksBrowseControls: Bool {
        #if os(tvOS)
        if !preview.hasRequestedInitialGuideFocus,
           model.guideChannels.first != nil || imports.playlistPhase == .idle || imports.playlistPhase == .loading {
            return true
        }
        #endif
        return preview.isRestoringGuideFocus
    }

    private func focusInitialChannelIfNeeded() {
        #if os(tvOS)
        guard let row = preview.requestInitialGuideFocus(
            isActive: isActive, hasOverlay: isSearching || sheet != nil
        ) else { return }
        selectedRowID = row
        selectedChannelID = row.channelID
        focusedProgram = nil
        controlsActive = false
        #endif
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

    private func openSearch() {
        guard !isSearching else {
            searchFocusRequest &+= 1
            return
        }
        #if os(tvOS)
        // Gate the shell before UIKit presents its keyboard and claims focus.
        onExpandedChange(true)
        #endif
        searchOrigin = PrototypeSearchBookmark(
            row: selectedRowID, guideOffset: guideOffset, timeAnchor: timeAnchor, timelineOffset: timelineOffset
        )
        guideOffset = 0
        timelineOffset = 0
        timeAnchor = Date(timeIntervalSince1970: floor(model.now.timeIntervalSince1970 / 1_800) * 1_800)
        #if os(tvOS)
        selectedRowID = model.guideChannels.first?.id
        selectedChannelID = selectedRowID?.channelID
        focusedProgram = nil
        #endif
        controlsActive = true
        isSearching = true
        searchFocusRequest &+= 1
    }

    private func closeSearch() {
        guard isSearching else { return }
        model.query = ""
        if let bookmark = searchOrigin {
            guideOffset = bookmark.guideOffset
            timeAnchor = bookmark.timeAnchor
            timelineOffset = bookmark.timelineOffset
        }
        if let origin = searchOrigin?.row, let row = model.guideRow(for: origin.channelID, preferring: origin.section) {
            selectedRowID = row
            selectedChannelID = row.channelID
        }
        searchOrigin = nil
        enterGuide()
        isSearching = false
    }

    private func enterGuide() {
        controlsActive = false
        guard isActive else { return }
        #if os(tvOS)
        preview.requestBrowsingFocus()
        #endif
    }

    private func applyViewSettings() {
        guard let settings = viewSettingsStore?.load() else { return }
        model.sort = settings.sortByName ? .name : .channelNumber
        model.favoritesOnly = settings.favoritesOnly
        model.guideOnly = settings.guideOnly
        #if os(tvOS)
        preview.setFollowsFocus(settings.autoPreview)
        #endif
    }

    private func persistViewFilters() {
        guard let viewSettingsStore else { return }
        let current = viewSettingsStore.load()
        var settings = current
        settings.sortByName = model.sort == .name
        settings.favoritesOnly = model.favoritesOnly
        settings.guideOnly = model.guideOnly
        if settings != current { viewSettingsStore.save(settings) }
    }

    private func tune(_ id: String, origin: LiveTVGuideRowID? = nil) {
        guard isActive else {
            HandoffDiagnostics.emit("LIVE_TV event=watchIgnored reason=inactiveDestination")
            return
        }
        if !preview.isExpanded {
            channelSequence = LiveTVChannelSequence(channels: model.guideChannels.map(\.channel))
        }
        let selectedOrigin = !preview.isExpanded && selectedRowID?.channelID == id ? selectedRowID : nil
        preview.watch(id, origin: origin ?? selectedOrigin)
        if !model.tuneFailed {
            selectedChannelID = id
            selectedRowID = preview.watchOrigin
            focusedProgram = nil
            controlsActive = false
        }
    }

    private func changeChannel(by offset: Int) {
        guard let id = channelSequence.neighbor(
            of: model.playingChannelID, offset: offset, visibleChannels: model.visibleChannels
        ) else { return }
        tune(id)
    }

    private func confirmWatching(_ channel: LiveTVPrototypeChannel) {
        guard isActive, preview.isExpanded,
              let current = model.channel(id: channel.id),
              current.streamURL == channel.streamURL, current.httpHeaders == channel.httpHeaders
        else {
            HandoffDiagnostics.emit("LIVE_TV event=watchConfirmationIgnored reason=staleOrInactive")
            return
        }
        if !model.recordWatched(channel.id) {
            HandoffDiagnostics.emit("LIVE_TV event=watchHistoryNotRecorded reason=unavailableOrStale")
        }
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
