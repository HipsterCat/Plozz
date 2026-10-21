import Foundation
import Observation

public enum PlayerTouchSkipDirection: Equatable, Sendable {
    case backward, forward
}

public struct PlayerTouchSkipFeedback: Equatable, Sendable {
    public let seconds: TimeInterval
    public let target: TimeInterval
    public let pulse: Int

    public var direction: PlayerTouchSkipDirection { seconds < 0 ? .backward : .forward }
}

public enum PlayerTouchLevel: Equatable, Sendable {
    case brightness, volume

    func systemImage(at value: Double) -> String {
        guard self == .volume else { return "sun.max.fill" }
        if value <= 0 { return "speaker.slash.fill" }
        if value < 1.0 / 3 { return "speaker.wave.1.fill" }
        if value < 2.0 / 3 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

public struct PlayerTouchLevelFeedback: Equatable, Sendable {
    public let kind: PlayerTouchLevel
    /// Nil means this output cannot currently be adjusted.
    public let value: Double?
    /// Points dragged past a limit: positive above full, negative below zero.
    public let overshoot: Double
    public let isDragging: Bool
    public let isDirectInteraction: Bool
}

struct PlayerTouchLevelDrag {
    enum Feedback {
        case step, limit
    }

    let kind: PlayerTouchLevel
    let startValue: Double
    let height: Double
    private var lastAppliedValue: Double
    private var lastFeedbackValue: Double

    init(kind: PlayerTouchLevel, startValue: Double, height: Double, initialFeedbackValue: Double? = nil) {
        self.kind = kind
        self.startValue = startValue
        self.height = height
        lastAppliedValue = initialFeedbackValue ?? startValue
        lastFeedbackValue = lastAppliedValue
    }

    static func kind(at x: Double, width: Double) -> PlayerTouchLevel? {
        guard x.isFinite, width.isFinite, width > 0, x >= 0, x <= width else { return nil }
        if x < width * 0.3 { return .brightness }
        if x > width * 0.7 { return .volume }
        return nil
    }

    func adjustment(translationY: Double) -> (value: Double, overshoot: Double)? {
        guard translationY.isFinite, startValue.isFinite, height.isFinite, height > 0 else { return nil }
        let proposed = startValue - translationY / height
        let value = min(max(proposed, 0), 1)
        let overshoot = (proposed - value) * height
        guard proposed.isFinite, overshoot.isFinite else { return nil }
        return (value, overshoot)
    }

    mutating func feedback(afterApplying value: Double) -> Feedback? {
        let previous = lastAppliedValue
        lastAppliedValue = value
        guard value != previous else { return nil }
        if value == 0 || value == 1 {
            lastFeedbackValue = value
            return .limit
        }
        // Measure from the last tick so small reversals around a boundary cannot buzz.
        guard abs(value - lastFeedbackValue) >= 0.05 else { return nil }
        lastFeedbackValue = value
        return .step
    }
}

/// Keeps rapid taps relative to the requested position, not a lagging playback clock.
@MainActor
@Observable
public final class PlayerTouchGestureState {
    public private(set) var skip: PlayerTouchSkipFeedback?
    public private(set) var boostRate: Double?
    public var isPinching = false
    public private(set) var level: PlayerTouchLevelFeedback?
    @ObservationIgnored var levelInteractionRegion: (kind: PlayerTouchLevel, frame: CGRect)?
    private var feedbackTask: Task<Void, Never>?
    private var levelFeedbackTask: Task<Void, Never>?
    private var pulse = 0

    public init() {}

    public var isActive: Bool { skip != nil || boostRate != nil || isPinching || level != nil }

    public func showLevel(
        _ kind: PlayerTouchLevel, value: Double?, overshoot: Double = 0, isDirectInteraction: Bool = false
    ) {
        clearSkip()
        clearLevel()
        level = PlayerTouchLevelFeedback(
            kind: kind, value: value, overshoot: overshoot, isDragging: true, isDirectInteraction: isDirectInteraction
        )
    }

    public func finishLevel() {
        guard let level, levelFeedbackTask == nil else { return }
        self.level = PlayerTouchLevelFeedback(
            kind: level.kind, value: level.value, overshoot: 0, isDragging: false, isDirectInteraction: false
        )
        levelFeedbackTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(1200)) }
            catch { return }
            self?.level = nil
            self?.levelFeedbackTask = nil
        }
    }

    public func clearLevel() {
        levelFeedbackTask?.cancel()
        levelFeedbackTask = nil
        level = nil
    }

    public func seek(
        by interval: TimeInterval,
        from position: TimeInterval,
        within range: ClosedRange<TimeInterval>
    ) -> TimeInterval? {
        guard interval.isFinite, interval != 0, position.isFinite,
              range.lowerBound.isFinite, range.upperBound.isFinite else { return nil }
        let start = min(max(skip?.target ?? position, range.lowerBound), range.upperBound)
        let target = min(max(start + interval, range.lowerBound), range.upperBound)
        let delta = target - start
        guard delta != 0 else { return nil }
        clearLevel()
        let previous = skip?.seconds ?? 0
        let accumulated = previous.sign == delta.sign ? previous + delta : delta
        pulse &+= 1
        skip = PlayerTouchSkipFeedback(seconds: accumulated, target: target, pulse: pulse)
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(1200)) }
            catch { return }
            self?.skip = nil
            self?.feedbackTask = nil
        }
        return target
    }

    public func showBoost(rate: Double?) {
        clearSkip()
        if rate != nil { clearLevel() }
        boostRate = rate
    }

    public func clearSkip() {
        feedbackTask?.cancel()
        feedbackTask = nil
        skip = nil
    }

    public func cancel() {
        clearSkip()
        clearLevel()
        boostRate = nil
        isPinching = false
    }
}
