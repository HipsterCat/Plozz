#if DEBUG && os(tvOS)
import SwiftUI
import UIKit

/// Observes the presented HUD's native input without changing focus or consuming presses.
struct LiveChannelFocusActivityObserver: UIViewRepresentable {
    let onActivity: () -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        uiView.onActivity = onActivity
    }

    static func dismantleUIView(_ uiView: ObserverView, coordinator: ()) {
        uiView.stop()
    }

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var onActivity: (() -> Void)?
        private weak var observedWindow: UIWindow?
        private var pressObserver: UITapGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detachObservers()
            guard let window else { return }
            observedWindow = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(focusDidUpdate(_:)),
                name: UIFocusSystem.didUpdateNotification,
                object: nil
            )
            let presses = UITapGestureRecognizer()
            presses.allowedPressTypes = [
                UIPress.PressType.leftArrow, .rightArrow, .upArrow, .downArrow
            ].map { NSNumber(value: $0.rawValue) }
            presses.allowedTouchTypes = []
            presses.cancelsTouchesInView = false
            presses.delaysTouchesBegan = false
            presses.delaysTouchesEnded = false
            presses.delegate = self
            window.addGestureRecognizer(presses)
            pressObserver = presses
        }

        func stop() {
            detachObservers()
            onActivity = nil
        }

        private func detachObservers() {
            NotificationCenter.default.removeObserver(self)
            if let pressObserver { observedWindow?.removeGestureRecognizer(pressObserver) }
            pressObserver = nil
            observedWindow = nil
        }

        @objc private func focusDidUpdate(_ notification: Notification) {
            guard let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey]
                    as? UIFocusUpdateContext else { return }
            reportActivity(for: context.nextFocusedItem)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
            guard gestureRecognizer === pressObserver else { return false }
            let item = window.flatMap { UIFocusSystem.focusSystem(for: $0)?.focusedItem }
            return observePress(press.type, focusedItem: item)
        }

        func observePress(_ type: UIPress.PressType, focusedItem: (any UIFocusItem)?) -> Bool {
            switch type {
            case .leftArrow, .rightArrow, .upArrow, .downArrow:
                reportActivity(for: focusedItem)
            default: break
            }
            // Receiving an arrow at the end of a row is still activity. Reject
            // recognition so UIKit alone performs navigation and press replay.
            return false
        }

        func reportActivity(for item: (any UIFocusItem)?) {
            guard contains(item) else { return }
            onActivity?()
        }

        func contains(_ item: (any UIFocusItem)?) -> Bool {
            guard let window, let item, item.canBecomeFocused, !bounds.isEmpty else { return false }
            let frame: CGRect
            if let view = item as? UIView {
                guard view.window === window else { return false }
                frame = view.convert(view.bounds, to: self)
            } else {
                var environment = item.parentFocusEnvironment
                var container: (any UIFocusItemContainer)?
                while let current = environment {
                    if let view = current as? UIView, view.window !== window { return false }
                    if container == nil { container = current.focusItemContainer }
                    environment = current.parentFocusEnvironment
                }
                guard let container else { return false }
                let coordinates: any UICoordinateSpace = self
                frame = coordinates.convert(item.frame, from: container.coordinateSpace)
            }
            guard !frame.isEmpty, !frame.isNull, !frame.isInfinite else { return false }
            return bounds.contains(CGPoint(x: frame.midX, y: frame.midY))
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            if let pressObserver {
                let window = observedWindow
                Task { @MainActor in window?.removeGestureRecognizer(pressObserver) }
            }
        }
    }
}
#endif
