import CoreModels
import Foundation

/// App-side resolution only. An account-qualified link never searches another server.
public enum TopShelfItemResolver {
    public static func resolve(
        _ reference: TopShelf.ItemReference, accounts: [ResolvedAccount]
    ) async throws -> MediaItem {
        try Task.checkCancellation()
        let candidates: [ResolvedAccount]
        if let owner = reference.accountID {
            guard let account = accounts.first(where: { $0.account.id == owner }) else {
                throw AppError.unauthorized
            }
            candidates = [account]
        } else {
            candidates = accounts
        }
        var firstFailure: (any Error)?
        for account in candidates {
            do {
                let item = try await account.provider.item(id: reference.id)
                try Task.checkCancellation()
                guard item.id == reference.id else { throw AppError.invalidResponse }
                return item.taggingSource(account.account.id)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? AppError) == .cancelled { throw error }
                if reference.accountID != nil { throw error }
                if firstFailure == nil { firstFailure = error }
            }
        }
        throw firstFailure ?? AppError.notFound
    }
}
