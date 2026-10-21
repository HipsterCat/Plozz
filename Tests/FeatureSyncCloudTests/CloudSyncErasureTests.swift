import CloudKit
import XCTest
@testable import FeatureSyncCloud

@MainActor
final class CloudSyncErasureTests: XCTestCase {
    private let zones = [CKRecordZone.ID(zoneName: "config"), CKRecordZone.ID(zoneName: "credentials")]

    func testUnentitledTestHostNeverConstructsCloudKitOrTouchesLocalData() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = CloudConfigSyncService(.init(
            containerIdentifier: "iCloud.test", stateFileURL: folder.appendingPathComponent("state.json"),
            isEnabled: { false }, captureRecords: { $0 }, applyRecords: { _ in XCTFail("Must not apply.") }
        ))
        let result = await service.eraseAllServerData(
            authorized: { true }, stopSync: { XCTFail("Must not start erasure.") }
        )
        XCTAssertEqual(result, .unavailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testErasesUnmirroredAndDirectRecordsInBoundedBatches() async throws {
        var stored = Dictionary(uniqueKeysWithValues: zones.map { zone in
            (zone, (0..<250).map { CKRecord.ID(recordName: "unknown-\($0)", zoneID: zone) })
        })
        var enumerated: Set<CKRecordZone.ID> = []
        var batchSizes: [Int] = []
        try await CloudSyncErasure.run(zones: zones, validate: {}, records: { zone in
            enumerated.insert(zone)
            return stored[zone, default: []]
        }, delete: { ids in
            XCTAssertEqual(enumerated, Set(self.zones), "Do not delete before every inventory succeeds.")
            batchSizes.append(ids.count)
            for id in ids { stored[id.zoneID]?.removeAll { $0 == id } }
        })
        XCTAssertEqual(batchSizes, [200, 200, 100])
        XCTAssertTrue(stored.values.allSatisfy(\.isEmpty))
    }

    func testInventoryFailureNeverStartsDeletion() async {
        var deletes = 0
        do {
            try await CloudSyncErasure.run(zones: zones, validate: {}, records: { zone in
                if zone == self.zones[1] { throw CKError(.networkFailure) }
                return [CKRecord.ID(recordName: "remote", zoneID: zone)]
            }, delete: { _ in deletes += 1 })
            XCTFail("An incomplete inventory must fail.")
        } catch {}
        XCTAssertEqual(deletes, 0)
    }

    func testChangedAuthorizationStopsBeforeDestructiveBatch() async {
        var allowed = true
        var deletes = 0
        do {
            try await CloudSyncErasure.run(zones: [zones[0]], validate: {
                guard allowed else { throw CloudSyncErasure.Failure.authorizationChanged }
            }, records: { zone in
                allowed = false
                return [CKRecord.ID(recordName: "remote", zoneID: zone)]
            }, delete: { _ in deletes += 1 })
            XCTFail("Changed authorization must fail.")
        } catch CloudSyncErasure.Failure.authorizationChanged {
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(deletes, 0)
    }

    func testPartialDeleteFailureIsNotSuccess() async {
        var batches = 0
        do {
            try await CloudSyncErasure.run(zones: [zones[0]], validate: {}, records: { zone in
                (0..<250).map { CKRecord.ID(recordName: "\($0)", zoneID: zone) }
            }, delete: { _ in
                batches += 1
                if batches == 2 { throw CKError(.permissionFailure) }
            })
            XCTFail("Partial erasure must fail.")
        } catch {}
        XCTAssertEqual(batches, 2)
    }

    func testPeerRepublishingIsNotReportedAsAnEmptyCloud() async {
        do {
            try await CloudSyncErasure.run(zones: [zones[0]], validate: {}, records: { zone in
                [CKRecord.ID(recordName: "peer-upload", zoneID: zone)]
            }, delete: { _ in })
            XCTFail("Remaining records must fail verification.")
        } catch CloudSyncErasure.Failure.recordsRemain {
        } catch { XCTFail("Unexpected error: \(error)") }
    }
}
