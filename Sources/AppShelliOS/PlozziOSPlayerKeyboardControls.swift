#if os(iOS)
import FeaturePlayback
import SwiftUI
import UIKit

@MainActor
@Observable
final class PlozziOSPlayerKeyboardActions {
    var isEnabled = true
    var canSeek = false
    @ObservationIgnored var skip: ((PlayerTouchSkipDirection) -> Void)?
    @ObservationIgnored var playPause: (() -> Void)?

    func clear() {
        canSeek = false
        skip = nil
        playPause = nil
    }
}

struct PlozziOSPlayerKeyboardControls: UIViewControllerRepresentable {
    let isEnabled: Bool
    let canSeek: Bool
    let onSkip: (PlayerTouchSkipDirection) -> Void
    let onPlayPause: () -> Void

    func makeUIViewController(context: Context) -> KeyboardViewController { KeyboardViewController() }

    func updateUIViewController(_ controller: KeyboardViewController, context: Context) {
        controller.isEnabled = isEnabled
        controller.canSeek = canSeek
        controller.onSkip = onSkip
        controller.onPlayPause = onPlayPause
        controller.updateResponder()
    }

    static func dismantleUIViewController(_ controller: KeyboardViewController, coordinator: ()) {
        controller.isEnabled = false
        controller.resignFirstResponder()
        controller.onSkip = nil
        controller.onPlayPause = nil
    }

    final class KeyboardViewController: UIViewController {
        var isEnabled = false
        var canSeek = false
        var onSkip: ((PlayerTouchSkipDirection) -> Void)?
        var onPlayPause: (() -> Void)?

        override var canBecomeFirstResponder: Bool { isEnabled }

        override func viewDidLoad() {
            super.viewDidLoad()
            for input in [" ", UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow] {
                let command = UIKeyCommand(input: input, modifierFlags: [], action: #selector(handleKey(_:)))
                command.wantsPriorityOverSystemBehavior = true
                addKeyCommand(command)
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateResponder()
        }

        func updateResponder() {
            if isEnabled, viewIfLoaded?.window != nil, !isFirstResponder {
                becomeFirstResponder()
            } else if !isEnabled, isFirstResponder {
                resignFirstResponder()
            }
        }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            if action == #selector(handleKey(_:)), let command = sender as? UIKeyCommand {
                return isEnabled && (command.input == " " || canSeek)
            }
            return super.canPerformAction(action, withSender: sender)
        }

        @objc private func handleKey(_ command: UIKeyCommand) {
            guard isEnabled else { return }
            switch command.input {
            case " ": onPlayPause?()
            case UIKeyCommand.inputLeftArrow where canSeek: onSkip?(.backward)
            case UIKeyCommand.inputRightArrow where canSeek: onSkip?(.forward)
            default: break
            }
        }
    }
}
#endif
