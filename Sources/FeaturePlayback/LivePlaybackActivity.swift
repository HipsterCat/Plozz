#if DEBUG
import Foundation

/// Reconciles the presentation clock with transport hints without decoding or
/// copying video frames. A transport wait is not a visible stall while the ready
/// video surface's clock is advancing.
struct LivePlaybackActivity {
    enum Transport: String { case playing, waiting, paused, unknown }
    enum Intent { case play, pause, seek, suspended }
    enum State: String { case loading, playing, buffering, paused }

    struct Sample {
        let uptime: TimeInterval
        let position: TimeInterval
        let presentationReady: Bool
        let transport: Transport
    }

    private(set) var hasPresentedFrame = false
    private(set) var clockAdvanced = false
    private(set) var stalledFor: TimeInterval?
    private var previousSample: Sample?
    private var lastProgressAt: TimeInterval?

    static let stallGrace: TimeInterval = 1

    mutating func reset(preservingFrame: Bool = false) {
        if !preservingFrame { hasPresentedFrame = false }
        clockAdvanced = false
        stalledFor = nil
        previousSample = nil
        lastProgressAt = nil
    }

    mutating func update(_ sample: Sample, intent: Intent = .play) -> State {
        guard intent == .play else {
            reset(preservingFrame: true)
            return intent == .seek ? .buffering : .paused
        }

        let firstFrame = sample.presentationReady && !hasPresentedFrame
        hasPresentedFrame = hasPresentedFrame || sample.presentationReady
        clockAdvanced = false

        if let previousSample {
            let elapsed = sample.uptime - previousSample.uptime
            let advance = sample.position - previousSample.position
            if elapsed > 0, advance.isFinite {
                // A seek or playlist timestamp discontinuity is not playback.
                if advance < 0 || advance > max(1, elapsed * 2) {
                    lastProgressAt = nil
                } else {
                    clockAdvanced = sample.presentationReady && advance > 0.001
                }
            } else if elapsed < 0 {
                lastProgressAt = nil
            }
        }
        previousSample = sample

        if clockAdvanced || (firstFrame && sample.transport == .playing) {
            lastProgressAt = sample.uptime
        }
        stalledFor = lastProgressAt.map { max(0, sample.uptime - $0) }

        guard hasPresentedFrame else { return .loading }
        if sample.presentationReady,
           let stalledFor, stalledFor < Self.stallGrace {
            return .playing
        }
        return .buffering
    }
}
#endif
