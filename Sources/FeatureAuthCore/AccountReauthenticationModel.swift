import CoreModels
import CoreNetworking
import Foundation
import Observation

@MainActor
@Observable
public final class AccountReauthenticationModel {
    public let account: Account
    public let deviceID: String
    public private(set) var errorMessage: LocalizedStringResource?
    private let store: AccountPersisting
    private let isAuthorized: () -> Bool
    private let onComplete: () -> Void
    private var isActive = true

    public init(
        account: Account, deviceID: String, store: AccountPersisting,
        isAuthorized: @escaping () -> Bool, onComplete: @escaping () -> Void
    ) {
        self.account = account
        self.deviceID = deviceID
        self.store = store
        self.isAuthorized = isAuthorized
        self.onComplete = onComplete
    }

    public func complete(_ session: UserSession) throws {
        guard isActive, isAuthorized(), !Task.isCancelled else {
            PlozzLog.auth.info("Account recovery authorization changed")
            errorMessage = "This connection changed. Close sign-in and try again."
            throw AppError.cancelled
        }
        guard session.server.provider == account.server.provider,
              session.server.id == account.server.id, session.userID == account.userID else {
            PlozzLog.auth.info("Account recovery rejected a different server or user")
            errorMessage = "Sign in with the same account and server profile to restore this connection."
            throw AppError.conflict
        }
        do {
            try store.replaceAuthenticatedSession(session, expected: account)
        } catch {
            PlozzLog.auth.error("Unable to persist recovered server account")
            if error as? AppError == .conflict {
                errorMessage = "This connection changed. Close sign-in and try again."
            } else {
                errorMessage = "Couldn’t save the sign-in. Your existing connection has not been removed. Try again."
            }
            throw error
        }
        isActive = false
        onComplete()
    }

    public func retry() { errorMessage = nil }
    public func cancel() { isActive = false }
}
