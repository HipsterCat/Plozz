import CoreModels
import CoreNetworking
import Foundation

@MainActor
final class StreamingSessionMaintenance {
    private let interval: Duration
    private var task: Task<Void, Never>?
    private var sessionID: String?

    init(interval: Duration = .seconds(10)) {
        self.interval = interval
    }

    deinit {
        task?.cancel()
    }

    func start(request: PlaybackRequest, provider: any MediaProvider) {
        let previous = cancel()
        guard request.isTranscoding, request.streamingSessionID != nil,
              let provider = provider as? any StreamingSessionMaintaining else {
            sessionID = nil
            if let previous { task = Task { await previous.value } }
            return
        }
        sessionID = request.streamingSessionID
        let interval = interval
        task = Task {
            await previous?.value
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                    try Task.checkCancellation()
                    try await provider.maintainStreamingSession(request)
                } catch {
                    guard !Task.isCancelled else { return }
                    PlozzLog.playback.debug("Streaming session maintenance failed (non-fatal).")
                }
            }
        }
    }

    /// The caller drains this task before releasing its server session.
    @discardableResult
    func cancel() -> Task<Void, Never>? {
        let previous = task
        previous?.cancel()
        return previous
    }

    func cancel(sessionID: String) -> Task<Void, Never>? {
        guard self.sessionID == sessionID else { return nil }
        return cancel()
    }
}
