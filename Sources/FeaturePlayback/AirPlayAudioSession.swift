#if canImport(AVFoundation)
import AVFoundation
import CoreNetworking
import Foundation

/// AirPlay 2 audio for video: a HomePod (or stereo pair) used as the Apple TV's
/// speakers can go silent while `AVPlayer` keeps reporting it is playing, with no
/// interruption, route change or stall to react to (`docs/airplay-audio-recovery.md`).
enum AirPlayAudioSession {
    /// Whether the session's output is an AirPlay route.
    static var isActiveRoute: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
    }

    /// Rebuilds the AirPlay stream so a resume from pause always brings dead
    /// audio back: a full deactivate → reactivate, since `setActive(true)` alone
    /// is a no-op on an active session. Call while paused, immediately before
    /// play; the gap it costs is hidden by the pause. No-op off AirPlay.
    static func rebuildStreamBeforeResume() {
        guard isActiveRoute else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setActive(true)
        } catch {
            PlozzLog.playback.error("AirPlay audio session could not be rebuilt before resume")
        }
    }
}
#endif
