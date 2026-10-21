import AVFoundation
import CoreModels
import FeaturePlayback
import Foundation
import XCTest

@MainActor
final class StreamingBufferingHostedTests: XCTestCase {
    func testServerHLSRecoversFromAnEncoderSegmentGap() async throws {
        try await exercise(pauseBeforeStarting: false, rate: 1)
    }

    func testServerHLSResumePreservesSpeedAcrossAnEncoderSegmentGap() async throws {
        try await exercise(pauseBeforeStarting: true, rate: 1.25)
    }

    private func exercise(pauseBeforeStarting: Bool, rate: Double) async throws {
        let initialization = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "iptv-init", withExtension: "mp4", subdirectory: "Fixtures"
        ))
        let segment = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "iptv-segment-0", withExtension: "m4s", subdirectory: "Fixtures"
        ))
        let server = try IPTVTestHTTPServer { request in
            if request.contains("/media.m3u8") {
                return .init(data: Data("""
                #EXTM3U
                #EXT-X-VERSION:7
                #EXT-X-TARGETDURATION:12
                #EXT-X-PLAYLIST-TYPE:VOD
                #EXT-X-MAP:URI="init.mp4"
                #EXTINF:12,
                first.m4s
                #EXT-X-DISCONTINUITY
                #EXTINF:12,
                delayed.m4s
                #EXT-X-DISCONTINUITY
                #EXTINF:12,
                last.m4s
                #EXT-X-ENDLIST

                """.utf8), headers: ["Content-Type": "application/vnd.apple.mpegurl"])
            }
            if request.contains("/init.mp4") {
                return .init(file: initialization, headers: ["Content-Type": "video/mp4"])
            }
            if request.contains(".m4s") {
                return .init(
                    file: segment, headers: ["Content-Type": "video/mp4"],
                    headerDelay: request.contains("/delayed.m4s") ? .seconds(20) : .zero
                )
            }
            return .init(status: 404)
        }
        addTeardownBlock { await server.stop() }
        let origin = try await server.start()
        let engine = NativeVideoEngine(startsMuted: true)
        defer { engine.stop() }
        var request = PlaybackRequest(
            item: .init(id: "paced-transcode", title: "Paced transcode", kind: .movie, runtime: 36),
            streamURL: origin.appendingPathComponent("media.m3u8"),
            playSessionID: "paced-fixture", isTranscoding: true, sourceProvider: .jellyfin
        )
        request.streamingOptions = .init(quality: .low)
        let started = ContinuousClock.now
        await engine.load(request: request, startPosition: 0)
        let player = try XCTUnwrap(engine.underlyingPlayer)
        if pauseBeforeStarting {
            engine.pause()
            engine.setPlaybackSpeed(rate)
            XCTAssertTrue(engine.isPaused)
            XCTAssertEqual(player.rate, 0)
            engine.play()
        }
        XCTAssertTrue(player.automaticallyWaitsToMinimizeStalling)
        let item = try XCTUnwrap(player.currentItem)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        defer { item.remove(output) }
        var decodedFrames = 0
        let startupDeadline = started + .seconds(45)
        while ContinuousClock.now < startupDeadline, item.status != .failed {
            if player.currentTime().seconds > 0.2,
               output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil) != nil {
                decodedFrames += 1
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(decodedFrames, 0, "Require a decoded frame, not readiness or HTTP success.")
        guard decodedFrames > 0 else { return }
        XCTAssertEqual(player.rate, Float(rate))
        let firstFrame = ContinuousClock.now
        let initialPosition = player.currentTime().seconds
        let observationDeadline = firstFrame + .seconds(20)
        while ContinuousClock.now < observationDeadline, item.status != .failed {
            if output.hasNewPixelBuffer(forItemTime: player.currentTime()),
               output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil) != nil {
                decodedFrames += 1
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let advancedDuringGap = player.currentTime().seconds - initialPosition
        // Automatic buffering cannot predict an arbitrary server production gap.
        // Once all segments are available, the same player must recover unaided.
        try await Task.sleep(for: .seconds(3))
        let recoveryPosition = player.currentTime().seconds
        let recoveryDeadline = ContinuousClock.now + .seconds(5)
        var recoveryFrames = 0
        while ContinuousClock.now < recoveryDeadline, item.status != .failed {
            if output.hasNewPixelBuffer(forItemTime: player.currentTime()),
               output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil) != nil {
                recoveryFrames += 1
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let recoveredProgress = player.currentTime().seconds - recoveryPosition
        print("TRANSCODE_BUFFERING startup=\(started.duration(to: firstFrame))"
            + " gap_progress=\(advancedDuringGap) recovery_progress=\(recoveredProgress)"
            + " frames=\(decodedFrames) recovery_frames=\(recoveryFrames)")
        XCTAssertNotEqual(item.status, .failed)
        XCTAssertGreaterThan(decodedFrames, 30)
        XCTAssertGreaterThan(recoveryFrames, 20)
        XCTAssertGreaterThan(player.currentTime().seconds, 18)
        XCTAssertGreaterThan(
            recoveredProgress, 4.5 * rate,
            "Playback must recover at the selected speed after the server supplies the remaining segments."
        )
    }
}
