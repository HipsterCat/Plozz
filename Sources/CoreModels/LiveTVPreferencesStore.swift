import Foundation

/// Profile-scoped, non-secret Live TV metadata.
///
/// Channel identifiers are retained even when the current catalog is empty or
/// temporarily unavailable. The catalog may resolve them again on a later load.
public struct LiveTVPreferences: Codable, Equatable, Sendable {
    public static let maximumRecentChannelCount = 3
    public static let empty = LiveTVPreferences()

    public let favoriteIDs: Set<String>
    public let recentChannelIDs: [String]

    public init(
        favoriteIDs: Set<String> = [],
        recentChannelIDs: [String] = []
    ) {
        self.favoriteIDs = favoriteIDs

        var seen = Set<String>()
        self.recentChannelIDs = Array(
            recentChannelIDs
                .filter { seen.insert($0).inserted }
                .prefix(Self.maximumRecentChannelCount)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case favoriteIDs
        case recentChannelIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            favoriteIDs: try container.decode(Set<String>.self, forKey: .favoriteIDs),
            recentChannelIDs: try container.decode([String].self, forKey: .recentChannelIDs)
        )
    }
}

public protocol LiveTVPreferencesStoring: Sendable {
    func load() throws -> LiveTVPreferences
    func save(_ preferences: LiveTVPreferences) throws
}

public enum LiveTVPreferencesStoreError: Error, Equatable, Sendable {
    case invalidStoredValue
    case decodingFailed
    case encodingFailed
}

/// Persists Live TV favorites and recent channel identifiers in `UserDefaults`.
///
/// A corrupt value is reported rather than treated as empty. `save(_:)` also
/// refuses to replace an unreadable existing value, preserving it for recovery
/// or diagnosis instead of silently erasing it.
public final class LiveTVPreferencesStore: LiveTVPreferencesStoring, @unchecked Sendable {
    static let baseKey = "com.plozz.liveTV.preferences"

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    /// - Parameter namespace: per-profile scope. `nil` (the default/primary
    ///   profile) uses the un-suffixed key; secondary profiles pass their
    ///   `Profile.id`.
    public init(defaults: UserDefaults = .standard, namespace: String? = nil) {
        self.defaults = defaults
        self.key = SettingsKey.scoped(Self.baseKey, namespace: namespace)
    }

    public func load() throws -> LiveTVPreferences {
        lock.lock()
        defer { lock.unlock() }
        return try loadLocked()
    }

    public func save(_ preferences: LiveTVPreferences) throws {
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(preferences)
        } catch {
            throw LiveTVPreferencesStoreError.encodingFailed
        }

        lock.lock()
        defer { lock.unlock() }

        if defaults.object(forKey: key) != nil {
            _ = try loadLocked()
        }
        defaults.set(encoded, forKey: key)
    }

    private func loadLocked() throws -> LiveTVPreferences {
        guard let stored = defaults.object(forKey: key) else {
            return .empty
        }
        guard let data = stored as? Data else {
            throw LiveTVPreferencesStoreError.invalidStoredValue
        }
        do {
            return try JSONDecoder().decode(LiveTVPreferences.self, from: data)
        } catch {
            throw LiveTVPreferencesStoreError.decodingFailed
        }
    }
}
