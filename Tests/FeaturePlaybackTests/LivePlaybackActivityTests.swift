#if DEBUG
import CoreModels
import CoreNetworking
import XCTest
@testable import FeaturePlayback

final class LivePlaybackActivityTests: XCTestCase {
    private func sample(
        _ time: Double, _ position: Double,
        ready: Bool = true, transport: LivePlaybackActivity.Transport = .playing
    ) -> LivePlaybackActivity.Sample {
        .init(uptime: time, position: position, presentationReady: ready, transport: transport)
    }

    func testAdvancingVideoDoesNotBufferWhileTransportReportsWaiting() {
        var activity = LivePlaybackActivity()
        XCTAssertEqual(activity.update(sample(0, 100)), .playing)
        for tick in 1...120 {
            let time = Double(tick) / 4
            XCTAssertEqual(
                activity.update(sample(time, 100 + time, transport: .waiting)),
                .playing
            )
            XCTAssertTrue(activity.clockAdvanced)
        }
    }

    func testSingleWaitingSampleDoesNotFlashOverlay() {
        var activity = LivePlaybackActivity()
        _ = activity.update(sample(0, 100))
        XCTAssertEqual(activity.update(sample(0.25, 100, transport: .waiting)), .playing)
        XCTAssertEqual(activity.update(sample(0.5, 100.5)), .playing)
    }

    func testFrozenClockBuffersEvenIfTransportClaimsPlaying() {
        var activity = LivePlaybackActivity()
        _ = activity.update(sample(0, 100))
        XCTAssertEqual(activity.update(sample(1, 100)), .buffering)
        XCTAssertEqual(activity.update(sample(20, 100)), .buffering)
        XCTAssertEqual(activity.stalledFor, 20)
    }

    func testRealStallRecoversWhenClockAdvances() {
        var activity = LivePlaybackActivity()
        _ = activity.update(sample(0, 100))
        XCTAssertEqual(activity.update(sample(1, 100, transport: .waiting)), .buffering)
        XCTAssertEqual(activity.update(sample(1.25, 100.25, transport: .waiting)), .playing)
        XCTAssertEqual(activity.stalledFor, 0)
    }

    func testStartupRequiresVideoNotJustAudioClockOrTransport() {
        var activity = LivePlaybackActivity()
        for tick in 0...20 {
            let time = Double(tick) / 4
            XCTAssertEqual(activity.update(sample(time, time, ready: false)), .loading)
        }
        XCTAssertFalse(activity.hasPresentedFrame)
        XCTAssertFalse(activity.clockAdvanced)
        XCTAssertEqual(activity.update(sample(5.25, 5.25)), .playing)
    }

    func testUserPauseWinsOverAdvancingClock() {
        var activity = LivePlaybackActivity()
        _ = activity.update(sample(0, 100))
        XCTAssertEqual(activity.update(sample(0.25, 100.25), intent: .pause), .paused)
        XCTAssertEqual(activity.update(sample(0.5, 100.5), intent: .pause), .paused)
        XCTAssertFalse(activity.clockAdvanced)
        XCTAssertEqual(activity.update(sample(1, 100.5)), .buffering)
        XCTAssertEqual(activity.update(sample(1.25, 100.75)), .playing)
    }

    func testSeekJumpDoesNotCountAsPlaying() {
        var activity = LivePlaybackActivity()
        _ = activity.update(sample(0, 100))
        XCTAssertEqual(activity.update(sample(0.25, 900), intent: .seek), .buffering)
        XCTAssertEqual(activity.update(sample(0.5, 900)), .buffering)
        XCTAssertFalse(activity.clockAdvanced)
        XCTAssertEqual(activity.update(sample(0.75, 900.25)), .playing)
    }

    func testUnannouncedDiscontinuityNeedsNewContinuousProgress() {
        var activity = LivePlaybackActivity()
        _ = activity.update(sample(0, 100))
        XCTAssertEqual(activity.update(sample(0.25, 5_000)), .buffering)
        XCTAssertFalse(activity.clockAdvanced)
        XCTAssertEqual(activity.update(sample(0.5, 5_000.25)), .playing)
        XCTAssertEqual(activity.update(sample(0.75, 100)), .buffering)
        XCTAssertEqual(activity.update(sample(1, 100.25)), .playing)
    }

    func testForegroundRequiresFreshProgressInsteadOfBackgroundGap() {
        var activity = LivePlaybackActivity()
        _ = activity.update(sample(0, 100))
        XCTAssertEqual(activity.update(sample(1, 101), intent: .suspended), .paused)
        XCTAssertEqual(activity.update(sample(100, 200)), .buffering)
        XCTAssertEqual(activity.update(sample(100.25, 200.25)), .playing)
    }

    func testRetryDoesNotReusePreviousReadinessOrProgress() {
        var activity = LivePlaybackActivity()
        _ = activity.update(sample(0, 100))
        activity.reset()
        XCTAssertFalse(activity.hasPresentedFrame)
        XCTAssertEqual(activity.update(sample(1, 0, ready: false)), .loading)
        XCTAssertEqual(activity.update(sample(1.25, 0.25)), .playing)
    }

    func testInvalidClockCannotMaskStall() {
        var activity = LivePlaybackActivity()
        _ = activity.update(sample(0, 100))
        XCTAssertEqual(activity.update(sample(1, .nan)), .buffering)
        XCTAssertEqual(activity.update(sample(2, .infinity)), .buffering)
        XCTAssertFalse(activity.clockAdvanced)
    }

    func testLosingReadySurfaceDoesNotCountAudioAsVideoProgress() {
        var activity = LivePlaybackActivity()
        _ = activity.update(sample(0, 100))
        XCTAssertEqual(activity.update(sample(0.25, 100.25, ready: false)), .buffering)
        XCTAssertFalse(activity.clockAdvanced)
    }

    func testDiagnosticCadenceCoalescesChangesAndAddsHeartbeat() {
        var cadence = LiveChannelDiagnostics.Cadence()
        XCTAssertTrue(cadence.shouldEmit(signature: "playing", uptime: 0))
        XCTAssertFalse(cadence.shouldEmit(signature: "waiting", uptime: 0.25))
        XCTAssertFalse(cadence.shouldEmit(signature: "playing", uptime: 0.5))
        XCTAssertTrue(cadence.shouldEmit(signature: "waiting", uptime: 1))
        XCTAssertFalse(cadence.shouldEmit(signature: "waiting", uptime: 10))
        XCTAssertTrue(cadence.shouldEmit(signature: "waiting", uptime: 11))
    }

    func testDiagnosticChurnIsLimitedToOneSnapshotPerSecond() {
        var cadence = LiveChannelDiagnostics.Cadence()
        let emitted = (0..<400).filter { tick in
            cadence.shouldEmit(signature: String(tick), uptime: Double(tick) / 4)
        }
        XCTAssertEqual(emitted.count, 100)
    }

    func testDiagnosticErrorsNeverIncludeRawDetailsOrCredentials() {
        let wasEnabled = HandoffDiagnostics.isEnabled
        HandoffDiagnostics.setEnabled(true)
        defer { HandoffDiagnostics.setEnabled(wasEnabled) }
        let diagnostics = LiveChannelDiagnostics()
        diagnostics.event(
            .failure, attempt: 1,
            error: .unknown("https://fixture-user:fixture-password@example.invalid/live?token=fixture-secret")
        )
        let line = PlozzLog.recentEntries(limit: 1).first?.message ?? ""
        XCTAssertTrue(line.contains("LIVE_TV session="))
        XCTAssertTrue(line.contains("engine=AVPlayer"))
        XCTAssertTrue(line.contains("error=unknown"))
        XCTAssertFalse(line.contains("https://"))
        XCTAssertFalse(line.contains("fixture-"))
        XCTAssertFalse(line.contains("token="))
    }
}
#endif
