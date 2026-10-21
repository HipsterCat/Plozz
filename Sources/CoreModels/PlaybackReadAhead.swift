import Foundation
import os

public enum PlaybackReadAhead: String, CaseIterable, Sendable {
    case automatic
    case oneMinute
    case fiveMinutes
    case tenMinutes
    case maximumAvailable

    public static let `default`: Self = .automatic

    public var title: LocalizedStringResource {
        switch self {
        case .automatic: "Automatic"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        case .maximumAvailable: "Maximum available"
        }
    }
}

/// A device storage/network preference, deliberately outside profile transfer and sync.
public struct PlaybackReadAheadStore {
    public static let storageKey = "com.plozz.playbackReadAhead"
    private static let logger = Logger(subsystem: "com.plozz.app", category: "settings")
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> PlaybackReadAhead {
        guard let stored = defaults.object(forKey: Self.storageKey) else { return .default }
        guard let rawValue = stored as? String, let preference = PlaybackReadAhead(rawValue: rawValue) else {
            Self.logger.error("Invalid playback read-ahead preference; using Automatic")
            return .default
        }
        return preference
    }

    public func save(_ preference: PlaybackReadAhead) {
        defaults.set(preference.rawValue, forKey: Self.storageKey)
    }
}
