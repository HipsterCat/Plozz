#if DEBUG
import CoreModels
import CoreNetworking
import Foundation

struct LiveChannelDiagnostics {
    enum Event: String {
        case load, retry, pause, resume, seek, seekCompleted, suspend, foreground
        case failure, startupTimeout, stallTimeout, ended, stop
    }
    enum ItemState: String { case missing, unknown, ready, failed }
    enum WaitReason: String { case none, minimizeStalls, evaluatingRate, noItem, other }

    struct Snapshot {
        let phase: LivePlaybackActivity.State
        let transport: LivePlaybackActivity.Transport
        let item: ItemState
        let wait: WaitReason
        let layerReady: Bool
        let layerMatchesPlayer: Bool
        let attached: Bool
        let clockAdvanced: Bool
        let position: Double
        let stalledFor: Double?
        let rate: Float
        let bufferEmpty: Bool
        let likelyToKeepUp: Bool
        let seekableDuration: Double?

        var signature: String {
            "\(phase.rawValue)/\(transport.rawValue)/\(item.rawValue)/\(wait.rawValue)"
                + "/\(layerReady)/\(layerMatchesPlayer)/\(attached)/\(clockAdvanced)"
                + "/\(bufferEmpty)/\(likelyToKeepUp)"
        }

        var detail: String {
            "phase=\(phase.rawValue) transport=\(transport.rawValue) item=\(item.rawValue)"
                + " wait=\(wait.rawValue) layerReady=\(layerReady) layerMatches=\(layerMatchesPlayer)"
                + " attached=\(attached) clockAdvanced=\(clockAdvanced)"
                + " position=\(number(position)) stalledFor=\(number(stalledFor)) rate=\(number(Double(rate)))"
                + " bufferEmpty=\(bufferEmpty) likelyToKeepUp=\(likelyToKeepUp)"
                + " seekableDuration=\(number(seekableDuration))"
        }

        private func number(_ value: Double?) -> String {
            guard let value, value.isFinite else { return "unknown" }
            return String(format: "%.3f", value)
        }
    }

    struct Cadence {
        private var lastEmission: TimeInterval?
        private var lastSignature: String?

        mutating func shouldEmit(signature: String, uptime: TimeInterval) -> Bool {
            if let lastEmission {
                let elapsed = uptime - lastEmission
                guard elapsed >= 1,
                      signature != lastSignature || elapsed >= 10 else { return false }
            }
            lastEmission = uptime
            lastSignature = signature
            return true
        }
    }

    // Correlate an attempt without recording channel IDs, names, URLs or tokens.
    private let session = UUID().uuidString
    private var cadence = Cadence()

    mutating func sample(_ snapshot: Snapshot, uptime: TimeInterval, attempt: Int) {
        guard HandoffDiagnostics.isEnabled,
              cadence.shouldEmit(signature: snapshot.signature, uptime: uptime) else { return }
        emit("attempt=\(attempt) event=sample \(snapshot.detail)")
    }

    func event(_ event: Event, attempt: Int, error: AppError? = nil) {
        guard HandoffDiagnostics.isEnabled else { return }
        let code = error.map(HandoffDiagnostics.errorCode) ?? "none"
        emit("attempt=\(attempt) event=\(event.rawValue) error=\(code)")
    }

    private func emit(_ detail: String) {
        let line = "LIVE_TV session=\(session) engine=AVPlayer \(detail)"
        PlozzLog.playback.info(line)
        HandoffDiagnostics.emit(line)
    }
}
#endif
