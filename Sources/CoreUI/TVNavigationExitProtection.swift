import SwiftUI

#if os(tvOS) && canImport(UIKit)
import UIKit

/// Local-only, opt-in tracing for physical-device focus failures.
@MainActor
private enum ExitProtectionDiagnostic {
    static var isEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--trace-navigation-exit")
#else
        false
#endif
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let url = URL.cachesDirectory.appendingPathComponent("navigation-exit-trace.log")
        do {
            if !FileManager.default.fileExists(atPath: url.path),
               !FileManager.default.createFile(atPath: url.path, contents: nil) {
                print("Exit trace: could not create log")
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            defer {
                do { try handle.close() }
                catch { print("Exit trace close failed: \(error)") }
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\(Date().timeIntervalSince1970) \(message())\n".utf8))
        } catch {
            print("Exit trace write failed: \(error)")
        }
    }
}

private enum TVNavigationExitProtectionFocusKey: FocusedValueKey {
    typealias Value = Bool
}

private extension FocusedValues {
    var plozzNavigationHasFocus: Bool? {
        get { self[TVNavigationExitProtectionFocusKey.self] }
        set { self[TVNavigationExitProtectionFocusKey.self] = newValue }
    }
}

private struct TVNavigationExitProtectionModifier: ViewModifier {
    let isEnabled: Bool
    let navigationHasFocus: Bool?
    @FocusedValue(\.plozzNavigationHasFocus) private var nativeNavigationHasFocus

    func body(content: Content) -> some View {
        content
            .focusedValue(\.plozzNavigationHasFocus, true)
            .background(
                TVNavigationExitProtection(
                    isEnabled: isEnabled,
                    navigationHasFocus: navigationHasFocus ?? (nativeNavigationHasFocus == true)
                )
                .frame(width: 0, height: 0)
            )
    }
}

/// Prevents a short Back press from leaving the app while focus is in
/// navigation chrome, leaving Home and held Back presses to the system.
public struct TVNavigationExitProtection: UIViewRepresentable {
    private let isEnabled: Bool
    private let navigationHasFocus: Bool

    public init(isEnabled: Bool, navigationHasFocus: Bool) {
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
        private var diagnosticRecognizer: UITapGestureRecognizer?
        private var isEnabled = false
        private var navigationHasFocus = false

        func update(
            isEnabled: Bool,
            navigationHasFocus: Bool,
            window: UIWindow?
        ) {
            if self.isEnabled != isEnabled || self.navigationHasFocus != navigationHasFocus {
                ExitProtectionDiagnostic.log("scope enabled=\(isEnabled) navigation=\(navigationHasFocus)")
            }
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
                // Recognition waits for release to distinguish a tap from a hold.
                // Keep UIKit from acting on the initial Back press in the meantime.
                recognizer.delaysTouchesBegan = true
                recognizer.delegate = self
                recognizer.name = "Plozz navigation exit protection"
                window.addGestureRecognizer(recognizer)

                guardedWindow = window
                self.recognizer = recognizer
                if ExitProtectionDiagnostic.isEnabled {
                    let diagnostic = UITapGestureRecognizer()
                    diagnostic.allowedPressTypes = recognizer.allowedPressTypes
                    diagnostic.allowedTouchTypes = []
                    diagnostic.name = "Plozz exit diagnostics"
                    diagnostic.delegate = self
                    window.addGestureRecognizer(diagnostic)
                    diagnosticRecognizer = diagnostic
                }
            }

            recognizer?.isEnabled = isEnabled && navigationHasFocus
        }

        func detach() {
            if let diagnosticRecognizer {
                guardedWindow?.removeGestureRecognizer(diagnosticRecognizer)
                self.diagnosticRecognizer = nil
            }
            if let recognizer {
                guardedWindow?.removeGestureRecognizer(recognizer)
            }
            guardedWindow = nil
            recognizer = nil
        }

        @objc private func swallowBack() {
            ExitProtectionDiagnostic.log("CONSUMED")
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive press: UIPress
        ) -> Bool {
            if gestureRecognizer === diagnosticRecognizer {
                ExitProtectionDiagnostic.log("RAW press=\(press.type.rawValue) navigation=\(navigationHasFocus) enabled=\(isEnabled) focus=\(String(describing: guardedWindow.flatMap { UIFocusSystem.focusSystem(for: $0)?.focusedItem }.map { type(of: $0) }))")
                return false
            }
            let result = press.type == .menu && shouldProtectExit
            ExitProtectionDiagnostic.log("receive protect=\(result)")
            return result
        }

        public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let result = shouldProtectExit
            ExitProtectionDiagnostic.log("shouldBegin protect=\(result)")
            return result
        }

        private var shouldProtectExit: Bool {
            guard isEnabled, navigationHasFocus, let guardedWindow else { return false }
            return TVNavigationExitProtectionFocus.isFocusedInUnpresentedRoot(of: guardedWindow)
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
        ExitProtectionDiagnostic.log("began")
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
        ExitProtectionDiagnostic.log("ended state=\(state.rawValue)")
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
        ExitProtectionDiagnostic.log("reset")
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
        guard let item = UIFocusSystem.focusSystem(for: window)?.focusedItem,
              let focusedView = containingView(of: item)
        else { return false }
        return isUnpresentedRootView(focusedView, in: window)
    }

    /// SwiftUI can focus a non-view proxy. Follow its public focus environment
    /// rather than assuming every UIFocusItem is a UIView.
    static func containingView(of item: any UIFocusEnvironment) -> UIView? {
        var environment: (any UIFocusEnvironment)? = item
        var visited = Set<ObjectIdentifier>()
        while let current = environment, visited.insert(ObjectIdentifier(current)).inserted {
            if let view = current as? UIView { return view }
            if let controller = current as? UIViewController { return controller.viewIfLoaded }
            environment = current.parentFocusEnvironment
        }
        return nil
    }

    static func isUnpresentedRootView(_ focusedView: UIView, in window: UIWindow) -> Bool {
        guard focusedView.window === window,
              !isTextInput(focusedView),
              let root = window.rootViewController,
              focusedView.isDescendant(of: root.view)
        else { return false }
        return !descendants(of: root).compactMap(\.presentedViewController).contains {
            blocksNavigation($0, focusedView: focusedView, in: window)
        }
    }

    static func blocksNavigation(
        _ presented: UIViewController,
        focusedView: UIView,
        in window: UIWindow
    ) -> Bool {
        ExitProtectionDiagnostic.log("presentation=\(type(of: presented)) search=\(presented is UISearchController) style=\(presented.modalPresentationStyle.rawValue) inWindow=\(presented.viewIfLoaded?.window === window) fullscreen=\(presented.presentationController?.shouldPresentInFullscreen ?? false)")
        if !(presented is UISearchController), presented.isBeingPresented { return true }
        guard let view = presented.viewIfLoaded, view.window === window else { return false }
        var ancestor: UIView? = view
        while let current = ancestor {
            if current.isHidden || current.alpha == 0 { return false }
            ancestor = current.superview
        }

        // Search can be presented within a tab without covering its navigation
        // chrome. Its keyboard and results retain their own Back handling.
        if presented is UISearchController {
            return focusedView.isDescendant(of: view)
        }
        return true
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

    private static func descendants(
        of viewController: UIViewController
    ) -> [UIViewController] {
        var pending = [viewController]
        var result: [UIViewController] = []
        var visited = Set<ObjectIdentifier>()
        while let current = pending.popLast() {
            guard visited.insert(ObjectIdentifier(current)).inserted else { continue }
            result.append(current)
            pending.append(contentsOf: current.children)
            if let presented = current.presentedViewController {
                pending.append(presented)
            }
        }
        return result
    }
}
#endif

public extension View {
    /// A tab's content overrides the surrounding navigation focus scope, including
    /// any detail pages pushed inside it.
    func tvNavigationExitProtectionContent() -> some View {
#if os(tvOS) && canImport(UIKit)
        focusedValue(\.plozzNavigationHasFocus, false)
#else
        self
#endif
    }

    /// Keeps short Back presses in navigation chrome from exiting the app.
    /// Custom navigation passes its focus state. Native TabView content must use
    /// `tvNavigationExitProtectionContent()` to distinguish it from the chrome.
    func tvNavigationExitProtection(
        isEnabled: Bool,
        navigationHasFocus: Bool? = nil
    ) -> some View {
#if os(tvOS) && canImport(UIKit)
        modifier(
            TVNavigationExitProtectionModifier(
                isEnabled: isEnabled,
                navigationHasFocus: navigationHasFocus
            )
        )
#else
        self
#endif
    }
}
