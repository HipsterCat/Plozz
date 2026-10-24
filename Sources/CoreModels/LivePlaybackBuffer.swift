import Foundation
import os

public enum LivePlaybackBuffer: String, CaseIterable, Sendable {
    case automatic
    case tenSeconds
    case twentySeconds
    case thirtySeconds
    case fortyFiveSeconds

    public static let `default`: Self = .automatic

    public var seconds: TimeInterval? {
        switch self {
        case .automatic: nil
        case .tenSeconds: 10
        case .twentySeconds: 20
        case .thirtySeconds: 30
        case .fortyFiveSeconds: 45
        }
    }

    public var title: LocalizedStringResource {
        switch self {
        case .automatic: "Automatic"
        case .tenSeconds: "10 seconds"
        case .twentySeconds: "20 seconds"
        case .thirtySeconds: "30 seconds"
        case .fortyFiveSeconds: "45 seconds"
        }
    }
}

/// A device network/storage preference, independent of profile transfer and VOD read-ahead.
public struct LivePlaybackBufferStore {
    public static let storageKey = "com.plozz.livePlaybackBuffer"
    private static let logger = Logger(subsystem: "com.plozz.app", category: "settings")
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> LivePlaybackBuffer {
        guard let stored = defaults.object(forKey: Self.storageKey) else { return .default }
        guard let rawValue = stored as? String, let preference = LivePlaybackBuffer(rawValue: rawValue) else {
            Self.logger.error("Invalid live playback buffer preference; using Automatic")
            return .default
        }
        return preference
    }

    public func save(_ preference: LivePlaybackBuffer) {
        defaults.set(preference.rawValue, forKey: Self.storageKey)
    }
}
