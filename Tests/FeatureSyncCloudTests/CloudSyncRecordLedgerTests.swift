import CoreModels
import Darwin
import Foundation
import XCTest
@testable import FeatureSyncCloud

final class CloudSyncRecordLedgerTests: XCTestCase {
    private func location() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("live-tv.json")
    }

    private func fixture(count: Int = 32) -> SyncLedger {
        var desired: [String: Data] = [:]
        for index in 0..<count {
            desired["record-\(index)"] = Data(repeating: UInt8(index), count: 256 * 1_024)
        }
        var base = SyncLedger()
        _ = base.reconcileLocal(desired: desired, now: 10)
        for (name, value) in desired {
            base.applySendSuccess(
                recordName: name, savedValue: value, savedEditedAt: base.entries[name]?.editedAt ?? 10,
                systemFields: Data([1, 2, 3])
            )
        }
        var entries = base.entries
        entries["dirty"] = .init(
            syncedValue: Data([1]), syncedEditedAt: 10, systemFields: Data([2]),
            localValue: Data([3]), editedAt: 20, dirty: true
        )
        entries["deleted"] = .init(
            syncedValue: Data([1]), syncedEditedAt: 10, systemFields: nil,
            localValue: Data([1]), editedAt: 30, dirty: false, pendingDelete: true
        )
        entries["never-synced"] = .init(
            syncedValue: nil, syncedEditedAt: 0, systemFields: nil,
            localValue: Data(), editedAt: 40, dirty: true
        )
        return .init(checkpoint: base.checkpoint, entries: entries)
    }

    private func entries(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url.appendingPathExtension("entries"), includingPropertiesForKeys: [.fileSizeKey]
        )
    }

    func testMigrationHalvesDuplicatedPayloadsAndRepeatedAcknowledgementsDoNotAccumulateFiles() throws {
        let url = try location()
        var expected = fixture()
        let legacy = try JSONEncoder().encode(expected)
        try legacy.write(to: url)
        XCTAssertTrue(try XCTUnwrap(CloudSyncSealedLedger.load(from: url)).hasSamePersistedState(as: expected))
        let initialFiles = try Set(entries(url))
        let bytes = try initialFiles.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        XCTAssertLessThan(bytes, legacy.count * 55 / 100)
        XCTAssertLessThan(try Data(contentsOf: url).count, 16 * 1_024)
        for generation in 0..<12 {
            var values = expected.entries.mapValues(\.localValue)
            values["dirty"] = Data("changed-\(generation)".utf8)
            _ = expected.reconcileLocal(desired: values, now: Int64(50 + generation))
            expected.applySendSuccess(
                recordName: "dirty", savedValue: try XCTUnwrap(values["dirty"]),
                savedEditedAt: try XCTUnwrap(expected.entries["dirty"]).editedAt, systemFields: Data([8])
            )
            try CloudSyncSealedLedger.save(expected, to: url)
            let after = try Set(entries(url))
            XCTAssertEqual(after.count, expected.entries.count)
            XCTAssertGreaterThanOrEqual(initialFiles.intersection(after).count, 32)
            let restored = try XCTUnwrap(CloudSyncSealedLedger.load(from: url))
            XCTAssertTrue(restored.hasSamePersistedState(as: expected))
        }
    }

    func testInterruptedSaveGarbageIsReclaimedOnlyAfterTheCommittedIndexIsValidated() throws {
        let url = try location()
        let ledger = fixture(count: 1)
        try CloudSyncSealedLedger.save(ledger, to: url)
        let original = try Data(contentsOf: url)
        let orphan = url.appendingPathExtension("entries").appendingPathComponent("\(UUID().uuidString).record")
        try Data("interrupted payload".utf8).write(to: orphan)
        let unrelated = orphan.deletingLastPathComponent().appendingPathComponent("unknown.record")
        try Data([7]).write(to: unrelated)
        try Data("corrupt".utf8).write(to: url)
        XCTAssertThrowsError(try CloudSyncSealedLedger.load(from: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        try original.write(to: url)
        XCTAssertTrue(try XCTUnwrap(CloudSyncSealedLedger.load(from: url)).hasSamePersistedState(as: ledger))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertEqual(try Data(contentsOf: unrelated), Data([7]))
    }

    func testFailedMigrationPreservesTheOriginalLedgerAndRemovesUncommittedEntries() throws {
        let url = try location()
        var values = fixture(count: 1).entries
        values["oversized"] = .init(
            syncedValue: nil, syncedEditedAt: 0, systemFields: nil,
            localValue: Data(repeating: 1, count: 4 * 1_024 * 1_024), editedAt: 1, dirty: true
        )
        let ledger = SyncLedger(checkpoint: SyncLedger().checkpoint, entries: values)
        let original = try JSONEncoder().encode(ledger)
        try original.write(to: url)
        XCTAssertThrowsError(try CloudSyncSealedLedger.load(from: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try entries(url), [])
    }

    func testConcurrentOwnerCannotWriteOrCollectInProgressEntries() throws {
        let url = try location()
        let ledger = fixture(count: 1)
        try CloudSyncSealedLedger.save(ledger, to: url)
        let original = try Data(contentsOf: url)
        let orphan = url.appendingPathExtension("entries").appendingPathComponent("\(UUID().uuidString).record")
        try Data([1]).write(to: orphan)
        let descriptor = open(url.appendingPathExtension("lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try CloudSyncSealedLedger.load(from: url))
        XCTAssertThrowsError(try CloudSyncSealedLedger.save(SyncLedger(), to: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertEqual(flock(descriptor, LOCK_UN), 0)
        XCTAssertTrue(try XCTUnwrap(CloudSyncSealedLedger.load(from: url)).hasSamePersistedState(as: ledger))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testRestartBeforeFirstIndexCommitReclaimsOnlyUncommittedRecordFiles() throws {
        let url = try location()
        let folder = url.appendingPathExtension("entries")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let partial = folder.appendingPathComponent("\(UUID().uuidString).record")
        try Data([1, 2, 3]).write(to: partial)
        XCTAssertNil(try CloudSyncSealedLedger.load(from: url))
        XCTAssertEqual(try entries(url), [])
    }

    func testIndexWriteFailureKeepsThePreviousCommitAndRemovesNewEntries() throws {
        let url = try location()
        let folder = url.deletingLastPathComponent()
        let original = fixture(count: 1)
        try CloudSyncSealedLedger.save(original, to: url)
        let index = try Data(contentsOf: url)
        let files = try Set(entries(url))
        var updated = original
        var values = updated.entries.mapValues(\.localValue)
        values["record-0"] = Data([9])
        _ = updated.reconcileLocal(desired: values, now: 100)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer {
            do { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
            catch { XCTFail("Could not restore the owned fixture directory's permissions.") }
        }
        XCTAssertThrowsError(try CloudSyncSealedLedger.save(updated, to: url))
        XCTAssertEqual(try Data(contentsOf: url), index)
        XCTAssertEqual(try Set(entries(url)), files)
        XCTAssertTrue(try XCTUnwrap(CloudSyncSealedLedger.load(from: url)).hasSamePersistedState(as: original))
    }

    func testLegacyJSONLargerThan256MiBMigratesWithoutTruncation() throws {
        let url = try location()
        let ledger = fixture(count: 1)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        do {
            let whitespace = Data(repeating: 0x20, count: 8 * 1_024 * 1_024)
            for _ in 0..<32 { try handle.write(contentsOf: whitespace) }
            try handle.write(contentsOf: JSONEncoder().encode(ledger))
            try handle.close()
        } catch {
            try handle.close()
            throw error
        }
        XCTAssertGreaterThan(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 256 * 1_024 * 1_024)
        XCTAssertTrue(try XCTUnwrap(CloudSyncSealedLedger.load(from: url)).hasSamePersistedState(as: ledger))
        XCTAssertLessThan(try Data(contentsOf: url).count, 16 * 1_024)
    }

    func testRealLiveTVChannelMigratesAndRestoresAcrossServiceRestarts() async throws {
        let url = try location()
        let primary = url.deletingLastPathComponent().appendingPathComponent("primary.json")
        let ledger = fixture(count: 1)
        try JSONEncoder().encode(ledger).write(to: url)
        for _ in 0..<3 {
            let service = CloudConfigSyncService(.init(
                containerIdentifier: "iCloud.test", stateFileURL: primary,
                isEnabled: { false }, captureRecords: { $0 }, applyRecords: { _ in }
            ), channels: [.init(
                schema: .liveTVStateV1, stateFileURL: url,
                captureRecords: { $0 }, applyRecords: { _ in }
            )])
            let restored = try await service.restoredLedgers()
            XCTAssertTrue(try XCTUnwrap(restored.last).hasSamePersistedState(as: ledger))
            let persisted = await service.persist()
            XCTAssertTrue(persisted)
            XCTAssertEqual(try entries(url).count, ledger.entries.count)
        }
    }

    func testLegacyAtomicCleanupLeavesOtherFilesDirectoriesAndSymlinksAlone() throws {
        let url = try location()
        let root = url.deletingLastPathComponent()
        let manager = FileManager.default
        let abandoned = root.appendingPathComponent("NSIRD_Plozz_old")
        try manager.createDirectory(at: abandoned, withIntermediateDirectories: false)
        try Data([1]).write(to: abandoned.appendingPathComponent(url.lastPathComponent))
        let unrelated = root.appendingPathComponent("NSIRD_Plozz_unrelated")
        try manager.createDirectory(at: unrelated, withIntermediateDirectories: false)
        try Data([2]).write(to: unrelated.appendingPathComponent("credentials.json"))
        let mixed = root.appendingPathComponent("NSIRD_Plozz_mixed")
        try manager.createDirectory(at: mixed, withIntermediateDirectories: false)
        try Data([3]).write(to: mixed.appendingPathComponent(url.lastPathComponent))
        try Data([4]).write(to: mixed.appendingPathComponent("unknown"))
        let link = root.appendingPathComponent("NSIRD_Plozz_link")
        try manager.createSymbolicLink(at: link, withDestinationURL: unrelated)
        try CloudSyncSealedLedger.reclaimLegacyAtomicWrites(in: root, fileName: url.lastPathComponent)
        XCTAssertFalse(manager.fileExists(atPath: abandoned.path))
        XCTAssertEqual(try Data(contentsOf: unrelated.appendingPathComponent("credentials.json")), Data([2]))
        XCTAssertEqual(try Data(contentsOf: mixed.appendingPathComponent(url.lastPathComponent)), Data([3]))
        XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }
}
