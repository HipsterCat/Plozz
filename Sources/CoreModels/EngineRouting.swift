import Foundation

/// Playback ownership. Aether chooses its own native or software decode route.
public enum PlaybackEngineKind: String, Codable, Sendable, Equatable, CaseIterable {
    /// AVFoundation-owned assets/compositions and bounded compatibility recovery.
    case native
    /// Legacy on-device-engine identifier, resolved to Plozzigen by the factory.
    case hybrid
    /// AetherEngine, including its AVPlayer-backed remote HLS route.
    case plozzigen
}
