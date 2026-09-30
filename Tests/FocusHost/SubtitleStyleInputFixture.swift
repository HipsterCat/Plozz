import CoreModels
import PlozzCoreUI
import SwiftUI
import UIKit
@testable import AppShell
@testable import FeaturePlayback

struct SubtitleStyleInputFixture: View {
    @State private var model = PlayerControlsModel()
    @State private var engine = SubtitleInputFixtureEngine()
    @State private var subtitles = LiveSubtitleModel()
    @State private var playerPresented = false
    @State private var navigationOpenAttempts = 0

    init() {
        let model = PlayerControlsModel()
        model.controlsVisible = true
        model.duration = 7200
        model.engineCapabilities = []
        model.subtitleOptions = [PlayerTrackOption(id: PlayerTrackOption.offID, title: Text("Off"), isSelected: true)]
        model.subtitleStyle = .default
        if ProcessInfo.processInfo.arguments.contains("--minimum-text-size") {
            model.subtitleStyle.fontScale = Double(SubtitleStyle.fontScalePercentages.first!) / 100
        } else if ProcessInfo.processInfo.arguments.contains("--maximum-text-size") {
            model.subtitleStyle.fontScale = Double(SubtitleStyle.fontScalePercentages.last!) / 100
        }
        _model = State(initialValue: model)
        if !ProcessInfo.processInfo.arguments.contains("--production-player-input") {
            PlayerScreenshotHook.pendingPanel = .subtitleStyle
        }
    }

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--production-player-input") {
                Color.black
                    .fullScreenCover(isPresented: $playerPresented) { playerContent }
                    .task { playerPresented = true }
            } else {
                playerContent
            }
        }
        .background {
            NavigationRailEdgeCatcher(
                onOpenNavigation: { navigationOpenAttempts += 1 },
                onLeaveNavigation: {},
                railHasFocus: false, isEnabled: true
            )
            .frame(width: 0, height: 0)
        }
    }

    private var playerContent: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--production-player-input") {
                CustomPlayerContainer(
                    engine: engine,
                    model: model, subtitleModel: subtitles,
                    actions: PlayerActions(setSubtitleStyle: { model.subtitleStyle = $0 }),
                    scrubPreview: nil, authenticatedHTTPResolver: nil,
                    themePalette: ThemePaletteBox(
                        makeControls: { model, actions, exit in
                            AnyView(PlayerControls(model: model, palette: .dark, actions: actions, onExitToSurface: exit))
                        },
                        makeSkipButton: { _, _, _, _ in AnyView(EmptyView()) },
                        makeUpNextCard: { _, _, _, _ in AnyView(EmptyView()) }
                    )
                )
            } else {
                PlayerControls(
                    model: model, palette: .dark,
                    actions: PlayerOptionsActions(setSubtitleStyle: { model.subtitleStyle = $0 }),
                    onExitToSurface: {}
                )
            }
        }
        .background(.black)
        .overlay(alignment: .leading) {
            if ProcessInfo.processInfo.arguments.contains("--nearby-back") {
                Button("Nearby Back") {}
                    .offset(y: -150)
            }
        }

        .overlay(alignment: .topLeading) {
            VStack {
                Text(verbatim: String(Int((model.subtitleStyle.fontScale * 100).rounded())))
                    .accessibilityIdentifier("subtitle-text-size-value")
                Text(verbatim: String(navigationOpenAttempts))
                    .accessibilityIdentifier("subtitle-navigation-open-attempts")
            }
            .allowsHitTesting(false)
        }
    }
}

@MainActor
private final class SubtitleInputFixtureEngine: VideoEngine {
    var status: VideoEngineStatus = .ready
    var isPaused = true
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 7200
    var furthestObservedPosition: TimeInterval = 0
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    var onProgress: (@MainActor () -> Void)?
    var onFailure: (@MainActor (AppError) -> Void)?
    var onEnded: (@MainActor () -> Void)?
    var onTracksChanged: (@MainActor () -> Void)?
    var onSubtitleCues: (@MainActor ([SubtitleCue]) -> Void)?
    var onSecondarySubtitleCues: (@MainActor ([SubtitleCue]) -> Void)?
    var onProbedSourceFactsChanged: (@MainActor (EngineProbedSourceFacts) -> Void)?

    func load(request: PlaybackRequest, startPosition: TimeInterval) async {}
    func play() { isPaused = false }
    func pause() { isPaused = true }
    func seek(to seconds: TimeInterval) async { currentTime = seconds }
    func stop() { status = .idle }
    func selectAudioTrack(_ track: MediaTrack?) {}
    func selectSubtitleTrack(_ track: MediaTrack?) {}
    func makeVideoOutputView() -> UIView { UIView() }
}
