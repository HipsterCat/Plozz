#if os(tvOS)
import SwiftUI
import UIKit
import FeatureHome

/// Resolves the actual focusable control containing a row's label, rather than
/// asking SwiftUI to focus a non-focusable layout/binding container.
struct NavigationRowFocusRequester: UIViewRepresentable {
    let request: Int?
    let onFocused: (Int) -> Void

    func makeUIView(context: Context) -> RequestView {
        let view = RequestView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: RequestView, context: Context) {
        uiView.onFocused = onFocused
        uiView.request = request
    }

    static func dismantleUIView(_ uiView: RequestView, coordinator: ()) {
        uiView.request = nil
        uiView.onFocused = nil
    }

    final class RequestView: UIView {
        var onFocused: ((Int) -> Void)?
        var request: Int? {
            didSet {
                if request != oldValue { scheduleFocus() }
            }
        }
        private var pending: Task<Void, Never>?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleFocus()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleFocus()
        }

        private func scheduleFocus() {
            pending?.cancel()
            guard let request, window != nil, !bounds.isEmpty else { return }
            pending = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, self.request == request,
                      let window = self.window,
                      let system = UIFocusSystem.focusSystem(for: window) else { return }
                guard let target = NavigationRowFocusRequester.target(for: self, in: window) else {
                    HeroFocusDiagnostics.emit("sidebar.native-request no-target token=\(request) bounds=\(self.bounds)")
                    return
                }
                HeroFocusDiagnostics.emit("sidebar.native-request token=\(request) target=\(String(describing: target)) frame=\(target.frame)")
                let didFocus = NavigationRowFocusRequester.handoff(to: target, in: window, using: system)
                HeroFocusDiagnostics.emit("sidebar.native-request result=\(didFocus) focused=\(String(describing: system.focusedItem))")
                if didFocus, self.request == request {
                    self.request = nil
                    self.onFocused?(request)
                }
            }
        }

        deinit { pending?.cancel() }
    }

    static func handoff(
        to target: any UIFocusItem,
        in window: UIWindow,
        using system: any NavigationFocusUpdating
    ) -> Bool {
        system.requestFocusUpdate(to: target)
        // Native Search retains focus across its presentation boundary.
        // Re-evaluate from their shared window, whose preferred rail row is the
        // requested destination, rather than only the leaf item.
        system.requestFocusUpdate(to: window)
        system.updateFocusIfNeeded()
        return system.focusedItem === target
    }

    static func target(
        for marker: UIView,
        in root: any UIFocusItemContainer
    ) -> (any UIFocusItem)? {
        guard !marker.bounds.isEmpty else { return nil }
        var containers: [any UIFocusItemContainer] = [root]
        var seen = Set<ObjectIdentifier>()
        var best: (item: any UIFocusItem, area: CGFloat)?
        let coordinates: any UICoordinateSpace = marker
        while let container = containers.popLast() {
            guard seen.insert(ObjectIdentifier(container)).inserted else { continue }
            let query = container.coordinateSpace.convert(marker.bounds, from: marker)
            for item in container.focusItems(in: query) {
                if let children = item.focusItemContainer { containers.append(children) }
                guard item.canBecomeFocused else { continue }
                let frame = coordinates.convert(item.frame, from: container.coordinateSpace)
                guard !frame.isEmpty, !frame.isInfinite, !frame.isNull,
                      frame.insetBy(dx: -0.5, dy: -0.5).contains(marker.bounds) else { continue }
                let area = frame.width * frame.height
                if let best, area >= best.area { continue }
                best = (item, area)
            }
        }
        return best?.item
    }
}

@MainActor
protocol NavigationFocusUpdating: AnyObject {
    var focusedItem: (any UIFocusItem)? { get }
    func requestFocusUpdate(to environment: any UIFocusEnvironment)
    func updateFocusIfNeeded()
}

extension UIFocusSystem: NavigationFocusUpdating {}

#endif
