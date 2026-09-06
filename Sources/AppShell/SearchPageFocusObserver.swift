#if os(tvOS)
import SwiftUI
import UIKit

/// Native Search's keyboard does not report focus through SwiftUI FocusState.
/// Observe UIKit inside the page's actual bounds, excluding its header capsule.
struct SearchPageFocusObserver: UIViewRepresentable {
    let isEnabled: Bool
    let onFocusEntered: () -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        uiView.onFocusEntered = onFocusEntered
        uiView.isEnabled = isEnabled
    }

    static func dismantleUIView(_ uiView: ObserverView, coordinator: ()) {
        uiView.stop()
    }

    final class ObserverView: UIView {
        var onFocusEntered: (() -> Void)?
        var isEnabled = false {
            didSet {
                if oldValue != isEnabled { updateObservation() }
            }
        }
        private var pendingFocusCheck: Task<Void, Never>?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateObservation()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleCurrentFocusCheck()
        }

        func stop() {
            isEnabled = false
            onFocusEntered = nil
        }

        private func updateObservation() {
            NotificationCenter.default.removeObserver(self)
            pendingFocusCheck?.cancel()
            guard isEnabled, window != nil else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(focusDidUpdate(_:)),
                name: UIFocusSystem.didUpdateNotification,
                object: nil
            )
            scheduleCurrentFocusCheck()
        }

        private func scheduleCurrentFocusCheck() {
            pendingFocusCheck?.cancel()
            guard isEnabled, window != nil else { return }
            pendingFocusCheck = Task { @MainActor [weak self] in
                // Layout and representable updates must finish before notifying SwiftUI.
                await Task.yield()
                guard !Task.isCancelled, let self, let window = self.window else { return }
                self.reportFocus(UIFocusSystem(for: window)?.focusedItem)
            }
        }

        @objc private func focusDidUpdate(_ notification: Notification) {
            guard let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey]
                    as? UIFocusUpdateContext else { return }
            reportFocus(context.nextFocusedItem)
        }

        func reportFocus(_ item: (any UIFocusItem)?) {
            guard isEnabled, containsFocus(item) else { return }
            isEnabled = false
            onFocusEntered?()
        }

        func containsFocus(_ item: (any UIFocusItem)?) -> Bool {
            guard let window, let item, item.canBecomeFocused, !bounds.isEmpty else { return false }
            let frame: CGRect
            if let view = item as? UIView {
                guard view.window === window else { return false }
                frame = view.convert(view.bounds, to: self)
            } else {
                // Keyboard keys and SwiftUI buttons can be virtual focus items.
                // Their frames belong to the nearest containing focus environment.
                var parent = item.parentFocusEnvironment
                var container: (any UIFocusItemContainer)?
                while let environment = parent {
                    if let view = environment as? UIView, view.window !== window { return false }
                    if let candidate = environment.focusItemContainer {
                        container = candidate
                        break
                    }
                    parent = environment.parentFocusEnvironment
                }
                guard let container else { return false }
                let coordinates: any UICoordinateSpace = self
                frame = coordinates.convert(item.frame, from: container.coordinateSpace)
            }
            guard !frame.isEmpty, !frame.isInfinite, !frame.isNull else { return false }
            return bounds.contains(CGPoint(x: frame.midX, y: frame.midY))
        }

        deinit {
            pendingFocusCheck?.cancel()
            NotificationCenter.default.removeObserver(self)
        }
    }
}
#endif
