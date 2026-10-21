import CoreModels
import CoreNetworking

struct JellyfinWatchHistoryInfo: Decodable {
    struct AIOStreams: Decodable {
        struct Features: Decodable {
            let history: Int?
        }

        let features: Features?
    }

    let Id: String?
    let aiostreams: AIOStreams?
}

/// Capability lifetime is one provider/account session, never a host-name guess
/// or a persisted preference that can survive switching servers.
actor JellyfinWatchHistoryScope {
    private var accountWide: Bool?

    func isAccountWide(client: JellyfinClient, serverID: String) async throws -> Bool {
        try Task.checkCancellation()
        if let accountWide { return accountWide }

        let info: JellyfinWatchHistoryInfo
        do {
            info = try await client.watchHistorySystemInfo()
        } catch AppError.notFound {
            try Task.checkCancellation()
            PlozzLog.networking.info(
                "MediaBrowser history capability endpoint unavailable; retaining library filtering"
            )
            accountWide = false
            return false
        }
        try Task.checkCancellation()
        let result = (info.aiostreams?.features?.history ?? 0) > 0
        if result {
            guard !serverID.isEmpty, info.Id == serverID else { throw AppError.conflict }
            PlozzLog.networking.info(
                "AIOStreams account-wide watch history enabled; catalog visibility does not filter history"
            )
        }
        accountWide = result
        return result
    }
}
