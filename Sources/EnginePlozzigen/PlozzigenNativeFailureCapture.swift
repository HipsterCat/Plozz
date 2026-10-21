#if canImport(AVFoundation)
@preconcurrency import AVFoundation
import CoreModels
import Foundation

/// Native log getters can block in the media service. Never wait for them on the
/// UI actor, or admit unlimited readers when that service stops responding.
final class PlozzigenNativeFailureCapture: @unchecked Sendable {
    static let shared = PlozzigenNativeFailureCapture()
    private let lock = NSLock()
    private var running = 0

    func capture(
        item: AVPlayerItem?, fallbackError: NSError?,
        timeout: TimeInterval = 0.5,
        read: @escaping @Sendable (AVPlayerItem) -> PlaybackFailureEvidence = { PlozzigenNativeFailureCapture.read($0) }
    ) async -> PlaybackFailureEvidence {
        guard let item else {
            return .init(nativeCapture: .noItem, nativeErrors: PlaybackFailureEvidence.ErrorCode.chain(fallbackError))
        }
        let admitted = lock.withLock {
            guard running < 2 else { return false }
            running += 1
            return true
        }
        guard admitted else {
            return .init(nativeCapture: .busy, nativeErrors: PlaybackFailureEvidence.ErrorCode.chain(fallbackError))
        }
        let completion = Completion()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion.install(continuation)
                DispatchQueue.global(qos: .utility).async { [self] in
                    var evidence = read(item)
                    if evidence.nativeErrors.isEmpty {
                        evidence.nativeErrors = PlaybackFailureEvidence.ErrorCode.chain(fallbackError)
                    }
                    lock.withLock { running -= 1 }
                    completion.finish(evidence)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    completion.finish(.init(
                        nativeCapture: .timedOut, nativeErrors: PlaybackFailureEvidence.ErrorCode.chain(fallbackError)
                    ))
                }
            }
        } onCancel: {
            completion.finish(.init(nativeCapture: .timedOut))
        }
    }

    static func read(_ item: AVPlayerItem) -> PlaybackFailureEvidence {
        .init(
            nativeCapture: .captured,
            nativeErrors: PlaybackFailureEvidence.ErrorCode.chain(item.error as NSError?),
            nativeLogErrors: (item.errorLog()?.events.suffix(4) ?? []).map {
                .init(domain: $0.errorDomain, code: $0.errorStatusCode)
            }.filter(\.isValid)
        )
    }

    private final class Completion: @unchecked Sendable {
        private let lock = NSLock()
        private var result: PlaybackFailureEvidence?
        private var continuation: CheckedContinuation<PlaybackFailureEvidence, Never>?

        func install(_ continuation: CheckedContinuation<PlaybackFailureEvidence, Never>) {
            let value: PlaybackFailureEvidence? = lock.withLock {
                if let result { return result }
                self.continuation = continuation
                return nil
            }
            if let value { continuation.resume(returning: value) }
        }

        func finish(_ value: PlaybackFailureEvidence) {
            let callback = lock.withLock {
                guard result == nil else { return nil as CheckedContinuation<PlaybackFailureEvidence, Never>? }
                result = value
                let callback = continuation
                continuation = nil
                return callback
            }
            callback?.resume(returning: value)
        }
    }
}
#endif
