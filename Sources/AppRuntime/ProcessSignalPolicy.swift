import CoreNetworking
import Darwin

/// App-owned signal policy, installed before networking or crash reporting starts.
public enum ProcessSignalPolicy {
    /// A disconnected socket/pipe must fail its write with EPIPE, not terminate
    /// the app. Some descriptors belong to native dependencies, so per-socket
    /// SO_NOSIGPIPE alone cannot enforce this across the process.
    ///
    /// Install before Sentry starts: it preserves an existing SIG_IGN, including
    /// across crash-reporting opt-out/restart. Do not tie this to reporting consent.
    @discardableResult
    public static func ignoreBrokenPipe() -> Bool {
        var action = sigaction()
        action.__sigaction_u.__sa_handler = SIG_IGN
        sigemptyset(&action.sa_mask)
        guard sigaction(SIGPIPE, &action, nil) == 0 else {
            let errorCode = errno
            PlozzLog.app.error("Could not install broken-pipe protection (errno \(errorCode))")
            return false
        }
        return true
    }
}
