import CloudKit
import Foundation

/// Enumerate every zone before deleting anything. Never substitute the local
/// ledger for server inventory: it can omit records from other devices.
enum CloudSyncErasure {
    enum Failure: Error {
        case authorizationChanged
        case recordsRemain
    }

    static func run(
        zones: [CKRecordZone.ID],
        validate: () async throws -> Void,
        records: (CKRecordZone.ID) async throws -> [CKRecord.ID],
        delete: ([CKRecord.ID]) async throws -> Void
    ) async throws {
        var inventory: [CKRecord.ID] = []
        for zone in zones {
            try Task.checkCancellation()
            try await validate()
            inventory.append(contentsOf: try await records(zone))
        }
        for start in stride(from: 0, to: inventory.count, by: 200) {
            try Task.checkCancellation()
            try await validate()
            try await delete(Array(inventory[start..<min(start + 200, inventory.count)]))
        }
        for zone in zones {
            try Task.checkCancellation()
            try await validate()
            guard try await records(zone).isEmpty else { throw Failure.recordsRemain }
        }
        try await validate()
    }

    static func recordIDs(
        in zone: CKRecordZone.ID, database: CKDatabase
    ) async throws -> [CKRecord.ID] {
        var ids: Set<CKRecord.ID> = []
        var token: CKServerChangeToken?
        do {
            repeat {
                try Task.checkCancellation()
                let page = try await database.recordZoneChanges(
                    inZoneWith: zone, since: token, desiredKeys: []
                )
                for (id, result) in page.modificationResultsByID {
                    _ = try result.get()
                    ids.insert(id)
                }
                for deletion in page.deletions { ids.remove(deletion.recordID) }
                token = page.changeToken
                if !page.moreComing { break }
            } while true
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return []
        }
        return Array(ids)
    }

    static func delete(_ ids: [CKRecord.ID], database: CKDatabase) async throws {
        let results = try await database.modifyRecords(saving: [], deleting: ids, atomically: false)
        for id in ids {
            guard let result = results.deleteResults[id] else { throw Failure.recordsRemain }
            do { try result.get() }
            catch let error as CKError where error.code == .unknownItem { continue }
        }
    }
}
