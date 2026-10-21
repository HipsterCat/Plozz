import CoreModels
import CoreNetworking
import CoreTrackerAuth
import Foundation

public actor WetrakrWatchlistDestination: WatchlistBatchApplying {
    public nonisolated let id = WatchlistDestinationID(rawValue: "wetrakr")!
    public nonisolated let maximumBatchSize = 50
    public nonisolated let writePolicyVersion = 1
    public nonisolated let capabilities = WatchlistDestinationCapabilities(
        readable: true, writable: true, removable: true, bindingRequirement: .globalExternalIdentity,
        globalIdentityNamespaces: [.imdb, .tmdb, .tvdb, .trakt, .aniList, .myAnimeList, .aniDB, .wetrakr]
    )
    public nonisolated var reconciliationScope: String {
        id.rawValue + "#" + tokenStore.coordinationID + "#" + (tokenStore.load()?.stableAccountIdentity ?? "disconnected")
    }

    private let client: WetrakrClient
    private let auth: WetrakrAuthService
    private let tokenStore: any TrackerTokenStoring
    private let coordinator: TrackerTokenCoordinator
    private let generation: TrackerProfileGeneration
    private let now: @Sendable () -> Date
    private let operations = ConcurrencyLimiter(limit: 1)
    private var cache: Cache?

    private struct Cache {
        var scope: String
        var items: [String: WetrakrMedia]
        var cursor: Date
        var seen: [String: Date] = [:]
        var activityStamp: String?
        var checkedAt: Date = .distantPast
    }

    init(
        client: WetrakrClient, tokenStore: any TrackerTokenStoring,
        coordinator: TrackerTokenCoordinator, generation: TrackerProfileGeneration,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.auth = WetrakrAuthService(client: client)
        self.tokenStore = tokenStore
        self.coordinator = coordinator
        self.generation = generation
        self.now = now
    }

    public func clearCache() { cache = nil }

    public func fetchEntries() async throws -> [WatchlistDestinationEntry] {
        try await operations.run { [self] in
            try await mapped { try await self.fetch() }
        }
    }

    private func fetch() async throws -> [WatchlistDestinationEntry] {
        let scope = reconciliationScope
        let version = generation.current
        let token = try await accessToken(scope: scope, generation: version)
        if let cache, cache.scope == scope, now().timeIntervalSince(cache.checkedAt) < 60 {
            return try entries(cache.items)
        }
        let activities = try await client.decode(
            WetrakrActivities.self, endpoint: Endpoint(path: "/sync/last_activities"), accessToken: token
        )
        try check(scope: scope, version: version)
        if var cached = cache, cached.scope == scope,
           let stamp = activities.all, cached.activityStamp == stamp {
            cached.checkedAt = now()
            cache = cached
            return try entries(cached.items)
        }
        var current: Cache
        if let cached = cache, cached.scope == scope {
            do { current = try await increment(cached, token: token) }
            catch WetrakrError.journalExpired {
                current = try await full(scope: scope, activities: activities, token: token)
            }
        } else {
            current = try await full(scope: scope, activities: activities, token: token)
        }
        try check(scope: scope, version: version)
        if let stamp = activities.all, try WetrakrDate.parse(stamp) <= current.cursor {
            current.activityStamp = stamp
        } else {
            current.activityStamp = nil
        }
        current.checkedAt = now()
        let result = try entries(current.items)
        cache = current
        return result
    }

    private func full(scope: String, activities: WetrakrActivities, token: String) async throws -> Cache {
        guard let mark = activities.journalVisibleUntil else { throw AppError.invalidResponse }
        let cursor = try WetrakrDate.parse(mark)
        var items: [String: WetrakrMedia] = [:]
        for page in 1...1_000 {
            let (rows, hasNext) = try await client.page(
                [WetrakrMedia].self, path: "/sync/tracking/planning/all", page: page, accessToken: token
            )
            for row in rows {
                guard row.id > 0, row.kind != nil else { throw AppError.invalidResponse }
                items[Self.key(row)] = row
            }
            if !hasNext { return Cache(scope: scope, items: items, cursor: cursor) }
        }
        throw AppError.invalidResponse
    }

    private func increment(_ original: Cache, token: String) async throws -> Cache {
        var result = original
        let from = WetrakrDate.string(original.cursor.addingTimeInterval(-5))
        var newest = original.cursor
        for page in 1...1_000 {
            let (journal, hasNext) = try await client.page(
                WetrakrJournal.self, path: "/sync/journal", page: page, query: [
                    .init(name: "from_date", value: from), .init(name: "category", value: "planning"),
                ], accessToken: token
            )
            for row in journal.journal {
                guard row.category == "planning", !row.entryID.isEmpty,
                      row.id > 0, row.media.kind != nil else { throw AppError.invalidResponse }
                let date = try WetrakrDate.parse(row.actionAt)
                newest = max(newest, date)
                if result.seen[row.entryID] != nil { continue }
                switch row.status {
                case "added":
                    result.items[Self.key(row.media)] = row.media
                case "removed":
                    result.items[Self.key(row.media)] = nil
                default: throw AppError.invalidResponse
                }
                result.seen[row.entryID] = date
            }
            if !hasNext {
                // Empty reads advance only to the server's visibility watermark,
                // never last_activities, whose writes may not be visible yet.
                result.cursor = journal.journal.isEmpty
                    ? max(newest, try WetrakrDate.parse(journal.visibleUntil)) : newest
                result.seen = result.seen.filter { $0.value >= result.cursor.addingTimeInterval(-10) }
                return result
            }
        }
        throw AppError.invalidResponse
    }

    public func resolve(_ target: WatchlistMutationTarget) async throws -> WatchlistDestinationBinding? {
        let ids = target.externalIDs.filter { capabilities.globalIdentityNamespaces.contains($0.namespace) }
        guard !ids.isEmpty else { return nil }
        let encoded = try JSONEncoder().encode(Binding(kind: target.kind, ids: ids))
        return WatchlistDestinationBinding(destinationID: id, opaqueValue: encoded.base64EncodedString())
    }

    public func apply(_ desiredState: WatchlistDesiredState, to binding: WatchlistDestinationBinding) async throws {
        try await apply(desiredState, to: binding, expectedReconciliationScope: reconciliationScope)
    }

    public func apply(
        _ desiredState: WatchlistDesiredState, to binding: WatchlistDestinationBinding,
        expectedReconciliationScope: String
    ) async throws {
        let outcomes = try await apply(
            desiredState, to: [binding], idempotencyKey: UUID().uuidString,
            expectedReconciliationScope: expectedReconciliationScope
        )
        guard let outcome = outcomes.first else { throw AppError.invalidResponse }
        try outcome.get()
    }

    public func apply(
        _ desiredState: WatchlistDesiredState, to bindings: [WatchlistDestinationBinding],
        idempotencyKey: String, expectedReconciliationScope: String
    ) async throws -> [Result<Void, WatchlistDestinationError>] {
        guard !bindings.isEmpty, bindings.count <= maximumBatchSize else {
            throw WatchlistDestinationError.permanent
        }
        return try await operations.run { [self] in
            try await mapped {
                try await self.write(
                    desiredState, bindings: bindings, idempotencyKey: idempotencyKey,
                    scope: expectedReconciliationScope
                )
            }
        }
    }

    private struct PlanningItem {
        let kind: MediaItemKind
        let item: WetrakrTrackingBody.Item
        var indices: [Int]
    }

    private func planningItem(_ binding: WatchlistDestinationBinding) throws -> PlanningItem {
        guard binding.destinationID == id, let bytes = Data(base64Encoded: binding.opaqueValue),
              let value = try? JSONDecoder().decode(Binding.self, from: bytes),
              value.kind == .movie || value.kind == .series else { throw WatchlistDestinationError.permanent }
        let ids = WetrakrIDs.from(Dictionary(value.ids.map {
            ($0.namespace.rawValue.lowercased(), $0.value)
        }, uniquingKeysWith: { first, _ in first }))
        let nativeID = value.ids.first(where: { $0.namespace == .wetrakr })
            .flatMap { Int($0.value) }.flatMap { $0 > 0 ? $0 : nil }
        guard nativeID != nil || !ids.externalIDs.isEmpty else { throw WatchlistDestinationError.unsupportedIdentity }
        let item = WetrakrTrackingBody.Item(id: nativeID, ids: nativeID == nil ? ids : nil, status: "planning")
        return PlanningItem(kind: value.kind, item: item, indices: [])
    }

    private func write(
        _ state: WatchlistDesiredState, bindings: [WatchlistDestinationBinding],
        idempotencyKey: String, scope: String
    ) async throws -> [Result<Void, WatchlistDestinationError>] {
        let version = generation.current
        let token = try await accessToken(scope: scope, generation: version)
        let entries = try await fetch()
        try check(scope: scope, version: version)
        var outcomes: [Result<Void, WatchlistDestinationError>] = Array(
            repeating: .failure(.permanent), count: bindings.count
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var grouped: [String: PlanningItem] = [:]
        var unchanged = 0
        for (index, binding) in bindings.enumerated() {
            let prepared: PlanningItem
            do { prepared = try planningItem(binding) }
            catch let error as WatchlistDestinationError {
                outcomes[index] = .failure(error)
                continue
            }
            let sameKind = entries.filter { $0.kind == prepared.kind }
            let matching = sameKind.filter { entry in
                if let nativeID = prepared.item.id {
                    return entry.externalIDs.contains {
                        $0.namespace == .wetrakr && $0.value == String(nativeID)
                    }
                }
                return WetrakrTrackingResult.matches(
                    prepared.item.ids?.externalIDs ?? [], entry.externalIDs
                )
            }
            let absent = matching.isEmpty && sameKind.allSatisfy { entry in
                if prepared.item.id != nil { return true }
                // Missing catalogue IDs cannot prove absence. Let the service
                // resolve such removals instead of silently dropping them.
                return (prepared.item.ids?.externalIDs ?? []).allSatisfy { expected in
                    entry.externalIDs.contains {
                        $0.namespace == expected.namespace && $0.value != expected.value
                    }
                }
            }
            if (state == .present && matching.count == 1) || (state == .absent && absent) {
                outcomes[index] = .success(())
                unchanged += 1
                continue
            }
            let key = prepared.kind.rawValue + ":" + (try encoder.encode(prepared.item)).base64EncodedString()
            if grouped[key] != nil {
                grouped[key]?.indices.append(index)
            } else {
                var item = prepared
                item.indices = [index]
                grouped[key] = item
            }
        }
        let sorted = grouped.keys.sorted().compactMap { grouped[$0] }
        let movies = sorted.filter { $0.kind == .movie }
        let shows = sorted.filter { $0.kind == .series }
        let pending = movies + shows
        guard !pending.isEmpty else {
            await client.gate.planningBatch(items: bindings.count, unchanged: unchanged, outcomes: outcomes)
            return outcomes
        }
        let body = WetrakrTrackingBody(
            movies: movies.isEmpty ? nil : movies.map(\.item),
            shows: shows.isEmpty ? nil : shows.map(\.item)
        )
        // A retry can omit titles proven present by a fresh read. Couple the key
        // to that exact remaining payload, not merely the original queue batch.
        let key = WatchlistReconciliationIdentity.credential(
            idempotencyKey + "\u{0}" + (try encoder.encode(body)).base64EncodedString()
        )
        try check(scope: scope, version: version)
        cache = nil
        let result = try await client.trackingResult(
            body, remove: state == .absent, idempotencyKey: key, accessToken: token
        )
        try check(scope: scope, version: version)
        let applied = try result.planningOutcomes(
            movies: movies.map(\.item), shows: shows.map(\.item), removing: state == .absent
        )
        for (item, outcome) in zip(pending, applied) {
            for index in item.indices { outcomes[index] = outcome }
        }
        await client.gate.planningBatch(items: bindings.count, unchanged: unchanged, outcomes: outcomes)
        return outcomes
    }

    private struct Binding: Codable { let kind: MediaItemKind; let ids: [WatchlistExternalID] }

    private func entries(_ items: [String: WetrakrMedia]) throws -> [WatchlistDestinationEntry] {
        try items.keys.sorted().map { key in
            guard let item = items[key], let kind = item.kind,
                  let nativeID = WatchlistExternalID(namespace: .wetrakr, value: String(item.id))
            else { throw AppError.invalidResponse }
            let ids = (item.ids?.externalIDs ?? []) + [nativeID]
            guard
                  let binding = WatchlistDestinationBinding(
                    destinationID: id,
                    opaqueValue: try JSONEncoder().encode(Binding(kind: kind, ids: ids)).base64EncodedString()
                  ),
                  let entry = WatchlistDestinationEntry(
                    kind: kind, externalIDs: ids, binding: binding,
                    presentation: item.title.map { MediaAliasPresentation(title: $0) },
                    attribution: .init(
                        source: .wetrakr,
                        sourceURL: URL(string: "https://wetrakr.com/\(kind == .movie ? "movies" : "shows")/\(item.id)")
                    )
                  ) else { throw AppError.invalidResponse }
            return entry
        }
    }

    private static func key(_ item: WetrakrMedia) -> String { "\(item.type):\(item.id)" }

    private func accessToken(scope: String, generation version: UInt64) async throws -> String {
        try check(scope: scope, version: version)
        guard let token = try await coordinator.accessToken(store: tokenStore.snapshot(), auth: auth)
        else { throw WatchlistDestinationError.authenticationRequired }
        try check(scope: scope, version: version)
        return token
    }
    private func check(scope: String, version: UInt64) throws {
        try Task.checkCancellation()
        guard generation.current == version, reconciliationScope == scope
        else { throw WatchlistDestinationError.authenticationRequired }
    }

    private nonisolated func mapped<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        do { return try await operation() }
        catch let error as WatchlistDestinationError { throw error }
        catch AppError.unauthorized { throw WatchlistDestinationError.authenticationRequired }
        catch AppError.rateLimited(let delay) { throw WatchlistDestinationError.rateLimited(retryAfter: delay) }
        catch AppError.notFound { throw WatchlistDestinationError.unsupportedIdentity }
        catch WetrakrError.itemRejected { throw WatchlistDestinationError.permanent }
        catch { throw WatchlistDestinationError.transient }
    }
}
