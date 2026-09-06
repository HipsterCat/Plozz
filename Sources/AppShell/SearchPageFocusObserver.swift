#if os(tvOS)
import SwiftUI
import UIKit
import FeatureHome

/// Native Search's keyboard does not report focus through SwiftUI FocusState.
/// Hand entry to its real controller and acknowledge only that controller's content.
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
                guard !Task.isCancelled, let self, self.isEnabled, let window = self.window,
                      let search = self.searchController(in: window),
                      let system = UIFocusSystem.focusSystem(for: window) else { return }
                if !self.containsFocus(system.focusedItem, in: search.view) {
                    HeroFocusDiagnostics.emit("search.native-entry requesting controller")
                    system.requestFocusUpdate(to: search)
                    system.updateFocusIfNeeded()
                    if !self.containsFocus(system.focusedItem, in: search.view) {
                        system.requestFocusUpdate(to: window)
                        system.updateFocusIfNeeded()
                    }
                }
                self.reportFocus(system.focusedItem, in: search.view)
            }
        }

        @objc private func focusDidUpdate(_ notification: Notification) {
            guard let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey]
                    as? UIFocusUpdateContext else { return }
            reportFocus(context.nextFocusedItem)
            if isEnabled { scheduleCurrentFocusCheck() }
        }

        func reportFocus(_ item: (any UIFocusItem)?, in contentRoot: UIView? = nil) {
            guard isEnabled, containsFocus(item, in: contentRoot) else { return }
            HeroFocusDiagnostics.emit("search.native-entry confirmed item=\(String(describing: item))")
            isEnabled = false
            onFocusEntered?()
        }

        func containsFocus(_ item: (any UIFocusItem)?, in contentRoot: UIView? = nil) -> Bool {
            guard let window, let item, item.canBecomeFocused, !bounds.isEmpty else { return false }
            guard let root = contentRoot ?? searchController(in: window)?.viewIfLoaded,
                  root.window === window else { return false }
            let frame: CGRect
            if let view = item as? UIView {
                guard view.window === window, view.isDescendant(of: root) else { return false }
                frame = view.convert(view.bounds, to: self)
            } else {
                // Keyboard keys and SwiftUI buttons can be virtual focus items.
                // Their frames belong to the nearest containing focus environment.
                var parent = item.parentFocusEnvironment
                var container: (any UIFocusItemContainer)?
                var belongsToSearch = false
                while let environment = parent {
                    if let view = environment as? UIView, view.window !== window { return false }
                    if let view = environment as? UIView, view.isDescendant(of: root) {
                        belongsToSearch = true
                    }
                    if container == nil, let candidate = environment.focusItemContainer {
                        container = candidate
                    }
                    if belongsToSearch, container != nil { break }
                    parent = environment.parentFocusEnvironment
                }
                guard belongsToSearch, let container else { return false }
                let coordinates: any UICoordinateSpace = self
                frame = coordinates.convert(item.frame, from: container.coordinateSpace)
            }
            guard !frame.isEmpty, !frame.isInfinite, !frame.isNull else { return false }
            return bounds.contains(CGPoint(x: frame.midX, y: frame.midY))
        }

        private func searchController(in window: UIWindow) -> UISearchController? {
            var controllers = window.rootViewController.map { [$0] } ?? []
            var seen = Set<ObjectIdentifier>()
            while let controller = controllers.popLast() {
                guard seen.insert(ObjectIdentifier(controller)).inserted else { continue }
                if let search = controller as? UISearchController,
                   let view = search.viewIfLoaded, view.window === window,
                   !view.isHidden, view.convert(view.bounds, to: self).intersects(bounds) {
                    return search
                }
                controllers.append(contentsOf: controller.children)
                if let container = controller as? UISearchContainerViewController {
                    controllers.append(container.searchController)
                }
                if let presented = controller.presentedViewController {
                    controllers.append(presented)
                }
            }
            return nil
        }

        deinit {
            pendingFocusCheck?.cancel()
            NotificationCenter.default.removeObserver(self)
        }
    }
}
#endif
