import Foundation

struct LiveChannelRetuneBudget {
    static let healthyPlaybackDuration: TimeInterval = 300
    private static let maximumProgressGap: TimeInterval = 5

    private struct HealthyPlayback {
        let started: TimeInterval
        var sampled: TimeInterval
        var advanced: TimeInterval
        var position: TimeInterval
    }

    private(set) var attempts = 0
    private var lastAttempt: TimeInterval?
    private var healthyPlayback: HealthyPlayback?

    var isExhausted: Bool { attempts >= 3 }

    func delayBeforeNextAttempt(uptime: TimeInterval) -> TimeInterval {
        guard let lastAttempt else { return 0 }
        return max(0, lastAttempt + 20 - uptime)
    }

    mutating func recordAttempt(uptime: TimeInterval) {
        interruptHealthyPlayback()
        attempts += 1
        lastAttempt = uptime
    }

    mutating func interruptHealthyPlayback() {
        healthyPlayback = nil
    }

    mutating func observeHealthyPlayback(position: TimeInterval, uptime: TimeInterval) {
        guard attempts > 0, position.isFinite, uptime.isFinite else {
            interruptHealthyPlayback()
            return
        }
        guard var healthy = healthyPlayback,
              uptime >= healthy.sampled,
              uptime - healthy.sampled <= Self.maximumProgressGap,
              uptime - healthy.advanced <= Self.maximumProgressGap,
              position >= healthy.position else {
            healthyPlayback = HealthyPlayback(started: uptime, sampled: uptime, advanced: uptime, position: position)
            return
        }
        healthy.sampled = uptime
        if position > healthy.position {
            healthy.position = position
            healthy.advanced = uptime
            if uptime - healthy.started >= Self.healthyPlaybackDuration {
                attempts = 0
                interruptHealthyPlayback()
                return
            }
        }
        healthyPlayback = healthy
    }
}
