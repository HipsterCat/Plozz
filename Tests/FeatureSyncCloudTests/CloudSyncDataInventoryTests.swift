import CoreModels
import CoreSecureStore
import Foundation
import XCTest
@testable import FeatureSyncCloud

final class CloudSyncDataInventoryTests: XCTestCase {
    private struct PrimaryState: Encodable { let ledger: SyncLedger }

    func testColdErasureDoesNotRestoreOldRecordsWhilePersisting() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        var ledger = SyncLedger()
        _ = ledger.reconcileLocal(desired: ["profile:p": Data([1])], now: 1)
        try JSONEncoder().encode(PrimaryState(ledger: ledger)).write(to: file)
        let configuration = CloudConfigSyncService.Configuration(
            containerIdentifier: "iCloud.test", stateFileURL: file,
            isEnabled: { false }, captureRecords: { $0 }, applyRecords: { _ in }
        )
        let service = CloudConfigSyncService(configuration)
        let cleared = await service.clearErasedLocalState()
        XCTAssertTrue(cleared)
        let restored = CloudConfigSyncService(configuration)
        let inventory = try await restored.dataInventory()
        XCTAssertEqual(inventory.recordCount, 0)
        XCTAssertEqual(inventory.pendingUploads, 0)
    }

    func testCountsCanonicalLocalBytesAndSeparatesPendingDeletions() {
        var ledger = SyncLedger()
        _ = ledger.applyFetched(saved: [
            .init(recordName: "keep", value: Data(repeating: 1, count: 10), editedAt: 1, systemFields: Data()),
            .init(recordName: "delete", value: Data(repeating: 2, count: 30), editedAt: 1, systemFields: Data())
        ], deleted: [], now: 1)
        _ = ledger.reconcileLocal(
            desired: ["keep": Data(repeating: 3, count: 20), "new": Data(repeating: 4, count: 7)],
            now: 2
        )
        var inventory = SyncDataInventory()
        inventory.include(ledger) { _ in .settings }
        XCTAssertEqual(inventory.recordCount, 2)
        XCTAssertEqual(inventory.payloadBytes, 27)
        XCTAssertEqual(inventory.pendingUploads, 2)
        XCTAssertEqual(inventory.pendingUploadBytes, 27)
        XCTAssertEqual(inventory.pendingDeletions, 1)
        XCTAssertEqual(inventory.rows.map(\.category), [.settings])
    }

    func testUnchangedSnapshotBytesRemainInInventoryButAreNotPendingUploads() {
        let name = LiveTVPortableRecordKey(
            profileID: "profile", kind: .snapshot, entityID: "snapshot.0"
        ).recordName
        let value = Data(repeating: 7, count: 128 * 1_024)
        var ledger = SyncLedger()
        _ = ledger.reconcileLocal(desired: [name: value], now: 1)
        ledger.applySendSuccess(recordName: name, savedValue: value, savedEditedAt: 1, systemFields: Data())
        _ = ledger.reconcileLocal(desired: [name: value], now: 2)
        var inventory = SyncDataInventory()
        inventory.include(ledger) { _ in .libraryChannelSchedules }
        XCTAssertEqual(inventory.payloadBytes, Int64(value.count))
        XCTAssertEqual(inventory.pendingUploadBytes, 0)
        XCTAssertEqual(inventory.pendingUploads, 0)
        XCTAssertTrue(ledger.pendingUploads().isEmpty)
    }

    func testRestoredInventoryClassifiesEveryChannelWithoutCloudKit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var primary = SyncLedger()
        _ = primary.reconcileLocal(desired: [
            "profile:p": Data(repeating: 0, count: 3),
            "membership:p": Data(repeating: 0, count: 4),
            "descriptor:share:smb://example.test/folder": Data(repeating: 0, count: 5),
            "setting:p:some-key": Data(repeating: 0, count: 6),
            "removal:old": Data(repeating: 0, count: 7),
            "future:opaque": Data(repeating: 0, count: 8)
        ], now: 1)
        let file = folder.appendingPathComponent("primary.json")
        try JSONEncoder().encode(PrimaryState(ledger: primary)).write(to: file)
        let id = UUID().uuidString
        let schemas: [CloudSyncSchemaDescriptor] = [.mediaStateV1, .liveTVStateV1, .liveTVSourcesV1, .trackerTokensV1]
        let records = [
            ["watchlist:p:\(id)": Data(repeating: 0, count: 11), "alias:p:\(id)": Data(repeating: 0, count: 12)],
            [
                "favorite:p:channel": Data(repeating: 0, count: 13),
                LiveTVPortableRecordKey(profileID: "p", kind: .library, entityID: id).recordName:
                    Data(repeating: 0, count: 16),
                LiveTVPortableRecordKey(profileID: "p", kind: .snapshot, entityID: "\(id).0").recordName:
                    Data(repeating: 0, count: 17)
            ],
            ["source:p:playlist": Data(repeating: 0, count: 14)],
            ["trackerToken:opaque": Data(repeating: 0, count: 15)]
        ]
        var channels: [CloudConfigSyncService.ChannelConfiguration] = []
        for (index, schema) in schemas.enumerated() {
            var ledger = SyncLedger()
            _ = ledger.reconcileLocal(desired: records[index], now: 1)
            let url = folder.appendingPathComponent("channel-\(index).json")
            let codec = schema.encryptsValue
                ? CloudSyncStateCodec(context: schema.zoneName, secureStore: InMemorySecureStore()) : nil
            if schema.encryptsValue || schema == .liveTVStateV1 {
                try CloudSyncSealedLedger.save(ledger, to: url, codec: codec, authority: nil)
            } else {
                try JSONEncoder().encode(ledger).write(to: url)
            }
            channels.append(.init(
                schema: schema, stateFileURL: url, captureRecords: { $0 }, applyRecords: { _ in },
                stateCodec: codec
            ))
        }
        let service = CloudConfigSyncService(.init(
            containerIdentifier: "iCloud.test", stateFileURL: file,
            isEnabled: { false }, captureRecords: { $0 }, applyRecords: { _ in }
        ), channels: channels)
        let inventory = try await service.dataInventory()
        XCTAssertEqual(inventory.rows.map(\.category), SyncDataInventory.Category.allCases)
        XCTAssertEqual(inventory.recordCount, 13)
        XCTAssertEqual(inventory.payloadBytes, 131)
        XCTAssertEqual(inventory.pendingUploads, 13)
        XCTAssertEqual(inventory.pendingUploadBytes, 131)
        XCTAssertEqual(inventory.rows.first { $0.category == .liveTVPreferences }?.payloadBytes, 13)
        XCTAssertEqual(inventory.rows.first { $0.category == .libraryChannelSchedules }?.payloadBytes, 33)
    }
}
