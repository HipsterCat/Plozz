import SwiftUI

#if os(tvOS) && canImport(UIKit)
import UIKit

/// Prevents a short Back press from leaving the app while focus is in
/// navigation chrome, leaving Home and held Back presses to the system.
public struct TVNavigationExitProtection: UIViewRepresentable {
    private let isEnabled: Bool
    private let navigationHasFocus: Bool?

    /// Leave `navigationHasFocus` nil for native TabView chrome; custom navigation
    /// supplies its own focus state.
    public init(isEnabled: Bool, navigationHasFocus: Bool? = nil) {
        self.isEnabled = isEnabled
        self.navigationHasFocus = navigationHasFocus
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> UIView {
        let view = TVNavigationExitProtectionMarkerView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.move(to: window)
        }
        context.coordinator.update(
            isEnabled: isEnabled,
            navigationHasFocus: navigationHasFocus,
            window: view.window
        )
        return view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(
            isEnabled: isEnabled,
            navigationHasFocus: navigationHasFocus,
            window: uiView.window
        )
    }

    public static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        (uiView as? TVNavigationExitProtectionMarkerView)?.windowDidChange = nil
        coordinator.detach()
    }

    @MainActor
    public final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var guardedWindow: UIWindow?
        private var recognizer: TVShortMenuPressGestureRecognizer?
        private var isEnabled = false
        private var navigationHasFocus: Bool?

        func update(
            isEnabled: Bool,
            navigationHasFocus: Bool? = nil,
            window: UIWindow?
        ) {
            self.isEnabled = isEnabled
            self.navigationHasFocus = navigationHasFocus
            move(to: window)
        }

        func move(to window: UIWindow?) {
            guard let window else {
                detach()
                return
            }
            if window !== guardedWindow {
                detach()

                let recognizer = TVShortMenuPressGestureRecognizer(
                    target: self,
                    action: #selector(swallowBack)
                )
                recognizer.allowedPressTypes = [
                    NSNumber(value: UIPress.PressType.menu.rawValue)
                ]
                recognizer.delegate = self
                recognizer.name = "Plozz navigation exit protection"
                window.addGestureRecognizer(recognizer)

                guardedWindow = window
                self.recognizer = recognizer
            }

            recognizer?.isEnabled = isEnabled && navigationHasFocus != false
        }

        func detach() {
            if let recognizer {
                guardedWindow?.removeGestureRecognizer(recognizer)
            }
            guardedWindow = nil
            recognizer = nil
        }

        @objc private func swallowBack() {}

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive press: UIPress
        ) -> Bool {
            press.type == .menu && shouldProtectExit
        }

        public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            shouldProtectExit
        }

        private var shouldProtectExit: Bool {
            guard isEnabled, navigationHasFocus != false, let guardedWindow else { return false }
            if navigationHasFocus == true {
                return TVNavigationExitProtectionFocus.isFocusedInUnpresentedRoot(of: guardedWindow)
            }
            return TVNavigationExitProtectionFocus.isFocusedInRootNavigation(
                of: guardedWindow
            )
        }
    }
}

@MainActor
final class TVNavigationExitProtectionMarkerView: UIView {
    var windowDidChange: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        windowDidChange?(window)
    }
}

@MainActor
final class TVShortMenuPressGestureRecognizer: UIGestureRecognizer {
    static let maximumDuration: TimeInterval = 0.45

    private var trackedPress: UIPress?
    private var beganAt: TimeInterval?
    private var timeout: DispatchWorkItem?

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        guard state == .possible,
              presses.count == 1,
              let press = presses.first,
              press.type == .menu
        else {
            state = .failed
            return
        }

        trackedPress = press
        beganAt = press.timestamp

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.state == .possible else { return }
            self.state = .failed
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.maximumDuration,
            execute: timeout
        )
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent) {}

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        guard state == .possible,
              let trackedPress,
              presses.contains(where: { $0 === trackedPress }),
              let beganAt,
              trackedPress.timestamp - beganAt <= Self.maximumDuration
        else {
            state = .failed
            return
        }
        state = .recognized
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        state = .failed
    }

    override func reset() {
        timeout?.cancel()
        timeout = nil
        trackedPress = nil
        beganAt = nil
        super.reset()
    }
}

@MainActor
enum TVNavigationExitProtectionFocus {
    static func isFocusedInUnpresentedRoot(of window: UIWindow) -> Bool {
        guard let focusedView = UIFocusSystem.focusSystem(for: window)?.focusedItem as? UIView
        else { return false }
        return isUnpresentedRootView(focusedView, in: window)
    }

    static func isUnpresentedRootView(_ focusedView: UIView, in window: UIWindow) -> Bool {
        guard focusedView.window === window,
              !isTextInput(focusedView),
              let root = window.rootViewController,
              focusedView.isDescendant(of: root.view)
        else { return false }
        return !descendants(of: root).contains { $0.presentedViewController != nil }
    }

    static func isFocusedInRootNavigation(of window: UIWindow) -> Bool {
        guard let focusedView = UIFocusSystem.focusSystem(for: window)?.focusedItem as? UIView
        else { return false }
        return isRootNavigationView(focusedView, in: window)
    }

    static func isRootNavigationView(_ focusedView: UIView, in window: UIWindow) -> Bool {
        guard isUnpresentedRootView(focusedView, in: window),
              let rootViewController = window.rootViewController
        else { return false }

        let tabControllers = descendants(of: rootViewController)
            .compactMap { $0 as? UITabBarController }

        for tabController in tabControllers.reversed()
        where focusedView.isDescendant(of: tabController.view) {
            guard !selectedContentContains(focusedView, in: tabController),
                  !selectedContentHasPushedDetail(in: tabController)
            else { return false }

            if focusedView.isDescendant(of: tabController.tabBar) {
                return true
            }

            guard let owner = nearestViewController(of: focusedView),
                  let navigationChild = directChild(of: tabController, containing: owner),
                  !(tabController.viewControllers ?? []).contains(where: { $0 === navigationChild }),
                  focusedView.isDescendant(of: navigationChild.view)
            else { return false }

            return true
        }

        return false
    }

    private static func isTextInput(_ focusedView: UIView) -> Bool {
        var view: UIView? = focusedView
        while let current = view {
            if current is any UITextInput || current is UISearchBar {
                return true
            }
            view = current.superview
        }
        return false
    }

    private static func selectedContentContains(
        _ focusedView: UIView,
        in tabController: UITabBarController
    ) -> Bool {
        guard let selected = tabController.selectedViewController else { return false }
        return focusedView === selected.view || focusedView.isDescendant(of: selected.view)
    }

    private static func selectedContentHasPushedDetail(
        in tabController: UITabBarController
    ) -> Bool {
        guard let selected = tabController.selectedViewController else { return false }
        return descendants(of: selected).contains {
            ($0 as? UINavigationController)?.viewControllers.count ?? 0 > 1
        }
    }

    private static func nearestViewController(of view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }

    private static func directChild(
        of ancestor: UIViewController,
        containing descendant: UIViewController
    ) -> UIViewController? {
        var current = descendant
        while let parent = current.parent {
            if parent === ancestor {
                return current
            }
            current = parent
        }
        return nil
    }

    private static func descendants(
        of viewController: UIViewController
    ) -> [UIViewController] {
        [viewController] + viewController.children.flatMap(descendants)
    }
}
#endif

public extension View {
    /// Keeps short Back presses in navigation chrome from exiting the app.
    /// Custom navigation passes its focus state; nil detects native TabView chrome.
    func tvNavigationExitProtection(
        isEnabled: Bool,
        navigationHasFocus: Bool? = nil
    ) -> some View {
#if os(tvOS) && canImport(UIKit)
        background(
            TVNavigationExitProtection(
                isEnabled: isEnabled,
                navigationHasFocus: navigationHasFocus
            )
                .frame(width: 0, height: 0)
        )
#else
        self
#endif
    }
}
