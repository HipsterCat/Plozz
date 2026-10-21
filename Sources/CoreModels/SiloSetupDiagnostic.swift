import Foundation

/// Only closed categories and bounded HTTP codes may leave the setup flow.
public struct SiloSetupDiagnostic: Codable, Equatable, Hashable, Sendable {
    public enum Stage: String, Codable, Sendable {
        case validation, capability, start, approvalLink, poll, profiles, pin, session
    }
    public enum Reason: String, Codable, Sendable {
        case network, unauthorized, notFound, rateLimited, server, redirect, malformed
        case invalidResponse, addressMismatch, unsupported, unavailable, denied, expired
    }
    public enum Response: String, Codable, Sendable {
        case unknown, json, html, other

        public init(mimeType: String?) {
            switch mimeType?.lowercased().split(separator: ";").first?.trimmingCharacters(in: .whitespaces) {
            case nil: self = .unknown
            case "application/json", "application/problem+json": self = .json
            case "text/html", "application/xhtml+xml": self = .html
            default: self = .other
            }
        }
    }

    public let stage: Stage
    public let reason: Reason
    public let httpStatus: Int?
    public let response: Response

    public init(stage: Stage, reason: Reason, httpStatus: Int? = nil, response: Response = .unknown) {
        self.stage = stage
        self.reason = reason
        self.httpStatus = httpStatus.flatMap { (100...599).contains($0) ? $0 : nil }
        self.response = response
    }

    public var isValid: Bool { httpStatus.map { (100...599).contains($0) } != false }
}

/// Consent is checked both at attempt creation and at emission; retained attempts
/// cannot report after opt-out or a subsequent opt-in.
public final class SiloSetupDiagnostics: @unchecked Sendable {
    public typealias Sink = @Sendable (SiloSetupDiagnostic) -> Void
    public static let shared = SiloSetupDiagnostics()
    private let lock = NSRecursiveLock()
    private var generation = UUID()
    private var sink: Sink?
    private var reported = Set<SiloSetupDiagnostic>()

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
            sink = nil
            reported = []
        }
    }

    public func begin() -> Sink? {
        guard let current = lock.withLock({ sink == nil ? nil : generation }) else { return nil }
        return { [weak self] diagnostic in
            guard let self else { return }
            self.lock.withLock {
                guard self.generation == current, diagnostic.isValid,
                      self.reported.count < 10, self.reported.insert(diagnostic).inserted else { return }
                self.sink?(diagnostic)
            }
        }
    }
}
