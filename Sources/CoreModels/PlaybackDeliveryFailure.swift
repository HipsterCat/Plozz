import Foundation

/// A loopback relay's typed failure, retained by its player before native playback
/// can replace an upstream refusal with a generic media-loading error.
public final class PlaybackDeliveryFailure: @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var entries: [URL: PlaybackDeliveryFailure] = [:]
    }

    private static let registry = Registry()
    private let lock = NSLock()
    private var failure: AppError?
    private var failureDiagnostic: PlaybackFailureDiagnostic?
    private var deliveryEvidence = PlaybackDeliveryEvidence()

    private init() {}

    public var error: AppError? { lock.withLock { failure } }
    public var diagnostic: PlaybackFailureDiagnostic? { lock.withLock { failureDiagnostic } }
    public var evidence: PlaybackDeliveryEvidence { lock.withLock { deliveryEvidence } }

    public func recordRequest(_ request: PlaybackDeliveryEvidence.Request) {
        lock.withLock {
            let root = deliveryEvidence.root
            if request.resource == .root,
               request.sequence >= (root?.sequence ?? 0),
               request.method == .get || root?.method != .get,
               request.outcome == .complete || root?.outcome != .complete || root?.method != request.method {
                deliveryEvidence.root = request
            }
            if request.outcome == .upstreamFailure, deliveryEvidence.firstFailure == nil {
                deliveryEvidence.firstFailure = request
            }
            deliveryEvidence.recent.removeAll { $0.sequence == request.sequence }
            deliveryEvidence.recent.append(request)
            deliveryEvidence.recent.sort { $0.sequence < $1.sequence }
            deliveryEvidence.recent = Array(deliveryEvidence.recent.suffix(8))
        }
    }

    public func record(_ error: AppError, diagnostic: PlaybackFailureDiagnostic? = nil) {
        guard error != .cancelled else { return }
        lock.withLock {
            guard failure == nil else { return }
            failure = error
            failureDiagnostic = diagnostic
        }
    }

    public func clearRateLimit() {
        lock.withLock {
            guard case .rateLimited = failure else { return }
            failure = nil
            failureDiagnostic = nil
        }
    }

    public static func register(loopbackURL: URL) -> PlaybackDeliveryFailure {
        let state = PlaybackDeliveryFailure()
        registry.lock.withLock { registry.entries[loopbackURL] = state }
        return state
    }

    public static func state(for url: URL) -> PlaybackDeliveryFailure? {
        registry.lock.withLock { registry.entries[url] }
    }

    public static func unregister(loopbackURL: URL) {
        registry.lock.withLock { _ = registry.entries.removeValue(forKey: loopbackURL) }
    }
}
