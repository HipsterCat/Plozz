import Foundation

struct LiveChannelHUDInactivity {
    private(set) var lastInteractionAt: TimeInterval?

    mutating func recordInteraction(at time: TimeInterval) {
        lastInteractionAt = max(lastInteractionAt ?? time, time)
    }

    func remainingDelay(
        startedAt: TimeInterval,
        now: TimeInterval,
        grace: TimeInterval = ControlsAutoHidePolicy.minSinceInput
    ) -> TimeInterval {
        max(0, max(startedAt, lastInteractionAt ?? startedAt) + grace - now)
    }
}
