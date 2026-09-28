import Foundation

/// One snapshot per (library, sort) within a provider's account session. A
/// fresh first page updates membership; subsequent sparse pages never re-probe.
public actor VideoPlaylistSnapshotCache {
    private struct InFlight {
        let id: UUID
        let task: Task<[MediaItem], Error>
        var waiters: Set<UUID>
    }

    private var snapshots: [String: [MediaItem]] = [:]
    private var inFlight: [String: InFlight] = [:]

    public init() {}

    public func snapshot(
        key: String, refresh: Bool,
        load: @escaping @Sendable () async throws -> [MediaItem]
    ) async throws -> [MediaItem] {
        try Task.checkCancellation()
        let waiterID = UUID()
        let request: InFlight
        if var existing = inFlight[key] {
            existing.waiters.insert(waiterID)
            inFlight[key] = existing
            request = existing
        } else {
            if !refresh, let cached = snapshots[key] { return cached }
            request = InFlight(id: UUID(), task: Task { try await load() }, waiters: [waiterID])
            inFlight[key] = request
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await request.task.value
            } onCancel: {
                Task { await self.cancelWaiter(key: key, id: request.id, waiterID: waiterID) }
            }
            try Task.checkCancellation()
            if inFlight[key]?.id == request.id {
                inFlight[key] = nil
                snapshots[key] = result
                if snapshots.count > 8 {
                    snapshots = [key: result]
                }
            }
            return result
        } catch {
            if Task.isCancelled {
                cancelWaiter(key: key, id: request.id, waiterID: waiterID)
            } else if inFlight[key]?.id == request.id {
                inFlight[key] = nil
            }
            throw error
        }
    }

    private func cancelWaiter(key: String, id: UUID, waiterID: UUID) {
        guard var request = inFlight[key], request.id == id else { return }
        guard request.waiters.remove(waiterID) != nil else { return }
        if request.waiters.isEmpty {
            inFlight[key] = nil
            request.task.cancel()
        } else {
            inFlight[key] = request
        }
    }
}
