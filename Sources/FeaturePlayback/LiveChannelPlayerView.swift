#if DEBUG && canImport(SwiftUI) && canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import CoreModels
import CoreUI
import Observation
import SwiftUI
import UIKit

/// Debug-only, provider-free playback host for public IPTV HLS channels.
///
/// The host deliberately bypasses `PlayerViewModel`: live channels have no
/// provider playback session, watch history, resume point, duration, or
/// scrobbling lifecycle. Video still runs through Plozz's production
/// AetherEngine adapter and its existing video surface.
public struct LiveChannelPlayerView: View {
    private let channelID: String
    private let title: String
    private let streamURL: URL
    private let httpHeaders: [String: String]
    private let logoURL: URL?
    private let logoNeedsDarkBackground: Bool
    private let makeEngine: @MainActor () throws -> any LiveChannelEngine
    private let onPreviousChannel: () -> Void
    private let onNextChannel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: LiveChannelPlayerModel?
    @State private var engineInitializationFailed = false
    @State private var controlsVisible = true
    @State private var autoHideRevision = 0
    @FocusState private var focusedControl: LiveChannelControl?

    public init(
        channelID: String,
        title: String,
        streamURL: URL,
        logoURL: URL?,
        logoNeedsDarkBackground: Bool = false,
        httpHeaders: [String: String] = [:],
        makeEngine: @escaping @MainActor () throws -> any LiveChannelEngine,
        onPreviousChannel: @escaping () -> Void,
        onNextChannel: @escaping () -> Void
    ) {
        self.channelID = channelID
        self.title = title
        self.streamURL = streamURL
        self.httpHeaders = httpHeaders
        self.logoURL = logoURL
        self.logoNeedsDarkBackground = logoNeedsDarkBackground
        self.makeEngine = makeEngine
        self.onPreviousChannel = onPreviousChannel
        self.onNextChannel = onNextChannel
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let model {
                VideoSurfaceContainer(engine: model.engine)
                    .ignoresSafeArea()

                LiveChannelRevealSurface(
                    isEnabled: !controlsVisible,
                    focus: $focusedControl,
                    onReveal: revealControls
                )

                if controlsVisible, model.interruption == nil {
                    LiveChannelOverlay(
                        title: title,
                        logoURL: logoURL,
                        logoNeedsDarkBackground: logoNeedsDarkBackground,
                        phase: model.phase,
                        isAtLiveEdge: model.isAtLiveEdge,
                        canPause: model.canPause,
                        canGoLive: model.canGoLive,
                        focus: $focusedControl,
                        onClose: dismissPlayer,
                        onPrevious: channelPrevious,
                        onPlayPause: togglePlayPause,
                        onGoLive: goLive,
                        onNext: channelNext
                    )
                    .onAppear { focusAfterPresentation(.close) }
                    .transition(.opacity)
                }

                if let interruption = model.interruption {
                    LiveChannelInterruptionView(
                        interruption: interruption,
                        canRetry: model.canRetry,
                        focus: $focusedControl,
                        onRetry: retry,
                        onClose: dismissPlayer
                    )
                } else if model.showsActivityIndicator {
                    LiveChannelActivityView(phase: model.phase)
                        .allowsHitTesting(false)
                }
            } else if engineInitializationFailed {
                LiveChannelInterruptionView(
                    interruption: .failure(.engine(.unknown("engine initialization")), retryLimitReached: false),
                    canRetry: false,
                    focus: $focusedControl,
                    onRetry: {},
                    onClose: dismissPlayer
                )
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .animation(.easeOut(duration: 0.2), value: controlsVisible)
        #if os(tvOS)
        .onExitCommand(perform: dismissPlayer)
        .onPlayPauseCommand(perform: togglePlayPause)
        #endif
        .onChange(of: focusedControl) { _, newValue in
            guard let newValue, newValue != .surface else { return }
            noteInteraction()
        }
        .onChange(of: model?.phase) { _, phase in
            autoHideRevision &+= 1
            guard let phase else { return }
            if phase != .playing {
                controlsVisible = true
            }
            if phase.isInterrupted {
                focusInterruptionAction()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            model?.handleScenePhase(phase)
        }
        .task(id: channelID) {
            let engine: any LiveChannelEngine
            do {
                engine = try makeEngine()
            } catch {
                LiveChannelDiagnostics().event(.initializationFailure, attempt: 0)
                engineInitializationFailed = true
                focusAfterPresentation(.close)
                return
            }
            let playerModel = LiveChannelPlayerModel(
                engine: engine, streamURL: streamURL, httpHeaders: httpHeaders
            )
            model = playerModel
            playerModel.handleScenePhase(scenePhase)
            await playerModel.start()
        }
        .task(id: autoHideRevision) {
            guard controlsVisible, model?.phase == .playing else { return }
            try? await Task.sleep(for: .seconds(ControlsAutoHidePolicy.minSinceInput))
            guard !Task.isCancelled,
                  controlsVisible,
                  model?.phase == .playing else {
                return
            }
            hideControls()
        }
        .onDisappear {
            model?.stop()
            model = nil
        }
    }

    private func noteInteraction() {
        controlsVisible = true
        autoHideRevision &+= 1
    }

    private func revealControls() {
        noteInteraction()
        focusAfterPresentation(.next)
    }

    private func hideControls() {
        guard model?.phase == .playing else { return }
        focusedControl = nil
        controlsVisible = false
        focusAfterPresentation(.surface)
    }

    private func focusAfterPresentation(_ control: LiveChannelControl) {
        #if os(tvOS)
        Task { @MainActor in
            await Task.yield()
            focusedControl = control
        }
        #endif
    }

    private func focusInterruptionAction() {
        focusAfterPresentation(model?.canRetry == true ? .retry : .close)
    }

    private func togglePlayPause() {
        guard let model else { return }
        noteInteraction()
        model.togglePlayPause()
    }

    private func goLive() {
        guard let model else { return }
        noteInteraction()
        Task { await model.goLive() }
    }

    private func retry() {
        guard let model, model.canRetry else { return }
        noteInteraction()
        Task { await model.retry() }
    }

    private func channelPrevious() {
        noteInteraction()
        onPreviousChannel()
    }

    private func channelNext() {
        noteInteraction()
        onNextChannel()
    }

    private func dismissPlayer() {
        model?.stop()
        dismiss()
    }
}

private enum LiveChannelControl: Hashable {
    case surface
    case close
    case previous
    case playPause
    case goLive
    case next
    case retry
}

private struct LiveChannelRevealSurface: View {
    let isEnabled: Bool
    @FocusState.Binding var focus: LiveChannelControl?
    let onReveal: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(isEnabled)
            .onTapGesture(perform: onReveal)
            #if os(tvOS)
            .focusable(isEnabled)
            .focused($focus, equals: .surface)
            .onMoveCommand { _ in onReveal() }
            #endif
    }
}

private struct LiveChannelOverlay: View {
    let title: String
    let logoURL: URL?
    let logoNeedsDarkBackground: Bool
    let phase: LiveChannelPlaybackPhase
    let isAtLiveEdge: Bool
    let canPause: Bool
    let canGoLive: Bool
    @FocusState.Binding var focus: LiveChannelControl?
    let onClose: () -> Void
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onGoLive: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            LiveChannelHeader(
                title: title,
                logoURL: logoURL,
                logoNeedsDarkBackground: logoNeedsDarkBackground,
                status: phase.statusLabel(isAtLiveEdge: isAtLiveEdge),
                statusColor: phase.statusColor(isAtLiveEdge: isAtLiveEdge),
                focus: $focus,
                onClose: onClose
            )
            Spacer()
            LiveChannelTransport(
                isPaused: phase == .paused,
                canPause: canPause,
                canGoLive: canGoLive,
                focus: $focus,
                onPrevious: onPrevious,
                onPlayPause: onPlayPause,
                onGoLive: onGoLive,
                onNext: onNext
            )
        }
        #if os(tvOS)
        .padding(.horizontal, 48)
        #else
        .padding(.horizontal, 16)
        #endif
        .padding(.vertical, 32)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.72), location: 0),
                    .init(color: .clear, location: 0.36),
                    .init(color: .clear, location: 0.58),
                    .init(color: .black.opacity(0.78), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

private struct LiveChannelHeader: View {
    let title: String
    let logoURL: URL?
    let logoNeedsDarkBackground: Bool
    let status: LocalizedStringResource
    let statusColor: Color
    @FocusState.Binding var focus: LiveChannelControl?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            LiveChannelLogo(
                title: title,
                logoURL: logoURL,
                needsDarkBackground: logoNeedsDarkBackground
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text(status)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
            }

            Spacer()

            Button(action: onClose) {
                Label("Close", systemImage: "xmark")
            }
            #if os(iOS)
            .labelStyle(.iconOnly)
            #endif
            .accessibilityIdentifier("live-channel-close")
            .focused($focus, equals: .close)
            .playerGlassButton(prominent: false)
        }
        .foregroundStyle(.white)
    }
}

private struct LiveChannelLogo: View {
    let title: String
    let logoURL: URL?
    let needsDarkBackground: Bool

    var body: some View {
        Group {
            if let logoURL {
                FallbackAsyncImage(
                    references: [.remote(logoURL)],
                    variant: .serviceLogo
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    LiveChannelLogoPlaceholder(
                        title: title,
                        usesDarkBackground: needsDarkBackground
                    )
                }
            } else {
                LiveChannelLogoPlaceholder(
                    title: title,
                    usesDarkBackground: needsDarkBackground
                )
            }
        }
        #if os(tvOS)
        .frame(width: 92, height: 58)
        #else
        .frame(width: 60, height: 38)
        #endif
        .padding(8)
        .background(
            needsDarkBackground ? Color.black.opacity(0.82) : Color.white.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityHidden(true)
    }
}

private struct LiveChannelLogoPlaceholder: View {
    let title: String
    let usesDarkBackground: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(
                    usesDarkBackground
                        ? Color.white.opacity(0.12)
                        : Color.black.opacity(0.08)
                )
            Text(String(title.prefix(1)).uppercased())
                .font(.title2.bold())
                .foregroundStyle(
                    usesDarkBackground
                        ? Color.white.opacity(0.85)
                        : Color.black.opacity(0.78)
                )
        }
    }
}

private struct LiveChannelTransport: View {
    let isPaused: Bool
    let canPause: Bool
    let canGoLive: Bool
    @FocusState.Binding var focus: LiveChannelControl?
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onGoLive: () -> Void
    let onNext: () -> Void

    var body: some View {
        transportButtons
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.black.opacity(0.58), in: Capsule())
    }

    @ViewBuilder
    private var transportButtons: some View {
        #if os(tvOS)
        // Only one set of focus targets. Glass already highlights focus;
        // changing its style on focus recreates the currently focused button.
        fullWidthButtons
        #else
        ViewThatFits(in: .horizontal) {
            fullWidthButtons
            HStack(spacing: 12) {
                previousButton.labelStyle(.iconOnly)
                if canPause || isPaused {
                    playPauseButton.labelStyle(.iconOnly)
                }
                if canGoLive {
                    goLiveButton.labelStyle(.iconOnly)
                }
                nextButton.labelStyle(.iconOnly)
            }
        }
        #endif
    }

    private var fullWidthButtons: some View {
        HStack(spacing: 18) {
            previousButton
            if canPause || isPaused { playPauseButton }
            if canGoLive { goLiveButton }
            nextButton
        }
    }

    private var previousButton: some View {
        Button(action: onPrevious) {
            Label("Previous Channel", systemImage: "backward.end.fill")
        }
        .focused($focus, equals: .previous)
        .playerGlassButton(prominent: false)
    }

    private var playPauseButton: some View {
        Button(action: onPlayPause) {
            if isPaused {
                Label("Play", systemImage: "play.fill")
            } else {
                Label("Pause", systemImage: "pause.fill")
            }
        }
        .focused($focus, equals: .playPause)
        .playerGlassButton(prominent: false)
    }

    private var goLiveButton: some View {
        Button(action: onGoLive) {
            Label("Go Live", systemImage: "dot.radiowaves.left.and.right")
        }
        .focused($focus, equals: .goLive)
        .playerGlassButton(prominent: true)
    }

    private var nextButton: some View {
        Button(action: onNext) {
            Label("Next Channel", systemImage: "forward.end.fill")
        }
        .focused($focus, equals: .next)
        .playerGlassButton(prominent: false)
    }
}

private struct LiveChannelActivityView: View {
    let phase: LiveChannelPlaybackPhase

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text(phase.activityLabel)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

private struct LiveChannelInterruptionView: View {
    let interruption: LiveChannelInterruption
    let canRetry: Bool
    @FocusState.Binding var focus: LiveChannelControl?
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: interruption.icon)
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.9))
            Text(interruption.title)
                .font(.title2.bold())
            Text(interruption.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            HStack(spacing: 16) {
                if canRetry {
                    Button("Try Again", action: onRetry)
                        .focused($focus, equals: .retry)
                        .playerGlassButton(prominent: true)
                }
                Button("Close", action: onClose)
                    .focused($focus, equals: .close)
                    .playerGlassButton(prominent: false)
            }
        }
        .foregroundStyle(.white)
        .padding(36)
        .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 28))
        .padding(40)
    }
}

@MainActor
@Observable
final class LiveChannelPlayerModel {
    let engine: any LiveChannelEngine
    private(set) var phase: LiveChannelPlaybackPhase = .loading
    private(set) var hasPresentedFrame = false
    private(set) var seekableWindow: LiveSeekableWindow?
    private(set) var isAtLiveEdge = true
    private(set) var manualRetryCount = 0

    private let streamURL: URL
    private let httpHeaders: [String: String]
    private let uptime: @MainActor () -> TimeInterval
    private let idleSleepGuard = IdleSleepGuard()
    private var monitorTask: Task<Void, Never>?
    private var attemptStartedAt: TimeInterval = 0
    private var bufferingStartedAt: TimeInterval?
    @ObservationIgnored private var diagnostics = LiveChannelDiagnostics()
    @ObservationIgnored private var retuneBudget = LiveChannelRetuneBudget()
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    @ObservationIgnored private var foregroundTask: Task<Void, Never>?
    private var recoveryGeneration = 0
    private var attemptGeneration = 0
    private var attemptCount = 0
    private var isLoading = false
    private var isSuspended = false
    private var needsForegroundLoad = false
    private var pendingSourceReset = false
    private var userPaused = false
    private var stopped = false

    private static let startupTimeout: TimeInterval = 30
    private static let bufferingTimeout: TimeInterval = 60
    private static let maximumManualRetries = 2

    init(
        engine: any LiveChannelEngine,
        streamURL: URL,
        httpHeaders: [String: String] = [:],
        uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.engine = engine
        self.streamURL = streamURL
        self.httpHeaders = httpHeaders
        self.uptime = uptime
    }

    var canPause: Bool {
        !phase.isInterrupted && hasPresentedFrame && seekableWindow?.supportsTimeShift == true
    }

    var canGoLive: Bool {
        canPause && !isAtLiveEdge
    }

    var canRetry: Bool {
        phase.isInterrupted && manualRetryCount < Self.maximumManualRetries
    }

    fileprivate var interruption: LiveChannelInterruption? {
        switch phase {
        case .failed(let failure):
            return .failure(failure, retryLimitReached: !canRetry)
        case .ended:
            return .ended(retryLimitReached: !canRetry)
        case .loading, .buffering, .seeking, .reconnecting, .playing, .paused:
            return nil
        }
    }

    var showsActivityIndicator: Bool {
        phase == .loading || phase == .buffering || phase == .seeking || phase == .reconnecting
    }

    func start() async {
        stopped = false
        engine.onFailure = { [weak self] error in
            self?.fail(.engine(error))
        }
        engine.onEnded = { [weak self] in
            self?.streamEnded()
        }
        engine.onLiveSourceReset = { [weak self] in
            self?.sourceNeedsRetune()
        }
        startMonitor()
        guard !isSuspended else {
            needsForegroundLoad = true
            return
        }
        await loadAttempt()
    }

    func retry() async {
        guard canRetry else { return }
        cancelRecovery()
        manualRetryCount += 1
        diagnostics.event(.retry, attempt: attemptCount + 1)
        pendingSourceReset = false
        userPaused = false
        await loadAttempt()
    }

    func togglePlayPause() {
        guard !phase.isInterrupted else { return }
        if userPaused || phase == .paused {
            userPaused = false
            diagnostics.event(.resume, attempt: attemptCount)
            guard !isSuspended else { return }
            resumeActivePlayback()
        } else {
            guard canPause else { return }
            userPaused = true
            diagnostics.event(.pause, attempt: attemptCount)
            if !isLoading { cancelRecovery() }
            engine.pause()
            phase = .paused
            bufferingStartedAt = nil
            idleSleepGuard.allowSleep()
        }
    }

    func goLive() async {
        guard canGoLive, !isSuspended, !isLoading else { return }
        let generation = attemptGeneration
        userPaused = false
        diagnostics.event(.seek, attempt: attemptCount)
        phase = .seeking
        bufferingStartedAt = uptime()
        await engine.seekToLiveEdge()
        guard generation == attemptGeneration else { return }
        diagnostics.event(.seekCompleted, attempt: attemptCount)
        guard !stopped, !isSuspended, !phase.isInterrupted, !userPaused else { return }
        engine.play()
        refreshFromEngine()
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            guard isSuspended, !stopped else { return }
            diagnostics.event(.foreground, attempt: attemptCount)
            isSuspended = false
            guard !userPaused, !phase.isInterrupted else { return }
            resumeActivePlayback()
        case .inactive, .background:
            guard !stopped else { return }
            if !isSuspended {
                diagnostics.event(.suspend, attempt: attemptCount)
            }
            isSuspended = true
            if !isLoading || scenePhase == .background { cancelRecovery() }
            engine.pause()
            if scenePhase == .background {
                // This foreground-only harness has no PiP session. Stop both
                // platforms explicitly rather than racing Aether's auto-reload.
                needsForegroundLoad = true
                attemptGeneration += 1
                isLoading = false
                foregroundTask?.cancel()
                foregroundTask = nil
                engine.stop()
            }
            idleSleepGuard.allowSleep()
        @unknown default:
            isSuspended = true
            diagnostics.event(.suspend, attempt: attemptCount)
            cancelRecovery()
            engine.pause()
            idleSleepGuard.allowSleep()
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        attemptGeneration += 1
        diagnostics.event(.stop, attempt: attemptCount)
        cancelRecovery()
        foregroundTask?.cancel()
        foregroundTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        engine.onFailure = nil
        engine.onEnded = nil
        engine.onLiveSourceReset = nil
        engine.stop()
        idleSleepGuard.allowSleep()
    }

    private func loadAttempt() async {
        guard !stopped, !isSuspended else {
            needsForegroundLoad = true
            return
        }
        attemptGeneration += 1
        let generation = attemptGeneration
        attemptCount += 1
        diagnostics.event(.load, attempt: attemptCount)
        isLoading = true
        phase = .loading
        hasPresentedFrame = false
        seekableWindow = nil
        isAtLiveEdge = true
        attemptStartedAt = uptime()
        bufferingStartedAt = nil
        needsForegroundLoad = false
        await engine.loadLive(url: streamURL, httpHeaders: httpHeaders)
        guard generation == attemptGeneration, !stopped, !phase.isInterrupted else { return }
        isLoading = false
        if isSuspended || userPaused {
            engine.pause()
        }
        refreshFromEngine()
        if pendingSourceReset { requestRetune() }
    }

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.refreshFromEngine()
            }
        }
    }

    func refreshFromEngine() {
        guard !stopped, !phase.isInterrupted else {
            idleSleepGuard.allowSleep()
            return
        }
        guard !isSuspended else {
            idleSleepGuard.allowSleep()
            return
        }

        let snapshot = engine.liveSnapshot
        diagnostics.sample(snapshot, uptime: uptime(), attempt: attemptCount)
        if snapshot.phase == .failed {
            if case .failed(let error) = engine.status {
                fail(.engine(error))
            } else {
                fail(.engine(.invalidResponse))
            }
            return
        }
        if snapshot.phase == .ended {
            streamEnded()
            return
        }
        seekableWindow = snapshot.seekableRange.flatMap {
            LiveSeekableWindow(ranges: [(start: $0.lowerBound, duration: $0.upperBound - $0.lowerBound)])
        }
        if let behind = snapshot.behindLiveSeconds, behind.isFinite {
            isAtLiveEdge = behind <= 3
        } else {
            isAtLiveEdge = seekableWindow?.isAtLiveEdge(currentTime: snapshot.position) ?? true
        }
        hasPresentedFrame = hasPresentedFrame || snapshot.firstFrameReady
        if userPaused {
            phase = .paused
        } else if pendingSourceReset || recoveryTask != nil {
            phase = .reconnecting
        } else if !hasPresentedFrame {
            phase = .loading
        } else {
            switch snapshot.phase {
            case .idle, .loading: phase = .loading
            case .playing: phase = snapshot.firstFrameReady ? .playing : .buffering
            case .paused: phase = .paused
            case .seeking: phase = .seeking
            case .rebuffering: phase = .buffering
            case .stalled(let reconnecting): phase = reconnecting ? .reconnecting : .buffering
            case .ended, .failed: break
            }
        }
        if showsActivityIndicator {
            if bufferingStartedAt == nil { bufferingStartedAt = uptime() }
        } else {
            bufferingStartedAt = nil
        }
        if !userPaused, phase != .paused {
            if hasPresentedFrame {
                enforceBufferingTimeout()
            } else {
                enforceStartupTimeout()
            }
        }
        idleSleepGuard.keepAwake(phase == .playing)
    }

    private func resumeActivePlayback() {
        attemptStartedAt = uptime()
        bufferingStartedAt = nil
        if needsForegroundLoad {
            guard foregroundTask == nil else { return }
            foregroundTask = Task { [weak self] in
                guard let self else { return }
                await self.loadAttempt()
                guard !Task.isCancelled else { return }
                self.foregroundTask = nil
            }
        } else if pendingSourceReset {
            requestRetune()
        } else {
            engine.play()
            refreshFromEngine()
        }
    }

    private func sourceNeedsRetune() {
        guard !stopped, !phase.isInterrupted else { return }
        if !pendingSourceReset {
            diagnostics.event(.sourceReset, attempt: attemptCount)
            pendingSourceReset = true
        }
        requestRetune()
    }

    @discardableResult
    func requestRetune() -> Task<Void, Never>? {
        guard pendingSourceReset, !stopped, !phase.isInterrupted,
              !isSuspended, !userPaused, !isLoading else { return nil }
        if let recoveryTask { return recoveryTask }
        guard !retuneBudget.isExhausted else {
            fail(.recoveryExhausted)
            return nil
        }
        phase = .reconnecting
        let recovery = recoveryGeneration
        let delay = retuneBudget.delayBeforeNextAttempt(uptime: uptime())
        let task = Task { [weak self] in
            do {
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            } catch is CancellationError {
                return
            } catch {
                self?.fail(.engine(.unknown("recovery scheduling")))
                return
            }
            guard let self, !Task.isCancelled,
                  self.recoveryGeneration == recovery, !self.stopped,
                  !self.isSuspended, !self.userPaused else { return }
            self.retuneBudget.recordAttempt(uptime: self.uptime())
            self.pendingSourceReset = false
            self.diagnostics.event(.retune, attempt: self.attemptCount + 1)
            await self.loadAttempt()
            guard self.recoveryGeneration == recovery else { return }
            self.recoveryTask = nil
            self.refreshFromEngine()
            if self.pendingSourceReset { self.requestRetune() }
        }
        recoveryTask = task
        return task
    }

    private func cancelRecovery() {
        recoveryGeneration += 1
        recoveryTask?.cancel()
        recoveryTask = nil
    }

    private func enforceStartupTimeout() {
        guard uptime() - attemptStartedAt >= Self.startupTimeout else { return }
        fail(.startupTimedOut)
    }

    private func enforceBufferingTimeout() {
        guard showsActivityIndicator,
              let bufferingStartedAt,
              uptime() - bufferingStartedAt >= Self.bufferingTimeout else {
            return
        }
        fail(.bufferingTimedOut)
    }

    private func fail(_ failure: LiveChannelPlaybackFailure) {
        guard !stopped, !phase.isInterrupted else { return }
        switch failure {
        case .engine(let error):
            diagnostics.event(.failure, attempt: attemptCount, error: error)
        case .startupTimedOut:
            diagnostics.event(.startupTimeout, attempt: attemptCount)
        case .bufferingTimedOut:
            diagnostics.event(.stallTimeout, attempt: attemptCount)
        case .recoveryExhausted:
            diagnostics.event(.retuneExhausted, attempt: attemptCount)
        }
        phase = .failed(failure)
        attemptGeneration += 1
        isLoading = false
        cancelRecovery()
        foregroundTask?.cancel()
        foregroundTask = nil
        engine.stop()
        idleSleepGuard.allowSleep()
    }

    private func streamEnded() {
        guard !stopped, !phase.isInterrupted else { return }
        diagnostics.event(.ended, attempt: attemptCount)
        phase = .ended
        attemptGeneration += 1
        isLoading = false
        cancelRecovery()
        foregroundTask?.cancel()
        foregroundTask = nil
        engine.stop()
        idleSleepGuard.allowSleep()
    }
}

enum LiveChannelPlaybackPhase: Equatable {
    case loading
    case buffering
    case seeking
    case reconnecting
    case playing
    case paused
    case failed(LiveChannelPlaybackFailure)
    case ended

    var isInterrupted: Bool {
        switch self {
        case .failed, .ended:
            return true
        case .loading, .buffering, .seeking, .reconnecting, .playing, .paused:
            return false
        }
    }

    func statusLabel(isAtLiveEdge: Bool) -> LocalizedStringResource {
        switch self {
        case .loading:
            return "CONNECTING"
        case .buffering:
            return "BUFFERING"
        case .seeking:
            return "SEEKING"
        case .reconnecting:
            return "RECONNECTING"
        case .playing:
            return isAtLiveEdge ? "LIVE" : "BEHIND LIVE"
        case .paused:
            return "PAUSED"
        case .failed:
            return "STREAM ERROR"
        case .ended:
            return "STREAM ENDED"
        }
    }

    func statusColor(isAtLiveEdge: Bool) -> Color {
        switch self {
        case .playing where isAtLiveEdge:
            return .green
        case .failed, .ended:
            return .red
        case .paused:
            return .yellow
        case .loading, .buffering, .seeking, .reconnecting, .playing:
            return .white.opacity(0.82)
        }
    }

    var activityLabel: LocalizedStringResource {
        switch self {
        case .seeking: "Returning to Live…"
        case .reconnecting: "Reconnecting to Live Stream…"
        case .buffering: "Buffering Live Stream…"
        default: "Connecting to Live Stream…"
        }
    }
}

enum LiveChannelPlaybackFailure: Equatable {
    case startupTimedOut
    case bufferingTimedOut
    case recoveryExhausted
    case engine(AppError)

    static func engineMessage(_ error: AppError) -> LocalizedStringResource {
        switch error {
        case .notFound:
            "The channel provider could not find this stream. Its playlist link may be outdated, or the feed may be temporarily off air."
        case .unauthorized, .invalidCredentials:
            "The channel provider refused access to this stream. It may require authorization or be unavailable in your region."
        case .serverUnreachable:
            "Plozz could not reach the channel's streaming server. Check your internet connection or try again later."
        case .rateLimited:
            "The channel provider is limiting requests. Wait before trying again."
        case .invalidResponse:
            "The channel's playlist or video data could not be opened. Its link may be outdated or the feed may be temporarily unavailable."
        case .decoding:
            "The player could not decode this channel's audio or video. Try another stream version or channel."
        case .cancelled:
            "Opening this channel was cancelled."
        default:
            "Plozz could not start this live stream. Try another channel or retry later."
        }
    }
}

private struct LiveChannelInterruption {
    let icon: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    static func failure(
        _ failure: LiveChannelPlaybackFailure,
        retryLimitReached: Bool
    ) -> LiveChannelInterruption {
        let base: LiveChannelInterruption
        switch failure {
        case .startupTimedOut:
            base = LiveChannelInterruption(
                icon: "exclamationmark.triangle.fill",
                title: "Live Stream Timed Out",
                message: "The channel did not present video in time."
            )
        case .bufferingTimedOut:
            base = LiveChannelInterruption(
                icon: "wifi.exclamationmark",
                title: "Live Stream Stalled",
                message: "The channel stopped delivering playable video."
            )
        case .engine(let error):
            base = LiveChannelInterruption(
                icon: "exclamationmark.triangle.fill",
                title: "Unable to Play Channel",
                message: LiveChannelPlaybackFailure.engineMessage(error)
            )
        case .recoveryExhausted:
            base = LiveChannelInterruption(
                icon: "wifi.exclamationmark",
                title: "Unable to Reconnect",
                message: "This channel keeps disconnecting. Try again or choose another channel."
            )
        }
        return retryLimitReached ? base.withRetryLimitMessage() : base
    }

    static func ended(retryLimitReached: Bool) -> LiveChannelInterruption {
        let base = LiveChannelInterruption(
            icon: "stop.circle.fill",
            title: "Live Stream Ended",
            message: "The channel ended its stream."
        )
        return retryLimitReached ? base.withRetryLimitMessage() : base
    }

    private func withRetryLimitMessage() -> LiveChannelInterruption {
        LiveChannelInterruption(
            icon: icon,
            title: title,
            message: "This channel could not be restarted. Return to the channel list and try again later."
        )
    }
}
#endif
