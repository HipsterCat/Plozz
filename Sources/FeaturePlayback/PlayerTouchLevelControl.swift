#if os(iOS)
import AVFAudio
import MediaPlayer
import SwiftUI
import UIKit

/// Owns device adjustments for one playback presentation, never an arbitrary key window.
@MainActor
final class PlayerTouchLevelControl {
    enum Failure: Error { case unavailable }

    private let volumeView = MPVolumeView(frame: CGRect(x: -200, y: 0, width: 160, height: 44))
    private weak var screen: UIScreen?
    private var originalBrightness: CGFloat?
    private var lastBrightness: CGFloat?
    private let readBrightness: (UIScreen) -> CGFloat
    private let writeBrightness: (UIScreen, CGFloat) -> Void

    init(
        readBrightness: @escaping (UIScreen) -> CGFloat = { $0.brightness },
        writeBrightness: @escaping (UIScreen, CGFloat) -> Void = { $0.brightness = $1 }
    ) {
        self.readBrightness = readBrightness
        self.writeBrightness = writeBrightness
        volumeView.alpha = 0.001
        volumeView.isUserInteractionEnabled = false
        volumeView.accessibilityElementsHidden = true
    }

    func begin(_ kind: PlayerTouchLevel, in view: UIView) throws -> Double {
        guard let screen = view.window?.windowScene?.screen else { throw Failure.unavailable }
        endVolume()
        switch kind {
        case .brightness:
            return Double(readBrightness(screen))
        case .volume:
            // iOS has no direct system-volume setter. Drive the native volume control
            // only during a user swipe; removing it restores the hardware-button HUD.
            view.addSubview(volumeView)
            volumeView.layoutIfNeeded()
            guard volumeSlider != nil else {
                endVolume()
                throw Failure.unavailable
            }
            return Double(AVAudioSession.sharedInstance().outputVolume)
        }
    }

    func set(_ kind: PlayerTouchLevel, value: Double, in view: UIView) throws {
        guard value.isFinite else { throw Failure.unavailable }
        let value = min(max(value, 0), 1)
        switch kind {
        case .brightness:
            guard let currentScreen = view.window?.windowScene?.screen else { throw Failure.unavailable }
            if screen !== currentScreen {
                restoreBrightness()
                screen = currentScreen
                originalBrightness = readBrightness(currentScreen)
            }
            writeBrightness(currentScreen, CGFloat(value))
            lastBrightness = CGFloat(value)
        case .volume:
            guard let slider = volumeSlider else { throw Failure.unavailable }
            slider.setValue(Float(value), animated: false)
            slider.sendActions(for: .valueChanged)
        }
    }

    private var volumeSlider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first { $0.isEnabled }
    }

    func endVolume() {
        volumeView.removeFromSuperview()
    }

    func deactivate() {
        endVolume()
        restoreBrightness()
    }

    private func restoreBrightness() {
        if let screen, let originalBrightness, let lastBrightness,
           abs(readBrightness(screen) - lastBrightness) < 0.001 {
            writeBrightness(screen, originalBrightness)
        }
        screen = nil
        originalBrightness = nil
        lastBrightness = nil
    }
}

private struct PlayerTouchLevelControlKey: EnvironmentKey {
    static let defaultValue: PlayerTouchLevelControl? = nil
}

extension EnvironmentValues {
    var playerTouchLevelControl: PlayerTouchLevelControl? {
        get { self[PlayerTouchLevelControlKey.self] }
        set { self[PlayerTouchLevelControlKey.self] = newValue }
    }
}

private struct PlayerTouchLevelSession: ViewModifier {
    let isActive: Bool
    @State private var control = PlayerTouchLevelControl()
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .environment(\.playerTouchLevelControl, control)
            .onChange(of: isActive) { _, active in
                if !active { control.deactivate() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { control.deactivate() }
            }
            .onDisappear { control.deactivate() }
    }
}

public extension View {
    /// Keep brightness through episode/engine handoffs, restoring it when playback leaves the screen.
    func playerTouchLevelSession(isActive: Bool = true) -> some View {
        modifier(PlayerTouchLevelSession(isActive: isActive))
    }
}
#endif
