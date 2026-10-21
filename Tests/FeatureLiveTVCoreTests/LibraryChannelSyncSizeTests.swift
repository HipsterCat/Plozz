import Foundation
import XCTest
@testable import CoreModels
@testable import FeatureLiveTVCore
@testable import TestSupportPerformance

@MainActor
final class LibraryChannelSyncSizeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let library = LibraryChannelLibrary(accountID: "account", libraryID: "library")

    private func groups(count: Int) throws -> [LibraryChannelAutomaticPlanner.Group] {
        let items = try (0..<count).map { index in
            try LibraryChannelItem(
                item: .init(id: "movie-\(index)", title: "Generated film \(index)", kind: .movie, runtime: 3_600),
                library: library, serverID: "server", userID: "user"
            )
        }
        return (0..<6).map { index -> LibraryChannelAutomaticPlanner.Group in
            let recipe = LibraryChannelRecipe(
                name: "Channel \(index)", libraries: [library], ordering: .seededShuffle,
                seed: UInt64(index + 1)
            )
            let selected: [LibraryChannelItem] = index < 4 ? items : Array(items.prefix(count / 2))
            return LibraryChannelAutomaticPlanner.Group(
                key: "v1/fixture-\(index)", recipe: recipe, items: selected, isCatchall: index == 0
            )
        }
    }

    private func publication(
        _ groups: [LibraryChannelAutomaticPlanner.Group]
    ) throws -> LibraryChannelPublication {
        try LibraryChannelAutomaticPublication.prepare(
            groups: groups, profileID: "profile", previous: [], snapshots: [:],
            schedules: [:], blockedSourceIDs: [], now: now
        )
    }

    private func verifySchedules(
        _ result: LibraryChannelPublication, groups: [LibraryChannelAutomaticPlanner.Group]
    ) throws {
        for group in groups {
            let id = LibraryChannelAutomaticIdentity.channelID(profileID: "profile", key: group.key)
            let definition = try XCTUnwrap(result.definitions.first { $0.id == id })
            let schedule = try XCTUnwrap(result.schedules[id])
            let independent = try LibraryChannelSnapshot(items: group.items, createdAt: now)
            var reference = definition
            reference.revisions = [.init(
                snapshotID: independent.id, recipe: group.recipe, epochSeconds: 1_800_000_000
            )]
            let expected = try LibraryChannelSchedule(
                definition: reference, snapshots: [independent.id: independent]
            )
            for offset in [0.0, 3_601.25, 86_400.0, 1_800_000.0] {
                let at = now.addingTimeInterval(offset)
                let actual = try schedule.slot(at: at)
                let original = try expected.slot(at: at)
                XCTAssertEqual(actual.item, original.item)
                XCTAssertEqual(actual.startSeconds, original.startSeconds)
                XCTAssertEqual(actual.offset(at: at), original.offset(at: at))
            }
        }
    }

    func testEquivalentInputsShareSnapshotsWithoutCombiningChannelRecipes() throws {
        let groups = try groups(count: 20)
        let result = try publication(groups)
        XCTAssertEqual(result.definitions.count, 6)
        XCTAssertEqual(result.snapshots.count, 2)
        XCTAssertEqual(result.staged.count, 2)
        XCTAssertEqual(result.snapshots.values.reduce(0) { $0 + $1.items.count }, 30)
        try verifySchedules(result, groups: groups)
        let restored = try Dictionary(uniqueKeysWithValues: result.snapshots.values.map { snapshot in
            let parts = try LiveTVPortableSnapshots.partition(snapshot).map { part in
                let record = LiveTVPortableRecord(snapshot: part)
                let key = LiveTVPortableRecordKey(profileID: "profile", kind: .snapshot, entityID: part.entityID)
                return try XCTUnwrap(LiveTVPortableRecord.decode(record.encoded(), key: key).snapshot)
            }
            return (snapshot.id, try LiveTVPortableSnapshots.assemble(parts))
        })
        XCTAssertEqual(restored, result.snapshots)
        let refreshed = try LibraryChannelAutomaticPublication.prepare(
            groups: groups, profileID: "profile", previous: result.definitions, snapshots: result.snapshots,
            schedules: result.schedules, blockedSourceIDs: [], now: now.addingTimeInterval(10)
        )
        XCTAssertEqual(refreshed.definitions, result.definitions)
        XCTAssertEqual(refreshed.snapshots, result.snapshots)
        XCTAssertTrue(refreshed.staged.isEmpty)
    }

    func testRecipeEditReusesInputsButPreservesPublishedRevisionsAndBoundaries() throws {
        var groups = try groups(count: 20)
        let original = try publication(groups)
        let oldGroup = groups[0]
        var recipe = oldGroup.recipe
        recipe.seed += 100
        groups[0] = .init(
            key: oldGroup.key, recipe: recipe, items: oldGroup.items, isCatchall: oldGroup.isCatchall
        )
        let changed = try LibraryChannelAutomaticPublication.prepare(
            groups: groups, profileID: "profile", previous: original.definitions, snapshots: original.snapshots,
            schedules: original.schedules, blockedSourceIDs: [], now: now.addingTimeInterval(10)
        )
        let before = try XCTUnwrap(original.definitions.first)
        let after = try XCTUnwrap(changed.definitions.first { $0.id == before.id })
        XCTAssertEqual(after.revisions.count, 2)
        XCTAssertEqual(after.revisions.first, before.revisions.first)
        XCTAssertEqual(after.revisions.last?.snapshotID, before.revisions.last?.snapshotID)
        XCTAssertEqual(after.revisions.last?.epochSeconds, 1_800_003_600)
        XCTAssertEqual(changed.snapshots, original.snapshots)
        XCTAssertTrue(changed.staged.isEmpty)
    }

    func testMatchingTitlesAndIDsFromDifferentServerUsersDoNotShareInputs() throws {
        let original = try XCTUnwrap(groups(count: 20).first)
        let otherItems = try original.items.map { item in
            try LibraryChannelItem(
                item: .init(id: item.itemID, title: item.title, kind: item.kind, runtime: Double(item.durationSeconds)),
                library: library, serverID: item.serverID, userID: "other-user"
            )
        }
        let other = LibraryChannelAutomaticPlanner.Group(
            key: "v1/other-user", recipe: original.recipe, items: otherItems, isCatchall: false
        )
        let result = try publication([original, other])
        XCTAssertEqual(result.snapshots.count, 2)
        XCTAssertEqual(Set(result.snapshots.values.map { $0.items[0].userID }), ["user", "other-user"])
    }

    func testPerformanceLibrarySyncPayload() async throws {
        try PerformanceProbe.requireEnabled()
        func catalog(uppercase: Bool) throws -> LibraryChannelAutomaticCatalog {
            let entries = try (0..<4_000).map { index -> LibraryChannelAutomaticCatalog.Entry in
                let item = try LibraryChannelItem(
                    item: .init(id: "movie-\(index)", title: "Generated film \(index)", kind: .movie, runtime: 3_600),
                    library: library, serverID: "server", userID: "user"
                )
                let genre = index.isMultiple(of: 2) ? "Drama" : "Comedy"
                let studio = index < 3_000 ? "Studio Alpha" : "Studio Beta"
                return .init(
                    item: item, genres: [uppercase ? genre.uppercased() : genre],
                    studios: [uppercase ? studio.uppercased() : studio], directors: [], year: nil
                )
            }
            return LibraryChannelAutomaticCatalog(entries: entries)
        }
        let originalCatalog = try catalog(uppercase: false)
        let refreshedCatalog = try catalog(uppercase: true)
        try await PerformanceProbe.measure(self, scenario: "live-tv-schedule-sync") {
            let groups = try LibraryChannelAutomaticPlanner.groups(catalog: originalCatalog, profileID: "profile")
            let refreshedGroups = try LibraryChannelAutomaticPlanner.groups(
                catalog: refreshedCatalog, profileID: "profile"
            )
            let original = try self.publication(groups)
            let result = try LibraryChannelAutomaticPublication.prepare(
                groups: refreshedGroups, profileID: "profile", previous: original.definitions,
                snapshots: original.snapshots, schedules: original.schedules, blockedSourceIDs: [],
                now: self.now.addingTimeInterval(10)
            )
            XCTAssertEqual(result.definitions.count, 5)
            for definition in result.definitions {
                let previous = try XCTUnwrap(original.definitions.first { $0.id == definition.id })
                XCTAssertEqual(definition.revisions.first, previous.revisions.first)
                let before = try XCTUnwrap(original.schedules[definition.id]).slot(at: self.now)
                let after = try XCTUnwrap(result.schedules[definition.id]).slot(at: self.now)
                XCTAssertEqual(before.item, after.item)
                XCTAssertEqual(before.startSeconds, after.startSeconds)
            }
            let export = try LiveTVPortableLibraryExport(
                definitions: result.definitions, snapshots: Array(result.snapshots.values)
            )
            return [
                "channels": result.definitions.count,
                "snapshots": result.snapshots.count,
                "snapshotItemReferences": result.snapshots.values.reduce(0) { $0 + $1.items.count },
                "encodedSnapshotBytes": export.encodedRecordBytes
            ]
        }
    }
}
