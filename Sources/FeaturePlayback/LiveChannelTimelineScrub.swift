import Foundation

/// A horizontal swipe through a live channel's rewind window, as VOD's scrub
/// surface does it: the playhead follows the finger (`preview`) and the seek is
/// made once, where it lifts (`commit`).
///
/// Kept free of UIKit so the axis lock and the seconds mapping are testable;
/// `LiveChannelTimelineScrubPan` feeds it the Siri Remote's pan samples.
struct LiveChannelTimelineScrub {
    /// Seconds behind live the scrub is showing; nil when not scrubbing.
    private(set) var behindLive: TimeInterval?
    private var startBehind: TimeInterval = 0
    private var lastTranslationX: Double = 0
    private var axis: Axis = .undecided

    enum Axis { case undecided, horizontal, vertical }

    /// Travel before the swipe commits to an axis, so a vertical swipe to the
    /// tabs never nudges the playhead on its way.
    static let axisLockDistance: Double = 24

    mutating func begin(behindLive current: TimeInterval) {
        startBehind = max(0, current)
        lastTranslationX = 0
        axis = .undecided
        behindLive = nil
    }

    /// One pan sample. Right moves toward live (less behind).
    mutating func change(
        translationX: Double, translationY: Double, speed: Double, windowSeconds: TimeInterval
    ) {
        if axis == .undecided {
            guard max(abs(translationX), abs(translationY)) >= Self.axisLockDistance else { return }
            axis = abs(translationX) > abs(translationY) * 1.2 ? .horizontal : .vertical
            if axis == .horizontal {
                behindLive = startBehind
                lastTranslationX = translationX
            }
        }
        guard axis == .horizontal, let current = behindLive else { return }
        let dx = translationX - lastTranslationX
        lastTranslationX = translationX
        let delta = ScrubGeometry.scrubDeltaSeconds(
            translationDeltaPoints: dx, speedPointsPerSecond: speed,
            tuning: Self.tuning(windowSeconds: windowSeconds)
        )
        behindLive = min(max(current - delta, 0), max(0, windowSeconds))
    }

    /// The scrub's landing, or nil if the swipe never became one.
    mutating func end() -> TimeInterval? {
        defer { behindLive = nil; axis = .undecided }
        return behindLive
    }

    mutating func cancel() {
        behindLive = nil
        axis = .undecided
    }

    /// VOD's transfer function, scaled to the window rather than a runtime, so a
    /// swipe covers the same share of the bar whatever the window's depth.
    static func tuning(windowSeconds: TimeInterval) -> ScrubGeometry.Tuning {
        let scale = min(max(windowSeconds / 7_200, 0.05), 1.6)
        return ScrubGeometry.Tuning(
            baseSecondsPerPoint: 0.18 * scale,
            accelOnsetSpeed: 500,
            accelSaturationSpeed: 3_500,
            maxAccelMultiplier: 5
        )
    }
}

#if os(tvOS)
import SwiftUI
import UIKit

/// The Siri Remote's touch surface while the timeline holds focus. Watches the
/// window like `LiveChannelRemotePresses`, without consuming or redirecting any
/// other input: focus still moves on a vertical swipe.
struct LiveChannelTimelineScrubPan: UIViewRepresentable {
    let isEnabled: Bool
    let began: () -> Void
    let changed: (_ translation: CGPoint, _ speed: Double) -> Void
    let ended: (_ committed: Bool) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        update(view)
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) { update(view) }

    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.detach() }

    private func update(_ view: ObserverView) {
        view.isEnabled = isEnabled
        view.began = began
        view.changed = changed
        view.ended = ended
    }

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var isEnabled = false {
            didSet { if !isEnabled, oldValue { recognizer?.isEnabled = false; recognizer?.isEnabled = true } }
        }
        var began: (() -> Void)?
        var changed: ((CGPoint, Double) -> Void)?
        var ended: ((Bool) -> Void)?
        private var recognizer: UIPanGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            pan.cancelsTouchesInView = false
            pan.delegate = self
            window.addGestureRecognizer(pan)
            recognizer = pan
        }

        func detach() {
            recognizer.map { $0.view?.removeGestureRecognizer($0) }
            recognizer = nil
        }

        @objc private func pan(_ gesture: UIPanGestureRecognizer) {
            guard isEnabled else { return }
            switch gesture.state {
            case .began:
                began?()
            case .changed:
                changed?(gesture.translation(in: gesture.view), Double(abs(gesture.velocity(in: gesture.view).x)))
            case .ended:
                changed?(gesture.translation(in: gesture.view), Double(abs(gesture.velocity(in: gesture.view).x)))
                ended?(true)
            case .cancelled, .failed:
                ended?(false)
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { isEnabled }
    }
}
#endif
