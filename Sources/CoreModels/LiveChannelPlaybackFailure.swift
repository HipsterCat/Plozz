import Foundation

public enum LiveChannelPlaybackFailure: Equatable, Sendable {
    case startupTimedOut
    case bufferingTimedOut
    case recoveryExhausted
    case engine(AppError)
    case input(LiveChannelInputError)
    case library(LibraryChannelError)
    case ended
    case initializationFailed

    public var message: LocalizedStringResource {
        switch self {
        case .startupTimedOut: "The player did not present channel video before the startup time limit."
        case .bufferingTimedOut: "The player did not resume channel video before the buffering time limit."
        case .recoveryExhausted: "The player could not recover this channel within its retry limit."
        case .engine(let error): Self.engineMessage(error)
        case .input(let error): error.message
        case .library(let error): error.message
        case .ended: "The channel’s stream ended."
        case .initializationFailed: "The player could not be started."
        }
    }

    public static func engineMessage(_ error: AppError) -> LocalizedStringResource {
        switch error {
        case .notFound:
            "The channel provider could not find this stream."
        case .unauthorized, .invalidCredentials:
            "The channel provider did not authorize access to this stream."
        case .accessRestricted:
            "The provider has restricted access to this stream."
        case .serverUnreachable:
            "Plozz could not reach the channel’s streaming server."
        case .rateLimited:
            "The channel provider is limiting requests."
        case .conflict:
            "No tuner is currently available. Keep watching or try again later."
        case .invalidResponse:
            "The channel’s playlist or video data could not be opened."
        case .decoding:
            "The player could not decode this channel’s audio or video."
        case .cancelled:
            "Opening this channel was cancelled."
        default:
            "Plozz could not start playback. No more specific cause was captured."
        }
    }

    var diagnosticCode: String {
        switch self {
        case .startupTimedOut: "startupTimedOut"
        case .bufferingTimedOut: "bufferingTimedOut"
        case .recoveryExhausted: "recoveryExhausted"
        case .input: "unsupportedSource"
        case .library: "library"
        case .ended: "ended"
        case .initializationFailed: "initializationFailed"
        case .engine(let error):
            switch error {
            case .serverUnreachable: "serverUnreachable"
            case .invalidResponse: "invalidResponse"
            case .unauthorized: "unauthorized"
            case .invalidCredentials: "invalidCredentials"
            case .accessRestricted: "accessRestricted"
            case .notFound: "notFound"
            case .rateLimited: "rateLimited"
            case .conflict: "tunerUnavailable"
            case .decoding: "decoding"
            case .cancelled: "cancelled"
            default: "unknown"
            }
        }
    }
}

/// Captured before stopping the engine, then retained by the presenting guide.
public struct LiveChannelFailureReport: Equatable, Sendable {
    public let failure: LiveChannelPlaybackFailure
    public let diagnostic: PlaybackFailureDiagnostic?

    public init(failure: LiveChannelPlaybackFailure, diagnostic: PlaybackFailureDiagnostic? = nil) {
        self.failure = failure
        self.diagnostic = diagnostic
    }

    public var message: LocalizedStringResource {
        if case .engine(.invalidResponse) = failure,
           let diagnostic, diagnostic.reason == .invalidResponse,
           diagnostic.httpStatus.map({ (200...299).contains($0) }) == true,
           let message = diagnostic.format.nonVideoMessage {
            return message
        }
        return switch failure {
        case .engine(.conflict): failure.message
        case .engine:
            PlaybackDiagnosticReport.providerMessage(
                httpStatus: diagnostic?.httpStatus,
                networkCode: diagnostic?.domain == .url ? diagnostic?.code : nil
            ) ?? diagnostic?.engineFailure.message ?? failure.message
        default: failure.message
        }
    }
}
