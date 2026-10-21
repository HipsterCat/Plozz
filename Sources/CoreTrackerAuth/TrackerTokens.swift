import CoreModels
import Foundation

// MARK: - Stored tokens

/// Profile-scoped OAuth credentials with an absolute expiry and stable grant identity.
public struct TrackerTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var accountIdentity: String?
    /// Absolute expiry instant (createdAt + expiresIn).
    public var expiresAt: Date

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        accountIdentity: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountIdentity = accountIdentity
    }

    /// Treated as expired a few minutes early so a scrobble never races the
    /// deadline with a token the server is about to reject.
    public var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-300)
    }

    public var stableAccountIdentity: String {
        accountIdentity ?? WatchlistReconciliationIdentity.credential(
            refreshToken.isEmpty ? accessToken : refreshToken
        )
    }

    public func inheritingAccountIdentity(from previous: Self) -> Self {
        var value = self
        value.accountIdentity = previous.stableAccountIdentity
        return value
    }
}
