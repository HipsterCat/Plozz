import Foundation
import XCTest
@testable import CoreModels

final class LiveTVPortableRecordStorageTests: XCTestCase {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    func testRepeatedExportsNeverPublishTemporaryPayloadFiles() throws {
        let root = try root()
        let input = Data(repeating: 0x5a, count: 8 * 1_024 * 1_024)
        for _ in 0..<48 {
            try autoreleasepool {
                let storage = LiveTVPortableRecordStorage(temporaryDirectory: root)
                let value = try storage.store(input)
                XCTAssertEqual(value, input)
                XCTAssertEqual(storage.residentBytes, 0)
                XCTAssertEqual(storage.storedBytes, input.count)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [],
                               "Even a still-live export must leave no linked payload behind on termination.")
            }
        }
    }

    func testMappingOutlivesStorageAndCopiesRemainIndependent() throws {
        let root = try root()
        let input = Data(repeating: 0x5a, count: 8 * 1_024 * 1_024)
        var storage: LiveTVPortableRecordStorage? = .init(temporaryDirectory: root)
        weak var retired = storage
        let mapped = try XCTUnwrap(storage).store(input)
        storage = nil
        XCTAssertNil(retired)
        var copy = mapped
        copy[0] = 0
        XCTAssertEqual(mapped, input)
        XCTAssertEqual(copy[0], 0)
        XCTAssertEqual(copy.last, input.last)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testFailedSpillDoesNotConsumeQuotaAndCanRetry() throws {
        let root = try root()
        let missing = root.appendingPathComponent("missing")
        let storage = LiveTVPortableRecordStorage(temporaryDirectory: missing)
        let resident = Data(repeating: 1, count: LiveTVPortableRecordStorage.maximumResidentBytes)
        _ = try storage.store(resident)
        XCTAssertThrowsError(try storage.store(Data(repeating: 2, count: 1_024)))
        XCTAssertEqual(storage.storedBytes, resident.count)
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: false)
        XCTAssertEqual(try storage.store(Data([3])), Data([3]))
        XCTAssertEqual(storage.storedBytes, resident.count + 1)
    }

    func testCancellationDoesNotPublishOrChargeAnExport() async throws {
        let root = try root()
        try await Task.detached {
            let storage = LiveTVPortableRecordStorage(temporaryDirectory: root)
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(try storage.store(Data(repeating: 1, count: 8 * 1_024 * 1_024))) {
                XCTAssertTrue($0 is CancellationError)
            }
            XCTAssertEqual(storage.storedBytes, 0)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        }.value
    }

    func testUpgradeReclaimsOnlyKnownLegacyExportFilesWithoutTouchingLiveMappings() throws {
        let root = try root()
        let manager = FileManager.default
        let legacy = root.appendingPathComponent("plozz-live-tv-records-\(UUID().uuidString)")
        try manager.createDirectory(at: legacy, withIntermediateDirectories: false)
        try Data([1]).write(to: legacy.appendingPathComponent("0.record"))
        let unrelated = root.appendingPathComponent("plozz-live-tv-records-not-a-uuid")
        try manager.createDirectory(at: unrelated, withIntermediateDirectories: false)
        try Data([2]).write(to: unrelated.appendingPathComponent("0.record"))
        let mixed = root.appendingPathComponent("plozz-live-tv-records-\(UUID().uuidString)")
        try manager.createDirectory(at: mixed, withIntermediateDirectories: false)
        try Data([3]).write(to: mixed.appendingPathComponent("profiles.json"))
        let link = root.appendingPathComponent("plozz-live-tv-records-\(UUID().uuidString)")
        try manager.createSymbolicLink(at: link, withDestinationURL: unrelated)
        let input = Data(repeating: 7, count: 8 * 1_024 * 1_024)
        let storage = LiveTVPortableRecordStorage(temporaryDirectory: root)
        let mapped = try storage.store(input)
        for _ in 0..<3 { try LiveTVPortableRecordStorage.reclaimLegacyFiles(in: root) }
        XCTAssertFalse(manager.fileExists(atPath: legacy.path))
        XCTAssertEqual(try Data(contentsOf: unrelated.appendingPathComponent("0.record")), Data([2]))
        XCTAssertEqual(try Data(contentsOf: mixed.appendingPathComponent("profiles.json")), Data([3]))
        XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertEqual(mapped, input)
    }
}
