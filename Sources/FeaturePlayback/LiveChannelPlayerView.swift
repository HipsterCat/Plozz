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
/// `NativeVideoEngine` and its existing `AVPlayerLayer` surface.
public struct LiveChannelPlayerView: View {
    private let channelID: String
    private let title: String
    private let streamURL: URL
    private let logoURL: URL?
    private let logoNeedsDarkBackground: Bool
    private let onPreviousChannel: () -> Void
    private let onNextChannel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: LiveChannelPlayerModel?
    @State private var controlsVisible = true
    @State private var autoHideRevision = 0
    @FocusState private var focusedControl: LiveChannelControl?

    public init(
        channelID: String,
        title: String,
        streamURL: URL,
        logoURL: URL?,
        logoNeedsDarkBackground: Bool = false,
        onPreviousChannel: @escaping () -> Void,
        onNextChannel: @escaping () -> Void
    ) {
        self.channelID = channelID
        self.title = title
        self.streamURL = streamURL
        self.logoURL = logoURL
        self.logoNeedsDarkBackground = logoNeedsDarkBackground
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
                    LiveChannelActivityView(isBuffering: model.hasPresentedFrame)
                }
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
            let playerModel = LiveChannelPlayerModel(
                channelID: channelID,
                title: title,
                streamURL: streamURL
            )
            model = playerModel
            playerModel.handleScenePhase(scenePhase)
            await playerModel.start()
            guard !Task.isCancelled else { return }
            focusAfterPresentation(.next)
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
            .focused($focus, equals: .close)
            .playerGlassButton(prominent: focus == .close)
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                previousButton
                if canPause || isPaused {
                    playPauseButton
                }
                if canGoLive {
                    goLiveButton
                }
                nextButton
            }

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
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.black.opacity(0.58), in: Capsule())
    }

    private var previousButton: some View {
        Button(action: onPrevious) {
            Label("Previous Channel", systemImage: "backward.end.fill")
        }
        .focused($focus, equals: .previous)
        .playerGlassButton(prominent: focus == .previous)
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
        .playerGlassButton(prominent: focus == .playPause || isPaused)
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
        .playerGlassButton(prominent: focus == .next)
    }
}

private struct LiveChannelActivityView: View {
    let isBuffering: Bool

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            if isBuffering {
                Text("Buffering Live Stream…")
                    .font(.headline)
                    .foregroundStyle(.white)
            } else {
                Text("Connecting to Live Stream…")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
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
                    .playerGlassButton(prominent: focus == .close || !canRetry)
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
private final class LiveChannelPlayerModel {
    let engine: NativeVideoEngine
    private(set) var phase: LiveChannelPlaybackPhase = .loading
    private(set) var hasPresentedFrame = false
    private(set) var seekableWindow: LiveSeekableWindow?
    private(set) var isAtLiveEdge = true
    private(set) var manualRetryCount = 0

    private let request: PlaybackRequest
    private let idleSleepGuard = IdleSleepGuard()
    private var monitorTask: Task<Void, Never>?
    private var attemptStartedAt = Date()
    private var bufferingStartedAt: Date?
    private var isSuspended = false
    private var shouldResumeWhenActive = false
    private var userPaused = false
    private var stopped = false

    private static let startupTimeout: TimeInterval = 15
    private static let bufferingTimeout: TimeInterval = 20
    private static let maximumManualRetries = 2

    init(channelID: String, title: String, streamURL: URL) {
        engine = NativeVideoEngine()
        request = PlaybackRequest(
            item: MediaItem(id: channelID, title: title, kind: .video),
            streamURL: streamURL,
            sourceFileName: streamURL.lastPathComponent
        )
    }

    var canPause: Bool {
        hasPresentedFrame && seekableWindow?.supportsTimeShift == true
    }

    var canGoLive: Bool {
        canPause && !isAtLiveEdge
    }

    var canRetry: Bool {
        phase.isInterrupted && manualRetryCount < Self.maximumManualRetries
    }

    var interruption: LiveChannelInterruption? {
        switch phase {
        case .failed(let failure):
            return .failure(failure, retryLimitReached: !canRetry)
        case .ended:
            return .ended(retryLimitReached: !canRetry)
        case .loading, .buffering, .playing, .paused:
            return nil
        }
    }

    var showsActivityIndicator: Bool {
        phase == .loading || phase == .buffering
    }

    func start() async {
        stopped = false
        engine.onFailure = { [weak self] error in
            self?.fail(.engine(error))
        }
        engine.onEnded = { [weak self] in
            self?.streamEnded()
        }
        startMonitor()
        await loadAttempt()
    }

    func retry() async {
        guard canRetry else { return }
        manualRetryCount += 1
        await loadAttempt()
    }

    func togglePlayPause() {
        guard !phase.isInterrupted else { return }
        if userPaused {
            userPaused = false
            if !isSuspended {
                engine.play()
                phase = hasPresentedFrame ? .buffering : .loading
                bufferingStartedAt = Date()
            }
        } else {
            guard canPause else { return }
            userPaused = true
            shouldResumeWhenActive = false
            engine.pause()
            phase = .paused
            bufferingStartedAt = nil
            idleSleepGuard.allowSleep()
        }
    }

    func goLive() async {
        guard let target = seekableWindow?.liveTarget, canGoLive else { return }
        userPaused = false
        phase = .buffering
        bufferingStartedAt = Date()
        await engine.seek(to: target, kind: .exact)
        guard !stopped, !isSuspended, !phase.isInterrupted else { return }
        engine.play()
        refreshFromPlayer()
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            isSuspended = false
            let shouldResume = shouldResumeWhenActive && !userPaused && !phase.isInterrupted
            shouldResumeWhenActive = false
            if shouldResume {
                if hasPresentedFrame {
                    bufferingStartedAt = Date()
                } else {
                    attemptStartedAt = Date()
                }
                engine.play()
                phase = hasPresentedFrame ? .buffering : .loading
            }
        case .inactive, .background:
            guard !isSuspended else { return }
            isSuspended = true
            shouldResumeWhenActive = !userPaused && !phase.isInterrupted
            engine.pause()
            idleSleepGuard.allowSleep()
        @unknown default:
            isSuspended = true
            shouldResumeWhenActive = false
            engine.pause()
            idleSleepGuard.allowSleep()
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        monitorTask?.cancel()
        monitorTask = nil
        engine.onFailure = nil
        engine.onEnded = nil
        engine.stop()
        idleSleepGuard.allowSleep()
    }

    private func loadAttempt() async {
        phase = .loading
        hasPresentedFrame = false
        seekableWindow = nil
        isAtLiveEdge = true
        attemptStartedAt = Date()
        bufferingStartedAt = nil
        userPaused = false
        engine.stop()
        await engine.load(request: request, startPosition: 0)
        guard !stopped, !phase.isInterrupted else { return }
        if isSuspended {
            engine.pause()
        }
        refreshFromPlayer()
    }

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.refreshFromPlayer()
            }
        }
    }

    private func refreshFromPlayer() {
        guard !stopped, !phase.isInterrupted else {
            idleSleepGuard.allowSleep()
            return
        }
        guard !isSuspended else {
            idleSleepGuard.allowSleep()
            return
        }

        guard let player = engine.underlyingPlayer,
              let item = player.currentItem else {
            enforceStartupTimeout()
            idleSleepGuard.allowSleep()
            return
        }

        if item.status == .failed || item.error != nil {
            fail(.engine(.invalidResponse))
            return
        }

        let ranges = item.seekableTimeRanges.map {
            let range = $0.timeRangeValue
            return (start: range.start.seconds, duration: range.duration.seconds)
        }
        seekableWindow = LiveSeekableWindow(ranges: ranges)
        if let seekableWindow,
           engine.currentTime >= seekableWindow.lowerBound - 1 {
            isAtLiveEdge = seekableWindow.isAtLiveEdge(currentTime: engine.currentTime)
        } else {
            isAtLiveEdge = true
        }

        let hadPresentedFrame = hasPresentedFrame
        if let surface = engine.makeVideoOutputView() as? PlayerLayerView,
           surface.playerLayer.isReadyForDisplay {
            hasPresentedFrame = true
        }
        if !hadPresentedFrame, hasPresentedFrame {
            bufferingStartedAt = nil
        }

        if isSuspended || userPaused {
            phase = .paused
            bufferingStartedAt = nil
            idleSleepGuard.allowSleep()
            return
        }

        switch player.timeControlStatus {
        case .playing where hasPresentedFrame:
            phase = .playing
            bufferingStartedAt = nil
        case .waitingToPlayAtSpecifiedRate:
            beginOrContinueWaiting()
        case .paused:
            beginOrContinueWaiting()
        case .playing:
            phase = .loading
        @unknown default:
            beginOrContinueWaiting()
        }

        if hasPresentedFrame {
            enforceBufferingTimeout()
        } else {
            enforceStartupTimeout()
        }
        idleSleepGuard.keepAwake(phase == .playing && engine.preventsDisplaySleep)
    }

    private func beginOrContinueWaiting() {
        phase = hasPresentedFrame ? .buffering : .loading
        if bufferingStartedAt == nil {
            bufferingStartedAt = Date()
        }
    }

    private func enforceStartupTimeout() {
        guard Date().timeIntervalSince(attemptStartedAt) >= Self.startupTimeout else { return }
        fail(.startupTimedOut)
    }

    private func enforceBufferingTimeout() {
        guard phase == .buffering,
              let bufferingStartedAt,
              Date().timeIntervalSince(bufferingStartedAt) >= Self.bufferingTimeout else {
            return
        }
        fail(.bufferingTimedOut)
    }

    private func fail(_ failure: LiveChannelPlaybackFailure) {
        guard !stopped, !phase.isInterrupted else { return }
        engine.pause()
        idleSleepGuard.allowSleep()
        phase = .failed(failure)
    }

    private func streamEnded() {
        guard !stopped, !phase.isInterrupted else { return }
        engine.pause()
        idleSleepGuard.allowSleep()
        phase = .ended
    }
}

private enum LiveChannelPlaybackPhase: Equatable {
    case loading
    case buffering
    case playing
    case paused
    case failed(LiveChannelPlaybackFailure)
    case ended

    var isInterrupted: Bool {
        switch self {
        case .failed, .ended:
            return true
        case .loading, .buffering, .playing, .paused:
            return false
        }
    }

    func statusLabel(isAtLiveEdge: Bool) -> LocalizedStringResource {
        switch self {
        case .loading:
            return "CONNECTING"
        case .buffering:
            return "BUFFERING"
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
        case .loading, .buffering, .playing:
            return .white.opacity(0.82)
        }
    }
}

private enum LiveChannelPlaybackFailure: Equatable {
    case startupTimedOut
    case bufferingTimedOut
    case engine(AppError)
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
                message: error.userMessage
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
