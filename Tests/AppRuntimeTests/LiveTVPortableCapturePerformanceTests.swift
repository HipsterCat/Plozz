import Foundation
import XCTest
@testable import AppRuntime
@testable import CoreModels
@testable import TestSupportPerformance

@MainActor
final class LiveTVPortableCapturePerformanceTests: XCTestCase {
    private func inputs(count: Int) throws -> (LibraryChannelDefinition, LibraryChannelSnapshot) {
        let library = LibraryChannelLibrary(accountID: "account", libraryID: "library")
        let items = try (0..<count).map { index in
            try LibraryChannelItem(
                item: .init(id: "movie-\(index)", title: "Generated movie \(index)", kind: .movie, runtime: 3_600),
                library: library, serverID: "server", userID: "user"
            )
        }
        let snapshot = try LibraryChannelSnapshot(items: items, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        let definition = LibraryChannelDefinition(profileID: "profile", revisions: [
            .init(snapshotID: snapshot.id, recipe: .init(name: "Movies", libraries: [library]), epochSeconds: 1_800_000_000)
        ])
        return (definition, snapshot)
    }

    private func capture(count: Int) async throws -> [String: Int] {
        var (definition, snapshot) = try inputs(count: count)
        let encodes = EncodeCounter()
        let preparation = LiveTVPortableLibraryPreparation { definitions, snapshots in
            encodes.increment()
            return try LiveTVPortableLibraryExport(definitions: definitions, snapshots: snapshots)
        }
        let first = try await preparation.prepare(definitions: [definition], snapshots: [snapshot])
        for index in 1...5 {
            definition.publishedThrough = 1_800_000_000 + Int64(index * 3_600)
            let value = try await preparation.prepare(definitions: [definition], snapshots: [snapshot])
            XCTAssertEqual(value.state.definitions, [definition])
            XCTAssertEqual(value.state.snapshots, [snapshot])
            XCTAssertEqual(value.encodedRecordBytes, first.encodedRecordBytes)
        }
        XCTAssertEqual(first.state.definitions.first?.publishedThrough, 0)
        snapshot = try LibraryChannelSnapshot(
            items: Array(snapshot.items.dropLast()), createdAt: Date(timeIntervalSince1970: 1_800_086_400)
        )
        definition.revisions = [
            .init(snapshotID: snapshot.id, recipe: definition.revisions[0].recipe, epochSeconds: 1_800_086_400)
        ]
        let changed = try await preparation.prepare(definitions: [definition], snapshots: [snapshot])
        XCTAssertEqual(changed.state.snapshots, [snapshot])
        return [
            "captures": 7, "fullSnapshotEncodes": encodes.value,
            "initialItems": count, "changedItems": snapshot.items.count,
            "initialEncodedBytes": first.encodedRecordBytes
        ]
    }

    func testDefinitionOnlyCapturesReuseValidatedImmutableRecordBytes() async throws {
        let counters = try await capture(count: 20)
        XCTAssertEqual(counters["fullSnapshotEncodes"], 2)
    }

    func testDefinitionReuseStillRejectsInvalidRevisionsAndPreservesLastValidExport() async throws {
        let (definition, snapshot) = try inputs(count: 20)
        let preparation = LiveTVPortableLibraryPreparation()
        let first = try await preparation.prepare(definitions: [definition], snapshots: [snapshot])
        var invalid = definition
        invalid.revisions = []
        do {
            _ = try await preparation.prepare(definitions: [invalid], snapshots: [snapshot])
            XCTFail("Reusing snapshot bytes must not bypass definition validation.")
        } catch {
            XCTAssertTrue(error is LibraryChannelError || error is LiveTVPortableStateError)
        }
        let restored = try await preparation.prepare(definitions: [definition], snapshots: [snapshot])
        XCTAssertEqual(restored.state, first.state)
    }

    func testAnotherProfileCannotUseTheDefinitionOnlyFastPath() async throws {
        let (definition, snapshot) = try inputs(count: 20)
        let encodes = EncodeCounter()
        let preparation = LiveTVPortableLibraryPreparation { definitions, snapshots in
            encodes.increment()
            return try LiveTVPortableLibraryExport(definitions: definitions, snapshots: snapshots)
        }
        _ = try await preparation.prepare(definitions: [definition], snapshots: [snapshot])
        let other = LibraryChannelDefinition(profileID: "other-profile", revisions: definition.revisions)
        let value = try await preparation.prepare(definitions: [other], snapshots: [snapshot])
        XCTAssertEqual(value.state.definitions, [other])
        XCTAssertEqual(encodes.value, 2)
    }

    func testChangedInputsCannotReuseBytesMerelyBecauseTheSnapshotIDMatches() async throws {
        let (definition, snapshot) = try inputs(count: 20)
        let preparation = LiveTVPortableLibraryPreparation()
        let first = try await preparation.prepare(definitions: [definition], snapshots: [snapshot])
        let changed = try LibraryChannelSnapshot(
            id: snapshot.id, items: Array(snapshot.items.dropLast()), createdAt: snapshot.createdAt
        )
        let next = try await preparation.prepare(definitions: [definition], snapshots: [changed])
        XCTAssertEqual(next.state.snapshots, [changed])
        XCTAssertLessThan(next.encodedRecordBytes, first.encodedRecordBytes)
    }

    func testPerformanceDefinitionOnlyCaptures() async throws {
        try PerformanceProbe.requireEnabled()
        try await PerformanceProbe.measure(self, scenario: "live-tv-schedule-capture") {
            try await self.capture(count: 12_000)
        }
    }
}

private final class EncodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
