import Foundation
import OSLog

public enum ProfileReturnPolicy: String, CaseIterable, Sendable {
    case automatic
    case immediately
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case never

    public var title: LocalizedStringResource {
        switch self {
        case .automatic: "Automatic"
        case .immediately: "Immediately"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .never: "Never"
        }
    }

    public static func automaticPolicy(for profiles: [Profile]) -> Self {
        if profiles.contains(where: { $0.isLocked || $0.playsAsPINProtectedPlexUser }) {
            return .immediately
        }
        return profiles.count > 1 ? .fiveMinutes : .never
    }

    public func delay(for profiles: [Profile], automaticallySignIn: Bool) -> TimeInterval? {
        guard !automaticallySignIn else { return nil }
        switch self {
        case .automatic: return Self.automaticPolicy(for: profiles).delay(for: profiles, automaticallySignIn: false)
        case .immediately: return 0
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1_800
        case .never: return nil
        }
    }
}

/// Shared by profiles on this device, not synced or included in profile transfers.
public struct ProfileReturnPolicyStore {
    public static let storageKey = "plozz.device.profileReturnPolicy"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ProfileReturnPolicy {
        guard defaults.object(forKey: Self.storageKey) != nil else { return .automatic }
        guard let raw = defaults.string(forKey: Self.storageKey),
              let policy = ProfileReturnPolicy(rawValue: raw) else {
            Logger(subsystem: "com.plozz.app", category: "settings")
                .error("Invalid profile return preference; using automatic protection.")
            return .automatic
        }
        return policy
    }

    public func save(_ policy: ProfileReturnPolicy) {
        defaults.set(policy.rawValue, forKey: Self.storageKey)
    }
}
