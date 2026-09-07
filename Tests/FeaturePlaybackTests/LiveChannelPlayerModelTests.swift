#if DEBUG && canImport(UIKit)
import CoreModels
import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class LiveChannelPlayerModelTests: XCTestCase {
    func testLiveFailureCopyDoesNotAskPublicChannelViewersToSignInAgain() {
        let messages: [(AppError, String)] = [
            (.notFound, "playlist link may be outdated"),
            (.unauthorized, "provider refused access"),
            (.serverUnreachable, "streaming server"),
            (.invalidResponse, "playlist or video data"),
            (.decoding, "could not decode"),
            (.rateLimited(retryAfter: nil), "Wait before trying again"),
            (.unknown("https://example.invalid/?token=fixture-secret"), "could not start this live stream")
        ]
        for (error, expected) in messages {
            let message = String(localized: LiveChannelPlaybackFailure.engineMessage(error))
            XCTAssertTrue(message.contains(expected), message)
            XCTAssertFalse(message.contains("fixture-secret"))
            XCTAssertFalse(message.contains("sign in again"))
            XCTAssertFalse(message.contains("Something went wrong"))
        }
    }

    private func makeModel(
        engine: LiveEngineSpy,
        clock: LiveTestClock = LiveTestClock()
    ) -> LiveChannelPlayerModel {
        LiveChannelPlayerModel(
            engine: engine,
            streamURL: URL(string: "https://example.invalid/channel.m3u8")!,
            uptime: { clock.now }
        )
    }

    func testLoadsLiveInsteadOfConstructingVODRequest() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        XCTAssertEqual(engine.liveLoads, 1)
        XCTAssertEqual(engine.vodLoads, 0)
        XCTAssertNotNil(engine.onLiveSourceReset)
        XCTAssertEqual(model.phase, .playing)
        XCTAssertFalse(model.showsActivityIndicator)
    }

    func testPlayingIntentWithoutFirstFrameKeepsStartupCover() async {
        let engine = LiveEngineSpy()
        engine.liveSnapshot.firstFrameReady = false
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        XCTAssertEqual(model.phase, .loading)
        XCTAssertFalse(model.hasPresentedFrame)
        engine.liveSnapshot.firstFrameReady = true
        model.refreshFromEngine()
        XCTAssertEqual(model.phase, .playing)
        XCTAssertFalse(model.showsActivityIndicator)
    }

    func testPlaylistHeadersSurviveLiveLoadRetryAndSourceReset() async {
        let engine = LiveEngineSpy()
        let headers = ["User-Agent": "IPTV test", "Referer": "https://example.invalid/"]
        let model = LiveChannelPlayerModel(
            engine: engine, streamURL: URL(string: "https://example.invalid/live.m3u8")!,
            httpHeaders: headers
        )
        defer { model.stop() }
        await model.start()
        engine.onFailure?(.serverUnreachable)
        await model.retry()
        engine.onLiveSourceReset?()
        await model.requestRetune()?.value
        XCTAssertEqual(engine.loadedHeaders, Array(repeating: headers, count: engine.liveLoads))
        XCTAssertEqual(engine.liveLoads, 3)
    }

    func testEnginePhaseOwnsStatusEvenWhileClockAdvances() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        let cases: [(LiveChannelEnginePhase, LiveChannelPlaybackPhase)] = [
            (.rebuffering, .buffering),
            (.stalled(reconnecting: true), .reconnecting),
            (.stalled(reconnecting: false), .buffering),
            (.seeking, .seeking),
            (.paused, .paused),
            (.playing, .playing),
        ]
        for (enginePhase, expectedPhase) in cases {
            engine.liveSnapshot.phase = enginePhase
            engine.liveSnapshot.position += 1
            model.refreshFromEngine()
            XCTAssertEqual(model.phase, expectedPhase)
        }
    }

    func testPauseIntentWinsOverLatePlayingPublication() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        model.togglePlayPause()
        engine.liveSnapshot.phase = .playing
        model.refreshFromEngine()
        XCTAssertEqual(model.phase, .paused)
        XCTAssertFalse(model.showsActivityIndicator)
        model.togglePlayPause()
        XCTAssertEqual(engine.playCount, 1)
        XCTAssertEqual(model.phase, .playing)
    }

    func testRouteReplacementWaitsForItsOwnFirstFrame() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        engine.liveSnapshot.route = .localHLS
        engine.liveSnapshot.firstFrameReady = false
        model.refreshFromEngine()
        XCTAssertEqual(model.phase, .buffering)
        engine.liveSnapshot.firstFrameReady = true
        model.refreshFromEngine()
        XCTAssertEqual(model.phase, .playing)
    }

    func testNoAdvertisedWindowDoesNotInventTimeshift() async {
        let engine = LiveEngineSpy()
        engine.liveSnapshot.seekableRange = nil
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        XCTAssertFalse(model.canPause)
        XCTAssertFalse(model.canGoLive)
        model.togglePlayPause()
        await model.goLive()
        XCTAssertEqual(engine.pauseCount, 0)
        XCTAssertEqual(engine.goLiveCount, 0)
    }

    func testGoLiveUsesEngineAPIInsteadOfGuessingSeekTarget() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        XCTAssertTrue(model.canGoLive)
        await model.goLive()
        XCTAssertEqual(engine.goLiveCount, 1)
        XCTAssertEqual(engine.genericSeekCount, 0)
        XCTAssertTrue(model.isAtLiveEdge)
    }

    func testPauseDuringGoLiveDoesNotResumeAtCompletion() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        engine.onGoLive = { model.togglePlayPause() }
        await model.goLive()
        model.refreshFromEngine()
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertEqual(model.phase, .paused)
    }

    func testStopDuringGoLiveIgnoresLateCompletion() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        await model.start()
        engine.onGoLive = { model.stop() }
        await model.goLive()
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertNil(engine.onLiveSourceReset)
    }

    func testStopDuringLoadDoesNotResurrectPlayback() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        engine.onLoad = { model.stop() }
        await model.start()
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertFalse(model.hasPresentedFrame)
        XCTAssertNil(engine.onFailure)
    }

    func testFailureDuringLoadSurvivesLateLoadCompletion() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        engine.onLoad = { engine.onFailure?(.notFound) }
        await model.start()
        XCTAssertEqual(model.phase, .failed(.engine(.notFound)))
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertTrue(model.canRetry)
    }

    func testStartupTimeoutStopsUnreadyEngine() async {
        let clock = LiveTestClock()
        let engine = LiveEngineSpy()
        engine.liveSnapshot.firstFrameReady = false
        let model = makeModel(engine: engine, clock: clock)
        defer { model.stop() }
        await model.start()
        clock.now = 29
        model.refreshFromEngine()
        XCTAssertEqual(model.phase, .loading)
        clock.now = 30
        model.refreshFromEngine()
        XCTAssertEqual(model.phase, .failed(.startupTimedOut))
        XCTAssertEqual(engine.stopCount, 1)
    }

    func testStallAllowsEngineRecoveryButIsStillBounded() async {
        let clock = LiveTestClock()
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine, clock: clock)
        defer { model.stop() }
        await model.start()
        engine.liveSnapshot.phase = .stalled(reconnecting: true)
        model.refreshFromEngine()
        clock.now = 59
        model.refreshFromEngine()
        XCTAssertEqual(model.phase, .reconnecting)
        clock.now = 60
        model.refreshFromEngine()
        XCTAssertEqual(model.phase, .failed(.bufferingTimedOut))
    }

    func testTerminalEngineErrorIsNotMistakenForBuffering() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        engine.status = .failed(.unauthorized)
        engine.liveSnapshot.phase = .failed
        model.refreshFromEngine()
        XCTAssertEqual(model.phase, .failed(.engine(.unauthorized)))
        XCTAssertFalse(model.showsActivityIndicator)
    }

    func testManualRetriesAreBounded() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        for _ in 0..<3 {
            engine.onFailure?(.serverUnreachable)
            await model.retry()
        }
        XCTAssertEqual(engine.liveLoads, 3)
        XCTAssertEqual(model.manualRetryCount, 2)
        XCTAssertFalse(model.canRetry)
    }

    func testSourceResetRetunesOnlyThreeTimesPerChannelSession() async {
        let clock = LiveTestClock()
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine, clock: clock)
        defer { model.stop() }
        await model.start()
        for tick in 0..<3 {
            clock.now = Double(tick) * 20
            engine.onLiveSourceReset?()
            await model.requestRetune()?.value
            XCTAssertEqual(model.phase, .playing)
        }
        XCTAssertEqual(engine.liveLoads, 4)
        engine.onLiveSourceReset?()
        XCTAssertEqual(model.phase, .failed(.recoveryExhausted))
        XCTAssertEqual(engine.liveLoads, 4)
        await model.retry()
        XCTAssertEqual(engine.liveLoads, 5)
        engine.onLiveSourceReset?()
        XCTAssertEqual(model.phase, .failed(.recoveryExhausted))
        XCTAssertEqual(engine.liveLoads, 5)
    }

    func testSourceResetRaisedDuringLoadIsNotLost() async {
        let engine = LiveEngineSpy()
        engine.onLoad = {
            if engine.liveLoads == 1 { engine.onLiveSourceReset?() }
        }
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        await model.requestRetune()?.value
        XCTAssertEqual(engine.liveLoads, 2)
        XCTAssertEqual(model.phase, .playing)
    }

    func testSourceResetWhilePausedWaitsForUserResume() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        model.togglePlayPause()
        engine.onLiveSourceReset?()
        XCTAssertNil(model.requestRetune())
        XCTAssertEqual(engine.liveLoads, 1)
        model.togglePlayPause()
        await model.requestRetune()?.value
        XCTAssertEqual(engine.liveLoads, 2)
        XCTAssertEqual(model.phase, .playing)
    }

    func testSourceResetWhileInactiveWaitsForForeground() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        model.handleScenePhase(.inactive)
        engine.onLiveSourceReset?()
        XCTAssertNil(model.requestRetune())
        XCTAssertEqual(engine.liveLoads, 1)
        model.handleScenePhase(.active)
        await model.requestRetune()?.value
        XCTAssertEqual(engine.liveLoads, 2)
    }

    func testRepeatedResetSignalsCoalesceBeforeRetuneStarts() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        for _ in 0..<100 { engine.onLiveSourceReset?() }
        await model.requestRetune()?.value
        XCTAssertEqual(engine.liveLoads, 2)
        XCTAssertEqual(model.phase, .playing)
    }

    func testStopCancelsScheduledRecovery() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        await model.start()
        engine.onLiveSourceReset?()
        let task = model.requestRetune()
        model.stop()
        await task?.value
        XCTAssertEqual(engine.liveLoads, 1)
        XCTAssertNil(engine.onLiveSourceReset)
    }

    func testBackgroundStopsEngineAndPausedReturnDoesNotAutoplay() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        model.togglePlayPause()
        model.handleScenePhase(.inactive)
        model.handleScenePhase(.background)
        XCTAssertEqual(engine.stopCount, 1)
        model.handleScenePhase(.active)
        XCTAssertEqual(engine.liveLoads, 1)
        XCTAssertEqual(engine.playCount, 0)
        let loaded = expectation(description: "Reload only after explicit resume")
        engine.onLoad = { loaded.fulfill() }
        model.togglePlayPause()
        await fulfillment(of: [loaded], timeout: 2)
        XCTAssertEqual(engine.liveLoads, 2)
    }

    func testInactiveReturnDoesNotReloadHealthyStream() async {
        let engine = LiveEngineSpy()
        let model = makeModel(engine: engine)
        defer { model.stop() }
        await model.start()
        model.handleScenePhase(.inactive)
        model.handleScenePhase(.active)
        XCTAssertEqual(engine.liveLoads, 1)
        XCTAssertEqual(engine.stopCount, 0)
        XCTAssertEqual(model.phase, .playing)
    }
}

private final class LiveTestClock {
    var now: TimeInterval = 0
}

@MainActor
private final class LiveEngineSpy: LiveChannelEngine {
    var liveSnapshot = LiveChannelEngineSnapshot(
        phase: .playing, firstFrameReady: true, position: 100,
        bufferedPosition: 110, seekableRange: 90...110,
        behindLiveSeconds: 10, route: .nativeHLS
    )
    var status: VideoEngineStatus = .ready
    var isPaused = false
    var currentTime: TimeInterval { liveSnapshot.position }
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
    var onLoad: (@MainActor () async -> Void)?
    var onGoLive: (@MainActor () -> Void)?
    var liveLoads = 0
    var loadedHeaders: [[String: String]] = []
    var vodLoads = 0
    var playCount = 0
    var pauseCount = 0
    var stopCount = 0
    var goLiveCount = 0
    var genericSeekCount = 0

    func loadLive(url: URL, httpHeaders: [String: String]) async {
        liveLoads += 1
        loadedHeaders.append(httpHeaders)
        status = .ready
        isPaused = false
        await onLoad?()
    }
    func load(request: PlaybackRequest, startPosition: TimeInterval) async { vodLoads += 1 }
    func play() { playCount += 1; isPaused = false }
    func pause() { pauseCount += 1; isPaused = true }
    func stop() {
        stopCount += 1
        status = .idle
        onLoad = nil
        onGoLive = nil
    }
    func seek(to seconds: TimeInterval) async { genericSeekCount += 1 }
    func seekToLiveEdge() async {
        goLiveCount += 1
        onGoLive?()
        liveSnapshot.behindLiveSeconds = 0
    }
    func selectAudioTrack(_ track: MediaTrack?) {}
    func selectSubtitleTrack(_ track: MediaTrack?) {}
    func makeVideoOutputView() -> UIView { UIView() }
}
#endif
