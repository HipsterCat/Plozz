import CoreModels
import FeaturePlayback
import SwiftUI
import UIKit
@testable import FeatureLiveTV
@testable import FeatureLiveTVCore

private enum MultiviewFixtureCatalog {
    static let channels = (1...4).map {
        LiveTVPrototypeChannel(
            id: "sports-\($0)", number: $0, name: "Sports \($0)", category: "Sports",
            symbol: "tv", accent: $0, source: .iptv, tagline: "",
            streamURL: URL(string: "https://example.invalid/sports-\($0).m3u8")!
        )
    }
}

@MainActor
private final class MultiviewFixtureState {
    let primary = LiveTVPlaybackPreparation()
    let output = LiveChannelOutputGroup()
    lazy var coordinator = LiveTVMultiviewCoordinator(
        primary: primary, makePreparation: { LiveTVPlaybackPreparation() },
        reference: { _ in nil }, authorizes: { _, _ in true }, recordWatched: { _ in }
    )
    var engines: [MultiviewFixtureEngine] = []

    let channels = MultiviewFixtureCatalog.channels

    func makeEngine() -> MultiviewFixtureEngine {
        let engine = MultiviewFixtureEngine(number: engines.count + 1)
        engines.append(engine)
        return engine
    }

    var metrics: String {
        "Engines \(engines.count) loads \(engines.reduce(0) { $0 + $1.loads }) " +
            "stops \(engines.reduce(0) { $0 + $1.stops }) " +
            "audible \(engines.filter { $0.audible && $0.status != .idle }.count)"
    }
}

struct MultiviewFixture: View {
    @State private var state = MultiviewFixtureState()
    @State private var isFavorite = false

    var body: some View {
        GeometryReader { geometry in
            let coordinator = state.coordinator
            ZStack {
                Color.black.ignoresSafeArea()
                ForEach(coordinator.panes) { pane in
                    if let prepared = pane.preparation.current {
                        let frame = coordinator.isEnabled ? LiveTVMultiviewGeometry.frame(
                            for: pane.id, panes: coordinator.panes.map(\.id),
                            primary: coordinator.primaryPaneID, layout: coordinator.layout,
                            corner: coordinator.corner, insetSize: coordinator.insetSize,
                            expanded: coordinator.expandedPaneID, size: geometry.size
                        ) : CGRect(origin: .zero, size: geometry.size)
                        LiveChannelPlayerView(
                            channelID: prepared.channel.id, title: prepared.channel.name,
                            input: prepared.input, logoURL: nil,
                            makeEngine: { state.makeEngine() },
                            onPreviousChannel: {}, onNextChannel: {},
                            isFavorite: isFavorite,
                            canToggleFavorite: ProcessInfo.processInfo.arguments.contains("--visual-focus-fixture"),
                            onToggleFavorite: { isFavorite.toggle() },
                            isExpanded: !coordinator.isEnabled,
                            usesNativeFullscreen: !coordinator.isEnabled,
                            onReturnToGuide: {},
                            reportingID: prepared.id,
                            onMultiview: { coordinator.begin() },
                            outputGroup: state.output, outputID: pane.id,
                            isAudible: pane.id == coordinator.audiblePaneID,
                            countsAsWatching: coordinator.isEnabled,
                            isMultiview: coordinator.isEnabled
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(!coordinator.isEnabled)
                        .accessibilityHidden(coordinator.isEnabled)
                        .opacity(coordinator.expandedPaneID == nil || coordinator.expandedPaneID == pane.id ? 1 : 0)
                    }
                }
                if coordinator.isEnabled {
                    LiveTVMultiviewOverlay(
                        coordinator: coordinator, channels: state.channels,
                        favoriteIDs: ["sports-2"],
                        exit: { _ = coordinator.exit() },
                        returnToGuide: { _ = coordinator.exit() }
                    )
                }
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    VStack {
                        Spacer()
                        Text(verbatim: state.metrics)
                            .font(.caption2)
                            .accessibilityIdentifier("multiview-fixture-metrics")
                    }
                    .padding(.bottom, 8)
                }
                .allowsHitTesting(false)
            }
        }
        .task {
            _ = await state.primary.prepare(
                state.channels[0], isAuthorized: { true }, accept: { true }
            )
        }
        .background { MultiviewFocusDiagnostics() }
    }
}

struct LiveTVRootFixture: View {
    @State private var isActive = true
    @State private var hostRevision = 0
    @State private var state = MultiviewFixtureState()
    @State private var profiles = ProfilesModel(store: SourceSmokeProfiles())
    @State private var sources: SourceSmokeStore
    @State private var imports: LiveTVPrototypeImportModel

    init() {
        let configuration = LiveTVSourcesConfiguration(playlists: [
            LiveTVPlaylistSource(
                id: "fixture", name: "Fixture sports",
                playlistURL: URL(string: "https://example.invalid/channels.m3u")!,
                guideURLs: [URL(string: "https://example.invalid/guide.xml")!]
            )
        ])
        _sources = State(initialValue: SourceSmokeStore(configuration: configuration))
        _imports = State(initialValue: LiveTVPrototypeImportModel(
            configuration: configuration, loader: LiveTVRootFixtureLoader()
        ))
    }

    var body: some View {
        NavigationStack {
            LiveTVPrototypeView(
                isActive: isActive,
                usesNativeFullscreen: true,
                preferencesStore: SourceSmokePreferences(),
                viewSettingsStore: LiveTVRootFixtureSettings(),
                sourceStore: sources,
                serverAuthorizationID: "fixture-\(hostRevision)",
                importModel: imports,
                profileID: profiles.activeProfileID,
                preferencesNamespace: profiles.activeNamespace,
                sourceApprovalContext: { [profiles] in LiveTVSourceApprovalContext(profiles: profiles) }
            ) { playback in
                LiveChannelPlayerView(
                    channelID: playback.channel.id, title: playback.channel.name,
                    input: playback.input, logoURL: nil,
                    makeEngine: { state.makeEngine() },
                    onPreviousChannel: playback.previousChannel, onNextChannel: playback.nextChannel,
                    isFavorite: playback.isFavorite, canToggleFavorite: playback.canToggleFavorite,
                    onToggleFavorite: playback.onToggleFavorite,
                    isExpanded: playback.isExpanded, usesNativeFullscreen: !playback.isMultiview,
                    isActive: playback.isPlaybackActive, onReturnToGuide: playback.returnToGuide,
                    playPauseRequest: playback.playPauseRequest, onPlaybackStarted: playback.playbackStarted,
                    reportingID: playback.reportingID, onPlaybackUpdate: playback.playbackUpdate,
                    onPlaybackFailed: playback.playbackFailed,
                    preparingChannelName: playback.preparingChannelName,
                    onMultiview: playback.canOpenMultiview ? playback.openMultiview : nil,
                    outputGroup: state.output, outputID: playback.paneID, isAudible: playback.isAudible,
                    countsAsWatching: playback.countsAsWatching, isMultiview: playback.isMultiview,
                    isAuthorized: playback.isAuthorized
                )
            }
        }
        .environment(profiles)
        .overlay(alignment: .topTrailing) {
            if isActive {
                HStack {
                    Button("Refresh host") { hostRevision += 1 }
                        .accessibilityIdentifier("live-root-fixture-refresh")
                        .accessibilityValue(String(hostRevision))
                    Button("Leave Live TV") { isActive = false }
                        .accessibilityIdentifier("live-root-fixture-leave")
                }
                .padding()
            }
        }
        .overlay(alignment: .bottom) {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                Text(verbatim: state.metrics)
                    .font(.caption2)
                    .accessibilityIdentifier("multiview-fixture-metrics")
            }
            .allowsHitTesting(false)
        }
        .background { MultiviewFocusDiagnostics() }
    }
}

private struct MultiviewFocusDiagnostics: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}

    static func dismantleUIView(_ view: Probe, coordinator: ()) {
        view.stop()
    }

    final class Probe: UIView {
        private var timer: Timer?
        private let report = UILabel()

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            report.accessibilityIdentifier = "multiview-fixture-focus-diagnostics"
            report.font = .systemFont(ofSize: 10)
            report.textColor = .white
            report.isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            stop()
            guard let window else { return }
            report.frame = CGRect(x: 80, y: window.bounds.height - 32, width: window.bounds.width - 160, height: 20)
            window.addSubview(report)
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            sample()
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            report.removeFromSuperview()
        }

        private func sample() {
            guard let window else { return }
            let focused = UIFocusSystem.focusSystem(for: window)?.focusedItem
            var pieces = [
                "keyWindow=\(window.isKeyWindow)",
                "focused=\(focused.map { String(describing: type(of: $0)) } ?? "nil")"
            ]
            if let focused {
                pieces.append("itemFrame=\(focused.frame)")
                var windowFrame = (focused as? UIView).map { $0.convert($0.bounds, to: window) }
                var environment = focused.parentFocusEnvironment
                for _ in 0..<20 {
                    guard let current = environment else { break }
                    pieces.append("focusParent=\(type(of: current))")
                    if let view = current as? UIView {
                        pieces.append("parentFrame=\(view.convert(view.bounds, to: window))")
                        if windowFrame == nil {
                            windowFrame = view.convert(focused.frame, to: window)
                        }
                    }
                    environment = current.parentFocusEnvironment
                }
                if let windowFrame {
                    pieces.append("focusWindowFrame=\(NSCoder.string(for: windowFrame))")
                }
            }
            if let view = focused as? UIView {
                pieces.append("focusID=\(view.accessibilityIdentifier ?? "-")")
                pieces.append("focusFrame=\(view.convert(view.bounds, to: window))")
            }
            func visit(_ controller: UIViewController) {
                pieces.append(
                    "controller=\(type(of: controller)):alpha=\(controller.viewIfLoaded?.alpha ?? -1)" +
                    ":interaction=\(controller.viewIfLoaded?.isUserInteractionEnabled ?? false)"
                )
                if let search = controller as? UISearchController {
                    pieces.append("searchActive=\(search.isActive)")
                    var view: UIView? = search.view
                    while let current = view {
                        pieces.append(
                            "ancestor=\(type(of: current)):hidden=\(current.isHidden)" +
                            ":alpha=\(current.alpha):interaction=\(current.isUserInteractionEnabled)" +
                            ":frame=\(current.convert(current.bounds, to: window))"
                        )
                        view = current.superview
                    }
                }
                for child in controller.children { visit(child) }
                if let presented = controller.presentedViewController { visit(presented) }
            }
            if let root = window.rootViewController { visit(root) }
            let description = pieces.joined(separator: " | ")
            if report.accessibilityValue != description {
                report.text = "Native focus diagnostics"
                report.accessibilityValue = description
                NSLog("MultiviewFocusDiagnostics %@", description)
            }
        }
    }
}

private struct LiveTVRootFixtureSettings: LiveTVViewSettingsStoring {
    func load() -> LiveTVViewSettings { .init(autoPreview: false) }
    func save(_ settings: LiveTVViewSettings) {}
}

private struct LiveTVRootFixtureLoader: LiveTVSourceLoading {
    func loadPlaylist(from url: URL) async throws -> LiveTVPlaylistImport {
        let channels = MultiviewFixtureCatalog.channels
        return LiveTVPlaylistImport(channels: channels, entryCount: channels.count, skippedEntryCount: 0)
    }

    func loadGuide(
        from url: URL, channels: [LiveTVPrototypeChannel], now: Date
    ) async throws -> LiveTVGuideImport {
        let start = now.addingTimeInterval(-300)
        let end = now.addingTimeInterval(3_600)
        return LiveTVGuideImport(
            programs: channels.map {
                LiveTVPrototypeProgram(
                    id: "final-\($0.id)", channelID: $0.id, title: "Championship final",
                    subtitle: "Live coverage", start: start, end: end
                )
            },
            matchedChannelCount: channels.count, guideChannelCount: channels.count,
            programCount: channels.count, coverageStart: start, coverageEnd: end
        )
    }
}

@MainActor
private final class MultiviewFixtureEngine: LiveChannelEngine {
    let number: Int
    private let output = UIView()
    private let label = UILabel()
    var status: VideoEngineStatus = .ready
    var isPaused = false
    var currentTime: TimeInterval { 0 }
    var duration: TimeInterval { 0 }
    var furthestObservedPosition: TimeInterval { 0 }
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    var onProgress: (@MainActor () -> Void)?
    var onFailure: (@MainActor (AppError) -> Void)?
    var onEnded: (@MainActor () -> Void)?
    var onTracksChanged: (@MainActor () -> Void)?
    var onProbedSourceFactsChanged: (@MainActor (EngineProbedSourceFacts) -> Void)?
    var onSubtitleCues: (@MainActor ([SubtitleCue]) -> Void)?
    var onSecondarySubtitleCues: (@MainActor ([SubtitleCue]) -> Void)?
    var onLiveSourceReset: (@MainActor () -> Void)?
    var supportsConcurrentPlayback: Bool { true }
    var loads = 0
    var stops = 0
    var audible = false
    var liveSnapshot = LiveChannelEngineSnapshot(
        phase: .playing, firstFrameReady: true, position: 100,
        bufferedPosition: 110, seekableRange: 90...110,
        behindLiveSeconds: 0, route: .nativeHLS
    )

    init(number: Int) {
        self.number = number
        output.backgroundColor = number == 1 ? .systemBlue : .systemTeal
        output.accessibilityIdentifier = "multiview-fixture-video-\(number)"
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .headline)
        label.accessibilityIdentifier = "multiview-fixture-player-\(number)"
        label.translatesAutoresizingMaskIntoConstraints = false
        output.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: output.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: output.centerYAnchor)
        ])
    }

    func configureLiveOutput(_ policy: LiveChannelOutputPolicy) { audible = policy.isAudible }
    func loadLive(url: URL, httpHeaders: [String: String]) async {
        loads += 1
        status = .ready
        label.text = "Engine \(number) loads \(loads)"
    }
    func load(request: PlaybackRequest, startPosition: TimeInterval) async {
        preconditionFailure("The live fixture must not load VOD")
    }
    func play() { isPaused = false; liveSnapshot.phase = .playing }
    func pause() { isPaused = true; liveSnapshot.phase = .paused }
    func stop() { stops += 1; status = .idle }
    func seek(to seconds: TimeInterval) async {}
    func seekToLiveEdge() async {}
    func selectAudioTrack(_ track: MediaTrack?) {}
    func selectSubtitleTrack(_ track: MediaTrack?) {}
    func makeVideoOutputView() -> UIView { output }
}
