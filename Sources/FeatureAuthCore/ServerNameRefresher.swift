import Foundation
import CoreModels
import CoreNetworking
import ProviderJellyfin

/// One-shot, cross-platform refresh of server names and redirected API addresses.
///
/// Historically iOS added Jellyfin/Emby accounts with a PLACEHOLDER name
/// (`ProviderKind.displayName`, e.g. "Jellyfin") and never fetched the server's real
/// name, so those accounts — and any devices they synced to — showed "Jellyfin"
/// instead of the server's actual name. Sign-in now resolves the real name, but
/// existing accounts still carry the stale value.
///
/// This refresher re-reads each managed (MediaBrowser: Jellyfin/Emby) server's public
/// system info without credentials. A resolved address is adopted only when the
/// server ID still matches. Metadata updates never rewrite credentials or revive
/// an account removed while discovery was in flight.
/// It is:
///   • idempotent (matching name and address are a no-op),
///   • non-destructive (offline/unreachable servers are skipped, tokens untouched),
///   • shared by tvOS + iOS so both platforms converge identically.
public struct ServerNameRefresher: Sendable {
    private let accountStore: AccountPersisting
    private let http: HTTPClient

    public init(accountStore: AccountPersisting, http: HTTPClient = URLSessionHTTPClient()) {
        self.accountStore = accountStore
        self.http = http
    }

    /// Refresh managed server names and addresses. Returns the number of accounts
    /// updated; unchanged and unreachable servers are not rewritten.
    @discardableResult
    public func refresh() async -> Int {
        let accounts = accountStore.loadAccounts()
        let deviceID = accountStore.deviceID()
        var updated = 0

        for account in accounts where account.server.provider.usesMediaBrowserAPI {
            let client = JellyfinClient(
                baseURL: account.server.baseURL,
                deviceProfile: JellyfinDeviceProfile(deviceID: deviceID),
                providerKind: account.server.provider,
                http: http
            )
            let info: MediaServer
            do {
                try Task.checkCancellation()
                info = try await client.publicSystemInfo()
                try Task.checkCancellation()
            } catch {
                if error is CancellationError || (error as? AppError) == .cancelled { return updated }
                PlozzLog.auth.info("Server metadata refresh failed: \(String(describing: error))")
                continue
            }
            // `publicSystemInfo` already applies the canonical ServerName ?? host ??
            // "<Provider> Server" fallback, so a non-placeholder here is authoritative.
            let addressChanged = info.baseURL != account.server.baseURL
            if addressChanged, info.id != account.server.id {
                PlozzLog.auth.error("Server metadata refresh rejected a redirected server identity mismatch")
                continue
            }
            guard !info.name.isEmpty,
                  info.name != account.server.name || addressChanged else { continue }

            var server = account.server
            server.name = info.name
            server.baseURL = info.baseURL
            if server.version == nil { server.version = info.version }
            do {
                try accountStore.updateServerMetadata(expected: account, server: server)
                updated += 1
                PlozzLog.auth.info("Server metadata refreshed addressChanged=\(addressChanged)")
            } catch {
                PlozzLog.auth.error("ServerNameRefresher: failed to update \(account.id): \(error.localizedDescription)")
            }
        }
        return updated
    }
}
