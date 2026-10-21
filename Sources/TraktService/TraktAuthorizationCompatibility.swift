@_exported import CoreTrackerAuth
import Foundation

public typealias TraktTokenCoordinator = TrackerTokenCoordinator
public typealias TraktTokenStoring = TrackerTokenStoring
public typealias TraktTokenStoreError = TrackerTokenStoreError
public typealias KeychainTraktTokenStore = KeychainTrackerTokenStore
public typealias InMemoryTraktTokenStore = InMemoryTrackerTokenStore
public typealias TraktSharedRefreshConfiguration = TrackerSharedRefreshConfiguration
public typealias TraktSharedRefreshTransport = TrackerSharedRefreshTransport
public typealias TraktSharedRefreshJournal = TrackerSharedRefreshJournal
public typealias SecureTraktSharedRefreshJournal = SecureTrackerSharedRefreshJournal
public typealias TraktSharedRefreshError = TrackerSharedRefreshError
public typealias TraktSharedRecord = TrackerSharedRecord
public typealias TraktSharedRefresh = TrackerSharedRefresh
public typealias TraktTokens = TrackerTokens

typealias TraktProfileGeneration = TrackerProfileGeneration

extension TrackerSharedRefreshError {
    public var userMessage: LocalizedStringResource {
        switch self {
        case .conflict, .refreshInProgress:
            LocalizedStringResource(
                "trakt.sync.updating",
                defaultValue: "Another device is updating this Trakt connection. Try again shortly.",
                comment: "Trakt shared refresh is owned by another device; retry rather than signing in again."
            )
        case .unavailable:
            LocalizedStringResource(
                "trakt.sync.unavailable",
                defaultValue: "Plozz couldn't access iCloud for this Trakt connection. Try again shortly.",
                comment: "Shared Trakt authorization could not be checked. May appear before sign-in, so do not claim a connection is saved."
            )
        case .cloudFailure(let code):
            LocalizedStringResource(
                "trakt.sync.cloudFailure",
                defaultValue: "Plozz couldn't sync this Trakt connection with iCloud (error \(code)). Try again. If this continues, report the error to Plozz.",
                comment: "CloudKit rejected a Trakt synchronization operation. The integer is a nonsecret CloudKit error code, not a Trakt sign-in error."
            )
        case .accountChanged:
            LocalizedStringResource(
                "trakt.sync.accountChanged",
                defaultValue: "The iCloud account changed. The previous account’s Trakt connection was not shared.",
                comment: "Prevents sharing a previous iCloud account's Trakt grant into a different account."
            )
        case .invalidRecord, .missingRecord:
            LocalizedStringResource(
                "trakt.sync.unverified",
                defaultValue: "The shared Trakt connection could not be verified. Try syncing again.",
                comment: "The saved shared Trakt grant could not be verified safely."
            )
        case .outcomeUnknown:
            LocalizedStringResource(
                "trakt.sync.waitingForOwner",
                defaultValue: "The device renewing Trakt has not shared its result yet. Open Plozz on that device and retry. If it cannot recover, reconnect this profile once to restore all devices.",
                comment: "A single-use refresh may have completed on another device. Never replay it; retry recovery or explicitly reconnect the shared profile."
            )
        case .superseded:
            LocalizedStringResource(
                "trakt.sync.changed",
                defaultValue: "This Trakt connection was changed on another device. Try again.",
                comment: "A newer shared Trakt authorization superseded this device's pending change."
            )
        case .retryable:
            LocalizedStringResource(
                "trakt.sync.retry",
                defaultValue: "Trakt could not renew this connection yet. Wait a moment, then retry. You do not need to sign in again.",
                comment: "A refresh was safely deferred or throttled. Retry the existing shared connection, not a new authorization."
            )
        }
    }
}
