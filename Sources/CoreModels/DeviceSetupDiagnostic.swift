import Foundation

/// Pairing telemetry contains only fixed categories and bounded elapsed time.
public struct DeviceSetupDiagnostic: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case sender, receiver }
    public enum Route: String, Codable, Sendable { case automatic, qr, code, nearby, sourceQR, link, receive }
    public enum Stage: String, Codable, Sendable {
        case validation, connection, configuration, handshake, confirmation, transfer, persistence
    }
    public enum Outcome: String, Codable, Sendable { case started, succeeded, failed, cancelled }
    public enum Reason: String, Codable, Sendable {
        case none, invalidInvite, expired, listener, connection, framing, timeout
        case verification, rejected, cancelled, authorizationChanged, configuration, storage, unknown
    }

    public let role: Role
    public let route: Route
    public let stage: Stage
    public let outcome: Outcome
    public let reason: Reason
    public let elapsedMilliseconds: Int

    public init(role: Role, route: Route, stage: Stage, outcome: Outcome, reason: Reason = .none,
                elapsedMilliseconds: Int = 0) {
        self.role = role
        self.route = route
        self.stage = stage
        self.outcome = outcome
        self.reason = reason
        self.elapsedMilliseconds = min(max(0, elapsedMilliseconds), 86_400_000)
    }

    public var isValid: Bool {
        (0...86_400_000).contains(elapsedMilliseconds)
            && (outcome == .failed ? reason != .none && reason != .cancelled && reason != .rejected
                : outcome == .cancelled ? reason == .cancelled || reason == .rejected
                : reason == .none)
    }

    public var failureKey: String { "\(role.rawValue):\(route.rawValue):\(stage.rawValue):\(reason.rawValue)" }
}

/// An attempt captures its consent generation. Opting out invalidates even retained
/// callbacks, and a later opt-in cannot upload work from the previous session.
public final class DeviceSetupDiagnostics: @unchecked Sendable {
    public typealias Sink = @Sendable (DeviceSetupDiagnostic) -> Void
    public static let shared = DeviceSetupDiagnostics()
    private let lock = NSRecursiveLock()
    private var generation = UUID()
    private var sink: Sink?
    private var reported: Set<String> = []

    public init() {}

    public func start(sink: @escaping Sink) {
        lock.withLock {
            generation = UUID()
            reported = []
            self.sink = sink
        }
    }

    public func stop() {
        lock.withLock {
            generation = UUID()
            reported = []
            sink = nil
        }
    }

    public func begin() -> Sink? {
        guard let current = lock.withLock({ sink == nil ? nil : generation }) else { return nil }
        return { [weak self] diagnostic in
            guard let self else { return }
            self.lock.withLock {
                guard self.generation == current, diagnostic.isValid, diagnostic.outcome == .failed,
                      self.reported.count < 10, self.reported.insert(diagnostic.failureKey).inserted else { return }
                self.sink?(diagnostic)
            }
        }
    }
}
