import XCTest
import CoreModels
import MediaTransportCore
@testable import ProviderShare

/// Guards the two rules that decide whether a directory is re-listed.
///
/// Both are correctness-critical in the same direction: getting them wrong means
/// a folder is skipped forever and newly-added media never appears. The tests
/// therefore lean on the conservative side — a rule may cost an extra listing,
/// but must never make something invisible.
final class ShareScannerIncrementalTests: XCTestCase {

    // MARK: Which directories have children

    /// A directory is only skippable when it has no subdirectories, because one
    /// listing is what yields its children's mtimes — skipping the parent
    /// forfeits that and forces every child to be listed instead.
    func testParentPathsIdentifiesDirectoriesWithChildren() {
        let recorded = [
            "Movies",
            "Movies/Arrival (2016)",
            "TV",
            "TV/Fargo",
            "TV/Fargo/Season 01"
        ]
        let parents = ShareScanner.parentPaths(of: recorded)

        // Interior nodes: must be listed even when unchanged.
        XCTAssertTrue(parents.contains("Movies"))
        XCTAssertTrue(parents.contains("TV"))
        XCTAssertTrue(parents.contains("TV/Fargo"))
        // Leaves: skippable when their mtime is unchanged.
        XCTAssertFalse(parents.contains("Movies/Arrival (2016)"))
        XCTAssertFalse(parents.contains("TV/Fargo/Season 01"))
    }

    /// Top-level directories make the share root a parent, so the root is never
    /// mistaken for a leaf and skipped — which would hide the entire library.
    func testTopLevelDirectoriesMakeTheRootAParent() {
        XCTAssertTrue(ShareScanner.parentPaths(of: ["Movies"]).contains(""))
    }

    func testParentPathsIgnoresTheRootItself() {
        XCTAssertTrue(ShareScanner.parentPaths(of: [""]).isEmpty)
        XCTAssertTrue(ShareScanner.parentPaths(of: []).isEmpty)
    }

    // MARK: Racy timestamps

    /// A settled mtime is trusted, so an unchanged folder can be skipped.
    func testTrustsAnMTimeComfortablyInThePast() {
        let now = Date()
        let settled = now.addingTimeInterval(-3600)
        XCTAssertEqual(ShareScanner.trustworthyMTime(settled, now: now), settled)
    }

    /// The racy-timestamp case: a file landing in the same second the scan reads
    /// the directory leaves an mtime equal to the one recorded, so the folder
    /// would look unchanged forever. Refusing to record it costs one listing next
    /// pass and self-corrects.
    func testRejectsAnMTimeTooCloseToNow() {
        let now = Date()
        XCTAssertNil(ShareScanner.trustworthyMTime(now, now: now))
        XCTAssertNil(ShareScanner.trustworthyMTime(now.addingTimeInterval(-0.5), now: now))
    }

    /// One-second filesystem granularity means the whole tick has to be excluded,
    /// not just the instant.
    func testRejectsAnMTimeInsideTheGranularityWindow() {
        let now = Date()
        let justInside = now.addingTimeInterval(-(ShareScanner.racyMTimeWindow - 0.1))
        XCTAssertNil(ShareScanner.trustworthyMTime(justInside, now: now))

        let justOutside = now.addingTimeInterval(-(ShareScanner.racyMTimeWindow + 0.1))
        XCTAssertEqual(ShareScanner.trustworthyMTime(justOutside, now: now), justOutside)
    }

    /// A server clock running ahead yields a future mtime. Treated as untrusted
    /// rather than clamped: the comparison it would feed is equality, and a
    /// future stamp says the folder may still be being written.
    func testRejectsAFutureMTime() {
        let now = Date()
        XCTAssertNil(ShareScanner.trustworthyMTime(now.addingTimeInterval(60), now: now))
    }

    /// A transport that reports no directory mtime (some SMB/NFS servers) records
    /// nothing, so the folder is always listed.
    func testRejectsAMissingMTime() {
        XCTAssertNil(ShareScanner.trustworthyMTime(nil))
    }

    private actor ListingRecorder {
        var paths: [String] = []
        func record(_ path: String) { paths.append(path) }
    }

    private func directory(_ path: String, timestamp: TimeInterval = 100) throws -> RemoteFileEntry {
        try RemoteFileEntry(
            relativePath: path, kind: .directory,
            modifiedAt: Date(timeIntervalSince1970: timestamp)
        )
    }

    private func video(_ path: String, size: Int64 = 1_000) throws -> RemoteFileEntry {
        try RemoteFileEntry(
            relativePath: path, kind: .file, size: size,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func scanner(
        _ store: ShareCatalogStore,
        tree: [String: [RemoteFileEntry]],
        recorder: ListingRecorder = ListingRecorder(),
        failures: Set<String> = [],
        gate: MetadataAsyncTestGate? = nil
    ) -> ShareScanner {
        ShareScanner(store: store, concurrency: 1, makeLister: {
            ShareScanner.ScanLister(list: { path in
                await recorder.record(path)
                if path == "B", let gate { await gate.wait() }
                if failures.contains(path) { throw URLError(.cannotConnectToHost) }
                return tree[path] ?? []
            }, close: {})
        })
    }

    func testUnchangedLibraryListsOnlyInteriorFoldersAndWritesInventoryOnce() async throws {
        let fixture = ShareCatalogSQLiteFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        _ = await store.movies(offset: 0, limit: 1)
        try fixture.execute("""
        CREATE TABLE inventory_writes(value INTEGER NOT NULL);
        INSERT INTO inventory_writes VALUES(0);
        CREATE TRIGGER inventory_insert AFTER INSERT ON playable_inventory BEGIN
          UPDATE inventory_writes SET value=value+1;
        END;
        CREATE TRIGGER inventory_update AFTER UPDATE ON playable_inventory BEGIN
          UPDATE inventory_writes SET value=value+1;
        END;
        """)
        let count = 200
        var tree: [String: [RemoteFileEntry]] = ["": [try directory("Movies")]]
        tree["Movies"] = try (0..<count).map { try directory("Movies/Film \($0) (2000)") }
        for index in 0..<count {
            let path = "Movies/Film \(index) (2000)"
            tree[path] = [try video("\(path)/Film \(index) (2000).mkv")]
        }
        let initial = await scanner(store, tree: tree).scan()
        XCTAssertEqual(initial, .completedClean)
        XCTAssertEqual(try fixture.integer("SELECT value FROM inventory_writes;"), count,
                       "each discovered playable path should be persisted once, not once per asset plus inventory")
        try fixture.execute("UPDATE inventory_writes SET value=0;")
        let recorder = ListingRecorder()
        let outcome = await scanner(store, tree: tree, recorder: recorder).scan(deep: false)
        let paths = await recorder.paths
        XCTAssertEqual(outcome, .completedClean)
        XCTAssertEqual(paths, ["", "Movies"], "unchanged media leaves must not incur network listings")
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets;"), count)
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM playable_inventory;"), count)
        XCTAssertEqual(try fixture.integer("SELECT value FROM inventory_writes;"), count)
    }

    func testDeepScanFindsMediaChangesEvenWhenDirectoryTimestampDoesNotMove() async throws {
        let fixture = ShareCatalogSQLiteFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let original: [String: [RemoteFileEntry]] = [
            "": [try directory("Movies")],
            "Movies": [try video("Movies/Old (2000).mkv")]
        ]
        _ = await scanner(store, tree: original).scan()
        let changed: [String: [RemoteFileEntry]] = [
            "": [try directory("Movies")],
            "Movies": [try video("Movies/New (2001).mkv")]
        ]
        let recorder = ListingRecorder()
        let outcome = await scanner(store, tree: changed, recorder: recorder).scan(deep: true)
        let paths = await recorder.paths
        XCTAssertEqual(outcome, .completedClean)
        XCTAssertEqual(paths, ["", "Movies"])
        XCTAssertEqual(try fixture.text("SELECT rel_path FROM assets;"), "Movies/New (2001).mkv")
        XCTAssertEqual(try fixture.text("SELECT rel_path FROM playable_inventory;"), "Movies/New (2001).mkv")
    }

    func testNormalScanFindsNestedAdditionsRenamesAndDeletions() async throws {
        let fixture = ShareCatalogSQLiteFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let original: [String: [RemoteFileEntry]] = [
            "": [try directory("TV")],
            "TV": [try directory("TV/Show")],
            "TV/Show": [try directory("TV/Show/Season 1")],
            "TV/Show/Season 1": [try video("TV/Show/Season 1/Show.S01E01.mkv")]
        ]
        _ = await scanner(store, tree: original).scan()
        var changed = original
        changed["TV/Show"] = [
            try directory("TV/Show/Season 1", timestamp: 200),
            try directory("TV/Show/Season 2")
        ]
        changed["TV/Show/Season 1"] = [try video("TV/Show/Season 1/Show.S01E02.mkv")]
        changed["TV/Show/Season 2"] = [try video("TV/Show/Season 2/Show.S02E01.mkv")]
        let outcome = await scanner(store, tree: changed).scan(deep: false)
        XCTAssertEqual(outcome, .completedClean)
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets;"), 2)
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets WHERE episode=1 AND season=1;"), 0)
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets WHERE season=2;"), 1)
    }

    private func cancellationTree() throws -> [String: [RemoteFileEntry]] {
        [
            "": [try directory("A"), try directory("B")],
            "A": [try directory("A/Kept")],
            "A/Kept": [try video("A/Kept/Kept (2000).mkv")],
            "B": [try directory("B/Pending")],
            "B/Pending": [try video("B/Pending/Pending (2001).mkv")]
        ]
    }

    func testCancellationDoesNotLoseUnflushedSkippedDirectories() async throws {
        let fixture = ShareCatalogSQLiteFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        var tree = try cancellationTree()
        _ = await scanner(store, tree: tree).scan()
        tree["B"] = [try directory("B/Pending", timestamp: 200)]
        let gate = MetadataAsyncTestGate()
        let interrupted = scanner(store, tree: tree, gate: gate)
        let task = Task { await interrupted.scan(deep: false) }
        await gate.waitUntilEntered()
        task.cancel()
        gate.open()
        _ = await task.value

        let outcome = await scanner(store, tree: tree).scan(deep: false)
        XCTAssertEqual(outcome, .completedClean)
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets;"), 2,
                       "a skipped folder must be stamped before saving a cancellation checkpoint")
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM playable_inventory;"), 2)
    }

    func testCancellationAfterListingFailureCannotResumeAsCleanAndPruneMissingSubtree() async throws {
        let fixture = ShareCatalogSQLiteFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        var tree = try cancellationTree()
        _ = await scanner(store, tree: tree).scan()
        tree["B"] = [try directory("B/Pending", timestamp: 200)]
        let gate = MetadataAsyncTestGate()
        let interrupted = scanner(store, tree: tree, failures: ["A"], gate: gate)
        let task = Task { await interrupted.scan(deep: false) }
        await gate.waitUntilEntered()
        task.cancel()
        gate.open()
        _ = await task.value

        let recorder = ListingRecorder()
        let outcome = await scanner(store, tree: tree, recorder: recorder).scan(deep: false)
        let paths = await recorder.paths
        XCTAssertEqual(outcome, .completedClean)
        XCTAssertTrue(paths.contains("A"), "a failed subtree cannot disappear from resume coverage")
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets;"), 2)
    }

    func testFailedSkipStampCannotPrunePlayableInventoryOrClaimCompletion() async throws {
        let fixture = ShareCatalogSQLiteFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let tree: [String: [RemoteFileEntry]] = [
            "": [try directory("Movies")],
            "Movies": [try video("Movies/Kept (2000).mkv")]
        ]
        _ = await scanner(store, tree: tree).scan()
        try fixture.execute("""
        CREATE TRIGGER fail_skip BEFORE UPDATE ON playable_inventory BEGIN
          SELECT RAISE(FAIL, 'injected stamp failure');
        END;
        """)
        let outcome = await scanner(store, tree: tree).scan(deep: false)
        XCTAssertEqual(outcome, .completedPartial)
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets;"), 1)
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM playable_inventory;"), 1)
        let completion = await store.meta(ShareCatalogStore.completedDirectoryStateScanKey)
        XCTAssertEqual(completion, "")
    }

    func testFailedDeepPassStaysDueButHonorsNormalRetryCooldown() async throws {
        let fixture = ShareCatalogSQLiteFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        let tree = try cancellationTree()
        _ = await scanner(store, tree: tree).scan()
        await store.setMeta("last_deep_scan_at", "1")
        await store.setMeta("last_full_scan_at", "1")
        let failing = scanner(store, tree: tree, failures: ["A"])
        let outcome = await failing.scanIfStale()
        XCTAssertEqual(outcome, .completedPartial)
        let deepStamp = await store.meta("last_deep_scan_at")
        XCTAssertEqual(deepStamp, "1", "an inaccessible subtree has not been re-verified")
        let immediateRetry = await failing.scanIfStale()
        XCTAssertEqual(immediateRetry, .freshNoOp, "failed shares must not spin without a cooldown")
        await store.setMeta("last_full_scan_at", "1")
        let recorder = ListingRecorder()
        let retry = await scanner(store, tree: tree, recorder: recorder).scanIfStale()
        let paths = await recorder.paths
        XCTAssertEqual(retry, .completedClean)
        XCTAssertTrue(paths.contains("A/Kept"))
    }

    func testDeepScanCannotReuseAnIncrementalCheckpoint() async throws {
        let fixture = ShareCatalogSQLiteFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        var tree = try cancellationTree()
        _ = await scanner(store, tree: tree).scan()
        tree["B"] = [try directory("B/Pending", timestamp: 200)]
        let gate = MetadataAsyncTestGate()
        let interrupted = scanner(store, tree: tree, gate: gate)
        let task = Task { await interrupted.scan(deep: false) }
        await gate.waitUntilEntered()
        task.cancel()
        gate.open()
        _ = await task.value
        let checkpoint = await store.meta("resume_checkpoint")
        XCTAssertFalse(checkpoint?.isEmpty ?? true)

        // The skipped half changed without a directory timestamp change.
        tree["A/Kept"] = [try video("A/Kept/New (2002).mkv")]
        let recorder = ListingRecorder()
        let outcome = await scanner(store, tree: tree, recorder: recorder).scan(deep: true)
        let paths = await recorder.paths
        XCTAssertEqual(outcome, .completedClean)
        XCTAssertTrue(paths.contains("A/Kept"))
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets WHERE year=2002;"), 1)
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets WHERE year=2000;"), 0)
    }

    func testResumedScanFinalizesItemsDiscoveredBeforeInterruption() async throws {
        let fixture = ShareCatalogSQLiteFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        var tree = try cancellationTree()
        _ = await scanner(store, tree: tree).scan()
        tree["A", default: []].append(try video("A/New (2002).mkv"))
        tree["B"] = [try directory("B/Pending", timestamp: 200)]
        let gate = MetadataAsyncTestGate()
        let interrupted = scanner(store, tree: tree, gate: gate)
        let task = Task { await interrupted.scan(deep: false) }
        await gate.waitUntilEntered()
        task.cancel()
        gate.open()
        _ = await task.value
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets;"), 3)
        let outcome = await scanner(store, tree: tree).scan(deep: false)
        XCTAssertEqual(outcome, .completedClean)
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets WHERE movie_group_key IS NULL;"), 0,
                       "resume-time row counts already include new files, but they still need reconciliation")
    }

    func testRestartWithoutCheckpointReconcilesInterruptedDiscoveries() async throws {
        let fixture = ShareCatalogSQLiteFixture()
        defer { fixture.cleanup() }
        let store = fixture.makeStore()
        var tree = try cancellationTree()
        _ = await scanner(store, tree: tree).scan()
        tree["A", default: []].append(try video("A/New (2002).mkv"))
        let gate = MetadataAsyncTestGate()
        let interrupted = scanner(store, tree: tree, gate: gate)
        let task = Task { await interrupted.scan(deep: false) }
        await gate.waitUntilEntered()
        task.cancel()
        gate.open()
        _ = await task.value
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets;"), 3)
        await store.setMeta("resume_checkpoint", "")

        let outcome = await scanner(store, tree: tree).scan(deep: false)

        XCTAssertEqual(outcome, .completedClean)
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets;"), 3)
        XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets WHERE movie_group_key IS NULL;"), 0,
                       "unchanged counts do not prove an interrupted pass finished reconciliation")
    }

    func testMissingOrFutureDirectoryTimesNeverHideNewMedia() async throws {
        for timestamp in [nil, Date().addingTimeInterval(600)] as [Date?] {
            let fixture = ShareCatalogSQLiteFixture()
            defer { fixture.cleanup() }
            let store = fixture.makeStore()
            var tree: [String: [RemoteFileEntry]] = [
                "": [try RemoteFileEntry(relativePath: "Movies", kind: .directory, modifiedAt: timestamp)],
                "Movies": [try video("Movies/Old (2000).mkv")]
            ]
            _ = await scanner(store, tree: tree).scan()
            tree["Movies", default: []].append(try video("Movies/New (2001).mkv"))
            let outcome = await scanner(store, tree: tree).scan(deep: false)
            XCTAssertEqual(outcome, .completedClean)
            XCTAssertEqual(try fixture.integer("SELECT COUNT(*) FROM assets;"), 2)
        }
    }
}
