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
    public let httpHeaders: [String: String]
    public let previousChannel: () -> Void
    public let nextChannel: () -> Void
    public let isFavorite: Bool
    public let canToggleFavorite: Bool
    public let onToggleFavorite: () -> Void
    public let isExpanded: Bool
    public let returnToGuide: () -> Void
    public let playPauseRequest: Int
    public let playbackStarted: () -> Void
    public let reportingID: UUID
    public let playbackUpdate: @MainActor (LiveTVPlaybackUpdate) -> Void
    public let playbackFailed: @MainActor () -> Void
    public let preparingChannelName: String?
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
    @State private var imports: LiveTVPrototypeImportModel
    @State private var playback: LiveTVPlaybackCoordinator
    @State private var sources: LiveTVSourceManagementModel?
    @State private var sourceApplicationFailed = false
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
    @State private var pendingServerConnection = false
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
    private let usesNativeFullscreen: Bool
    private let viewSettingsStore: (any LiveTVViewSettingsStoring)?
    private let didConfigurePlaylist: () -> Void
    private let serverProviderResolver: LiveTVServerProviderResolver
    private let serverChoices: [LiveTVServerChoice]
    private let serverAuthorizationID: String
    private let isProfileAuthorized: @MainActor @Sendable () -> Bool
    private let connectServer: (() -> Void)?
    private let onExpandedChange: (Bool) -> Void
    private let player: (LiveTVPrototypePlayback) -> PlayerContent

    public init(
        isActive: Bool = true,
        usesNativeFullscreen: Bool = false,
        preferencesStore: (any LiveTVPreferencesStoring)? = nil,
        viewSettingsStore: (any LiveTVViewSettingsStoring)? = nil,
        sourceStore: (any LiveTVSourcesStoring)? = nil,
        serverProviderResolver: LiveTVServerProviderResolver? = nil,
        authenticatedHTTPResolver: (any AuthenticatedHTTPResourceResolving)? = nil,
        isProfileAuthorized: @escaping @MainActor @Sendable () -> Bool = { true },
        serverChoices: [LiveTVServerChoice] = [],
        serverAuthorizationID: String = "",
        connectServer: (() -> Void)? = nil,
        didConfigurePlaylist: @escaping () -> Void = {},
        onExpandedChange: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder player: @escaping (LiveTVPrototypePlayback) -> PlayerContent
    ) {
        self.isActive = isActive
        self.usesNativeFullscreen = usesNativeFullscreen
        self.viewSettingsStore = viewSettingsStore
        let resolver: LiveTVServerProviderResolver = serverProviderResolver ?? { _ in nil }
        self.serverProviderResolver = resolver
        self.isProfileAuthorized = isProfileAuthorized
        self.serverChoices = serverChoices
        self.serverAuthorizationID = serverAuthorizationID
        self.connectServer = connectServer
        self.didConfigurePlaylist = didConfigurePlaylist
        let sources = sourceStore.map {
            LiveTVSourceManagementModel(store: $0, canMutate: { false })
        }
        _sources = State(initialValue: sources)
        let imports = LiveTVPrototypeImportModel(configuration: .empty, serverProviderResolver: resolver)
        _imports = State(initialValue: imports)
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
        let preview = LiveTVPreviewController(model: model)
        #else
        let preview = LiveTVPreviewController(model: model, followsFocus: false)
        #endif
        _preview = State(initialValue: preview)
        _playback = State(initialValue: LiveTVPlaybackCoordinator(
            model: model, preview: preview,
            preparation: LiveTVPlaybackPreparation(
                serverProviderResolver: resolver, authenticatedHTTPResolver: authenticatedHTTPResolver
            ),
            reference: { imports.serverChannelReferences[$0] },
            isAuthorized: { channel, reference in
                isProfileAuthorized() && (sources?.hasLoaded ?? true)
                    && LiveTVPlaybackCatalogAuthorization.allows(
                    channel, reference: reference, model: model, imports: imports,
                    configuration: sources?.configuration ?? imports.configuration
                )
            },
            isGuideOnly: { channelID in
                guard let reference = imports.serverChannelReferences[channelID] else { return false }
                return imports.serverSources.first(where: { $0.id == reference.sourceID })?
                    .availability?.status == .unsupportedPlaybackMode
            }
        ))
    }

    public var body: some View {
        lifecycleContent
    }

    private var playerAndGuideSurface: some View {
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
                if let prepared = playback.preparation.current {
                    let presentationID = playback.presentationID
                    player(LiveTVPrototypePlayback(
                        channel: prepared.channel, streamURL: prepared.resolvedURL,
                        httpHeaders: prepared.httpHeaders,
                        previousChannel: { changeChannel(by: -1) },
                        nextChannel: { changeChannel(by: 1) },
                        isFavorite: model.favoriteIDs.contains(prepared.channel.id),
                        canToggleFavorite: model.preferencesIssue != .loadFailed,
                        onToggleFavorite: { model.toggleFavorite(prepared.channel.id) },
                        isExpanded: preview.isExpanded,
                        returnToGuide: {
                            guard playback.ownsPlayerPresentation(presentationID) else { return }
                            returnToGuide()
                        },
                        playPauseRequest: playPauseRequest,
                        playbackStarted: { playback.confirmWatching(prepared.id) },
                        reportingID: prepared.id,
                        playbackUpdate: { playback.report($0, for: prepared.id) },
                        playbackFailed: { playback.playbackFailed(prepared.id) },
                        preparingChannelName: playback.preparation.preparingChannelID.flatMap {
                            model.channel(id: $0)?.name
                        }
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
        .overlay(alignment: .topTrailing) {
            if let id = playback.pendingWatchChannelID, !preview.isExpanded || playback.preparation.current == nil {
                PrototypeWatchPreparationStatus(
                    channelName: model.channel(id: id)?.name ?? "",
                    cancel: playback.cancelWatch
                )
            }
        }
        #if os(tvOS)
        .onPlayPauseCommand {
            if isActive && !preview.isExpanded { playPauseRequest &+= 1 }
        }
        #endif
    }

    private var presentedContent: some View {
        playerAndGuideSurface
        .sheet(item: $sheet, onDismiss: {
            if pendingServerConnection {
                pendingServerConnection = false
                connectServer?()
            } else if let id = pendingTuneID {
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
                tune: { pendingTuneID = $0 },
                sourceManagement: sources == nil ? nil : { AnyView(sourceSetupDestination($0)) }
            )
            .environment(\.themePalette, palette)
            .tint(palette.accent)
        }
        .alert("Can't play this channel", isPresented: Binding(
            get: { isActive && playback.watchFailure != nil },
            set: { if !$0 { playback.dismissFailure() } }
        ), presenting: playback.watchFailure) { failure in
            if failure.currentToStop != nil {
                Button("Stop current channel and retry", role: .destructive) {
                    playback.stopCurrentAndRetry(failure)
                }
            }
            Button("OK", role: .cancel) { playback.dismissFailure() }
        } message: { failure in
            Text(failure.message)
        }
        .alert("Live TV preferences unavailable", isPresented: Binding(
            get: { isActive && model.preferencesIssue != nil },
            set: { if !$0 { model.dismissPreferencesIssue() } }
        )) {
            Button("Retry") { model.retryPreferences() }
            Button("Not now", role: .cancel) { model.dismissPreferencesIssue() }
        } message: {
            if model.preferencesIssue == .loadFailed {
                Text("Your Favorites, recently watched channels, and hidden channels could not be loaded. Retry before making changes. Your saved preferences have not been replaced.")
            } else {
                Text("The change to your Favorites, recently watched channels, or hidden channels could not be saved. Retry to keep it across sessions.")
            }
        }
    }

    private var loadingContent: some View {
        presentedContent
        .task(id: isActive ? reloadRequest : -1) {
            guard isActive, loadedRequest != reloadRequest else { return }
            if let sources {
                sources.reload()
                guard sources.hasLoaded, applySourceConfiguration() else {
                    playback.validateAuthorization()
                    return
                }
            }
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
            if await playback.preparePreview(request) {
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
    }

    private var playbackObservedContent: some View {
        loadingContent
        .onChange(of: playback.preparation.current?.id) { _, _ in
            playback.synchronizePlayerState()
        }
        .onChange(of: playback.preparation.isPreparing) { _, _ in
            playback.synchronizePlayerState()
        }
        .onChange(of: playback.canAutoPreview) { _, _ in
            updatePreviewAvailability()
        }
        .onChange(of: playback.acceptedWatchID) { _, _ in
            handleWatchAcceptance()
        }
        .onChange(of: model.channels) { _, _ in
            playback.validateAuthorization()
        }
        .onChange(of: imports.serverChannelReferences) { _, _ in
            playback.validateAuthorization()
        }
        .onChange(of: sources?.mutationRevision) { _, _ in
            guard applySourceConfiguration() else { return }
            loadedRequest = nil
            reloadRequest &+= 1
        }
        .onChange(of: serverAuthorizationID) { _, _ in
            playback.validateAuthorization()
            do {
                try imports.setServerProviderResolver(serverProviderResolver, into: model)
                playback.validateAuthorization()
                sourceApplicationFailed = false
                loadedRequest = nil
                reloadRequest &+= 1
            } catch {
                sourceApplicationFailed = true
                playback.stop()
            }
        }
    }

    private var browsingObservedContent: some View {
        playbackObservedContent
        .onChange(of: selectedChannelID) { _, id in playback.focus(id) }
        .onChange(of: model.sort) { _, _ in persistViewFilters() }
        .onChange(of: model.favoritesOnly) { _, _ in persistViewFilters() }
        .onChange(of: model.guideOnly) { _, _ in persistViewFilters() }
        .onChange(of: controlsActive) { _, _ in updatePreviewAvailability() }
        .onChange(of: guideHasFocus) { _, _ in updatePreviewAvailability() }
        .onChange(of: sheet?.id) { _, _ in
            if sheet != nil { playback.cancelWatch() }
            updatePreviewAvailability()
            focusInitialChannelIfNeeded()
        }
        .onChange(of: model.guideChannels.first?.id, initial: true) { _, _ in
            focusInitialChannelIfNeeded()
        }
    }

    private var lifecycleContent: some View {
        browsingObservedContent
        .onChange(of: scenePhase, initial: true) { _, _ in
            updatePlaybackAvailability()
        }
        .onChange(of: isProfileAuthorized(), initial: true) { _, _ in
            updatePlaybackAvailability()
        }
        .onChange(of: isActive, initial: true) { _, active in
            if !active {
                loadedRequest = nil
                pendingServerConnection = false
                pendingTuneID = nil
                sheet = nil
                playback.stop()
            }
            if active {
                model.reloadPreferences()
                applyViewSettings()
            }
            updatePlaybackAvailability()
            if active { playback.focus(selectedChannelID) }
            focusInitialChannelIfNeeded()
        }
        .onChange(of: hidesAppNavigation, initial: true) { _, hidesChrome in
            onExpandedChange(hidesChrome)
        }
        .onAppear(perform: updatePlaybackAvailability)
        .onDisappear(perform: handleDisappearance)
    }

    private func handleDisappearance() {
        let preservesFullscreen = isActive && isProfileAuthorized() && usesNativeFullscreen && preview.isExpanded
        guard !preservesFullscreen else { return }
        playback.setActive(false)
        onExpandedChange(false)
    }

    @ViewBuilder
    private func guideContent(_ layout: PrototypePreviewLayout, canvasWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let sources, !sources.hasLoaded || sourceApplicationFailed {
                PrototypeGuidePlacement(frame: layout.contentFrame, canvasWidth: canvasWidth) {
                    LiveTVSourceLoadState(
                        issue: sources.loadIssue,
                        applicationFailed: sourceApplicationFailed,
                        retry: { loadedRequest = nil; reloadRequest &+= 1 }
                    )
                }
            } else if let sources,
                      sources.configuration.playlists.isEmpty && sources.configuration.servers.isEmpty {
                PrototypeGuidePlacement(frame: layout.contentFrame, canvasWidth: canvasWidth) {
                    LiveTVSetupWelcome(
                        addPlaylist: { sheet = .addPlaylist },
                        useServer: { sheet = .serverSetup },
                        issue: sources.mutationIssue?.message
                    )
                }
            } else if let sources,
                      !sources.configuration.playlists.contains(where: \.isEnabled),
                      !sources.configuration.servers.contains(where: \.isEnabled) {
                PrototypeGuidePlacement(frame: layout.contentFrame, canvasWidth: canvasWidth) {
                    ContentUnavailableView {
                        Label("Your sources are paused", systemImage: "pause.circle")
                    } description: {
                        Text("Enable a source to bring its channels back to the guide.")
                    } actions: {
                        Button("Manage sources") { sheet = .sources }
                    }
                }
            } else {
                catalogGuideContent(layout, canvasWidth: canvasWidth)
            }
        }
    }

    @ViewBuilder
    private func catalogGuideContent(_ layout: PrototypePreviewLayout, canvasWidth: CGFloat) -> some View {
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

    @ViewBuilder
    private func sourceSetupDestination(_ destination: PrototypeSheet) -> some View {
        if let sources {
            switch destination {
            case .addPlaylist:
                LiveTVSourceAccessGate(model: sources) {
                    LiveTVPlaylistEditor { input in
                        try sources.savePlaylist(input: input)
                        didConfigurePlaylist()
                    }
                }
            case .serverSetup:
                LiveTVSourceAccessGate(model: sources) {
                    LiveTVServerSetupView(
                        sources: sources, choices: serverChoices,
                        resolver: serverProviderResolver,
                        connectServer: connectServer == nil ? nil : requestServerConnection
                    )
                }
            default:
                LiveTVSourcesView(
                    model: sources, imports: imports, refresh: { reloadRequest &+= 1 },
                    serverChoices: serverChoices, serverProviderResolver: serverProviderResolver,
                    connectServer: connectServer == nil ? nil : requestServerConnection,
                    sourceFilterID: model.configuredSourceID,
                    browseSource: { sourceID in
                        model.source = nil
                        model.configuredSourceID = sourceID
                        topRequest &+= 1
                        sheet = nil
                    },
                    didConfigurePlaylist: didConfigurePlaylist
                )
            }

        }
    }

    private func requestServerConnection() {
        pendingTuneID = nil
        pendingServerConnection = true
        sheet = nil
    }

    @discardableResult
    private func applySourceConfiguration() -> Bool {
        guard let sources, sources.hasLoaded else { return false }
        do {
            try imports.applyConfiguration(sources.configuration, into: model)
            playback.validateAuthorization()
            sourceApplicationFailed = false
            return true
        } catch {
            sourceApplicationFailed = true
            playback.stop()
            return false
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
            if heroIsGuideOnly && !isSearching {
                Text("Guide only · This server's Live TV playback mode isn't supported yet.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
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
            isPresented: isActive && !preview.isExpanded && sheet == nil,
            isRestoringFocus: preview.isRestoringGuideFocus,
            restoresPlaybackFocus: preview.restoresPlaybackFocus, watchOrigin: preview.watchOrigin,
            focusRestored: {
                preview.completeGuideFocusRestore($0, focusedChannelID: selectedChannelID)
            },
            tune: { tune($0.channelID, origin: $0) },
            details: { sheet = .program($0) }, openControls: openSearch,
            openSources: { sheet = .sources }, openGuideTime: { sheet = .guideTime },
            openToolbar: {
                if playback.pendingWatchChannelID != nil {
                    playback.cancelWatch()
                    return
                }
                guard !preview.isRestoringGuideFocus else { return }
                if isSearching {
                    closeSearch()
                    return
                }
                controlsActive = true
                toolbarFocusRequest &+= 1
            },
            isLoading: model.channels.isEmpty && (imports.catalogPhase == .idle || imports.catalogPhase == .loading),
            loadFailed: imports.catalogPhase == .failed,
            reload: { reloadRequest += 1 },
            hideChannel: hideChannel
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
           model.guideChannels.first != nil || imports.catalogPhase == .idle || imports.catalogPhase == .loading {
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

    private var heroIsGuideOnly: Bool {
        guard let channel = heroChannel, let reference = imports.serverChannelReferences[channel.id] else {
            return false
        }
        return imports.serverSources.first(where: { $0.id == reference.sourceID })?
            .availability?.status == .unsupportedPlaybackMode
    }

    private func updatePreviewAvailability() {
        #if os(tvOS)
        let canFollowFocus = guideHasFocus
        #else
        let canFollowFocus = true
        #endif
        preview.setBrowsingActive(
            isActive && playback.canAutoPreview && scenePhase == .active
                && sheet == nil && !controlsActive && canFollowFocus
        )
    }

    private func updatePlaybackAvailability() {
        let active = isActive && scenePhase != .background && isProfileAuthorized()
        playback.setActive(active)
        playback.setInteractionActive(active && scenePhase == .active)
        updatePreviewAvailability()
        if active && scenePhase == .active { playback.focus(selectedChannelID) }
    }

    private func returnToGuide() {
        playback.cancelWatch()
        model.synchronizeClock()
        controlsActive = false
        #if os(tvOS)
        preview.returnToGuide()
        #else
        preview.returnToGuide(restoresFocus: false)
        #endif
    }

    private func openSearch() {
        playback.cancelWatch()
        guard !isSearching else {
            searchFocusRequest &+= 1
            return
        }
        #if os(tvOS)
        // Exclude both native and custom shell navigation before UIKit presents
        // its keyboard and claims focus.
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
        playback.cancelWatch()
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

    private func hideChannel(_ channel: LiveTVPrototypeChannel, from row: LiveTVGuideRowID) {
        let replacement = LiveTVGuideFocusTarget.rowAfterHiding(row, in: model.guideChannels)
        guard model.hideChannel(channel) else { return }
        selectedRowID = replacement
        selectedChannelID = replacement?.channelID
        focusedProgram = nil
        if replacement != nil {
            enterGuide()
        } else {
            controlsActive = true
            if preview.followsFocus && !preview.isHoldingWatchedChannel { playback.stop() }
            toolbarFocusRequest &+= 1
        }
    }

    private func applyViewSettings() {
        guard let settings = viewSettingsStore?.load() else { return }
        model.sort = settings.sortByName ? .name : .channelNumber
        model.favoritesOnly = settings.favoritesOnly
        model.guideOnly = settings.guideOnly
        preview.setKeepWatchingWhileBrowsing(settings.keepWatchingWhileBrowsing)
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
        guard isActive, scenePhase == .active, isProfileAuthorized() else {
            HandoffDiagnostics.emit("LIVE_TV event=watchIgnored reason=inactiveDestination")
            return
        }
        if !preview.isExpanded {
            channelSequence = LiveTVChannelSequence(channels: model.guideChannels.map(\.channel))
        }
        let selectedOrigin = !preview.isExpanded && selectedRowID?.channelID == id ? selectedRowID : nil
        playback.watch(id, origin: origin ?? selectedOrigin)
    }

    private func handleWatchAcceptance() {
        guard isActive, preview.isExpanded, let current = playback.preparation.current else { return }
        #if os(tvOS)
        onExpandedChange(true)
        #endif
        selectedChannelID = current.channel.id
        selectedRowID = preview.watchOrigin
        focusedProgram = nil
        controlsActive = false
    }

    private func changeChannel(by offset: Int) {
        guard let id = channelSequence.neighbor(
            of: playback.pendingWatchChannelID ?? playback.preparation.current?.channel.id,
            offset: offset, visibleChannels: model.visibleChannels
        ) else { return }
        tune(id)
    }
}

private struct PrototypeWatchPreparationStatus: View {
    let channelName: String
    let cancel: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack {
            ProgressView()
            Text("Opening \(channelName)")
            Button("Cancel", role: .cancel, action: cancel)
        }
        .padding()
        .background(palette.backgroundBase, in: RoundedRectangle(cornerRadius: 12))
        .padding()
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
