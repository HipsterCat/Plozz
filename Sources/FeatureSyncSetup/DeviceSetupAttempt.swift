import CoreModels
import CoreNetworking
import Foundation

@MainActor
struct DeviceSetupAttempt {
    let role: DeviceSetupDiagnostic.Role
    let route: DeviceSetupDiagnostic.Route
    var stage: DeviceSetupDiagnostic.Stage = .validation
    private let started = ContinuousClock.now
    private let report: DeviceSetupDiagnostics.Sink?

    init(role: DeviceSetupDiagnostic.Role, route: DeviceSetupDiagnostic.Route,
         diagnostics: DeviceSetupDiagnostics) {
        self.role = role
        self.route = route
        report = diagnostics.begin()
    }

    func record(_ outcome: DeviceSetupDiagnostic.Outcome, reason: DeviceSetupDiagnostic.Reason = .none) {
        let duration = started.duration(to: .now).components
        let milliseconds = min(86_400_000, duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000)
        let diagnostic = DeviceSetupDiagnostic(
            role: role, route: route, stage: stage, outcome: outcome, reason: reason,
            elapsedMilliseconds: Int(milliseconds)
        )
        let message = "format=plozz-device-setup-1 role=\(role.rawValue) route=\(route.rawValue)"
            + " stage=\(stage.rawValue) outcome=\(outcome.rawValue) reason=\(reason.rawValue)"
            + " elapsed_ms=\(diagnostic.elapsedMilliseconds)"
        if outcome == .failed { PlozzLog.sync.error(message) }
        else { PlozzLog.sync.info(message) }
        report?(diagnostic)
    }

    func fail(_ error: Error) {
        let reason: DeviceSetupDiagnostic.Reason
        switch error {
        case is CancellationError: reason = .cancelled
        case SyncPairingError.expiredContext: reason = .expired
        case SyncPairingError.notConfirmed: reason = .rejected
        case SyncPairingError.commitmentMismatch, SyncPairingError.decryptionFailed,
             SyncPairingError.kindMismatch: reason = .verification
        case BonjourPairingError.listenerFailed: reason = .listener
        case BonjourPairingError.connectionFailed: reason = .connection
        case BonjourPairingError.framing: reason = .framing
        case BonjourPairingError.timedOut: reason = .timeout
        case is DecodingError: reason = .framing
        case is ProfilesModel.AccountSelectionError: reason = .configuration
        case SetupAuthorizationError.changed: reason = .authorizationChanged
        default: reason = .unknown
        }
        record(reason == .cancelled || reason == .rejected ? .cancelled : .failed, reason: reason)
    }
}

enum SetupAuthorizationError: Error {
    case changed
}
