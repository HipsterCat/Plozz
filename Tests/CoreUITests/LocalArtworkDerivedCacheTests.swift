#if canImport(UIKit)
import CoreModels
@testable import CoreUI
import SQLite3
import UIKit
import XCTest

final class LocalArtworkDerivedCacheTests: XCTestCase {
    func testInactiveEntriesEvictBeforePreferredAccounts() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let clock = TestClock()
        let cache = LocalArtworkDerivedCache(
            directory: fixture.directory,
            byteCap: 1_000_000,
            warningByteCap: 750_000,
            maximumAge: 30 * 24 * 60 * 60,
            now: { clock.now }
        )
        let image = try Self.image(color: .red)
        await cache.store(
            image,
            key: "active",
            accountID: "active",
            credentialRevision: "revision",
            sourceFingerprint: "active-fingerprint",
            variant: .posterCard
        )
        clock.advance()
        await cache.store(
            image,
            key: "inactive",
            accountID: "inactive",
            credentialRevision: "revision",
            sourceFingerprint: "inactive-fingerprint",
            variant: .posterCard
        )
        let oneEntryCap = max(1, await cache.usageBytes() / 2 + 1)
        await cache.setPreferredAccounts(["active"], revision: 1)
        await cache.trim(to: oneEntryCap)

        let active = await cache.data(
            for: "active",
            accountID: "active",
            credentialRevision: "revision",
            sourceFingerprint: "active-fingerprint"
        )
        let inactive = await cache.data(
            for: "inactive",
            accountID: "inactive",
            credentialRevision: "revision",
            sourceFingerprint: "inactive-fingerprint"
        )
        XCTAssertNotNil(active)
        XCTAssertNil(inactive)
    }

    func testBackgroundReadDoesNotRefreshAgeAndExpiredEntryIsRemovedFirst() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let clock = TestClock()
        let cache = LocalArtworkDerivedCache(
            directory: fixture.directory,
            byteCap: 1_000_000,
            warningByteCap: 750_000,
            maximumAge: 10,
            now: { clock.now }
        )
        await cache.store(
            try Self.image(color: .blue),
            key: "expired",
            accountID: "active",
            credentialRevision: "revision",
            sourceFingerprint: "fingerprint",
            variant: .landscapeCard
        )
        clock.advance(by: 11)
        let backgroundHit = await cache.data(
            for: "expired",
            accountID: "active",
            credentialRevision: "revision",
            sourceFingerprint: "fingerprint",
            markUsed: false
        )
        XCTAssertNotNil(backgroundHit)

        await cache.trim(to: 1_000_000)

        let expired = await cache.data(
            for: "expired",
            accountID: "active",
            credentialRevision: "revision",
            sourceFingerprint: "fingerprint"
        )
        XCTAssertNil(expired)
    }

    func testStalePreferenceRevisionCannotReplaceNewerPolicy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let cache = LocalArtworkDerivedCache(directory: fixture.directory)
        await cache.setPreferredAccounts(["new"], revision: 2)
        await cache.setPreferredAccounts(["stale"], revision: 1)
        let preferred = await cache.preferredAccountsForTesting()
        XCTAssertEqual(preferred, ["new"])
    }

    func testSuspensionClosesManifestAndRejectsWorkUntilNewerResume() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let cache = LocalArtworkDerivedCache(directory: fixture.directory)
        let image = try Self.image(color: .orange)
        await cache.store(
            image,
            key: "before",
            accountID: "account",
            credentialRevision: "revision",
            sourceFingerprint: "before",
            variant: .posterCard
        )
        let storedBytes = await cache.usageBytes()
        XCTAssertGreaterThan(storedBytes, 0)

        await cache.setBackgroundWorkAllowed(false, revision: 2)
        let suspended = await cache.backgroundWorkAllowedForTesting()
        let suspendedUsage = await cache.usageBytes()
        XCTAssertFalse(suspended)
        XCTAssertEqual(suspendedUsage, 0)
        let manifestIsOpen = await cache.manifestIsOpenForTesting()
        XCTAssertFalse(manifestIsOpen)
        var observer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.directory.appendingPathComponent("manifest.sqlite").path, &observer), SQLITE_OK)
        defer { sqlite3_close(observer) }
        XCTAssertEqual(sqlite3_exec(observer, "BEGIN EXCLUSIVE; COMMIT;", nil, nil, nil), SQLITE_OK)
        await cache.store(
            image,
            key: "blocked",
            accountID: "account",
            credentialRevision: "revision",
            sourceFingerprint: "blocked",
            variant: .posterCard
        )

        await cache.setBackgroundWorkAllowed(true, revision: 1)
        await cache.setBackgroundWorkAllowed(true, revision: 2)
        let staleResumeAllowed = await cache.backgroundWorkAllowedForTesting()
        XCTAssertFalse(staleResumeAllowed)
        await cache.setBackgroundWorkAllowed(true, revision: 3)
        let resumed = await cache.backgroundWorkAllowedForTesting()
        let resumedUsage = await cache.usageBytes()
        XCTAssertTrue(resumed)
        XCTAssertEqual(resumedUsage, storedBytes)
        let blocked = await cache.data(
            for: "blocked",
            accountID: "account",
            credentialRevision: "revision",
            sourceFingerprint: "blocked"
        )
        XCTAssertNil(blocked)
    }

    func testSuspendedPurgesRunBeforeFirstResumedRead() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let cache = LocalArtworkDerivedCache(directory: fixture.directory)
        let image = try Self.image(color: .red)
        for (key, account, revision) in [
            ("a1", "a", "one"), ("a2", "a", "two"),
            ("b1", "b", "one"), ("c1", "c", "one"),
        ] {
            await cache.store(image, key: key, accountID: account, credentialRevision: revision,
                              sourceFingerprint: key, variant: .posterCard)
        }
        await cache.setBackgroundWorkAllowed(false, revision: 1)
        await cache.purge(accountID: "a", credentialRevision: "one")
        await cache.purge(accountID: "b")
        let openWhileSuspended = await cache.manifestIsOpenForTesting()
        XCTAssertFalse(openWhileSuspended)
        await cache.setBackgroundWorkAllowed(true, revision: 2)
        let purgedRevision = await cache.data(for: "a1", accountID: "a", credentialRevision: "one", sourceFingerprint: "a1")
        let retainedRevision = await cache.data(for: "a2", accountID: "a", credentialRevision: "two", sourceFingerprint: "a2")
        let purgedAccount = await cache.data(for: "b1", accountID: "b", credentialRevision: "one", sourceFingerprint: "b1")
        let retainedAccount = await cache.data(for: "c1", accountID: "c", credentialRevision: "one", sourceFingerprint: "c1")
        XCTAssertNil(purgedRevision)
        XCTAssertNotNil(retainedRevision)
        XCTAssertNil(purgedAccount)
        XCTAssertNotNil(retainedAccount)
    }

    func testSuspendedClearAndBudgetReductionAreNotLost() async throws {
        for clear in [true, false] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let cache = LocalArtworkDerivedCache(directory: fixture.directory)
            await cache.store(try Self.image(color: .blue), key: "old", accountID: "a",
                              credentialRevision: "one", sourceFingerprint: "old", variant: .posterCard)
            await cache.setBackgroundWorkAllowed(false, revision: 1)
            if clear { await cache.clear() } else { await cache.setByteCap(0) }
            let openWhileSuspended = await cache.manifestIsOpenForTesting()
            XCTAssertFalse(openWhileSuspended)
            await cache.setBackgroundWorkAllowed(true, revision: 2)
            let usage = await cache.usageBytes()
            XCTAssertEqual(usage, 0)
            let old = await cache.data(for: "old", accountID: "a", credentialRevision: "one", sourceFingerprint: "old")
            XCTAssertNil(old)
        }
    }

    func testBusyManifestReopenDoesNotDestroyExistingArtwork() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let cache = LocalArtworkDerivedCache(directory: fixture.directory)
        await cache.store(try Self.image(color: .green), key: "old", accountID: "a",
                          credentialRevision: "one", sourceFingerprint: "old", variant: .posterCard)
        await cache.setBackgroundWorkAllowed(false, revision: 1)
        var observer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.directory.appendingPathComponent("manifest.sqlite").path, &observer), SQLITE_OK)
        defer { sqlite3_close(observer) }
        XCTAssertEqual(sqlite3_exec(observer, "BEGIN EXCLUSIVE;", nil, nil, nil), SQLITE_OK)
        await cache.setBackgroundWorkAllowed(true, revision: 2)
        let busy = await cache.data(for: "old", accountID: "a", credentialRevision: "one", sourceFingerprint: "old")
        XCTAssertNil(busy)
        XCTAssertEqual(sqlite3_exec(observer, "COMMIT;", nil, nil, nil), SQLITE_OK)
        let retained = await cache.data(for: "old", accountID: "a", credentialRevision: "one", sourceFingerprint: "old")
        XCTAssertNotNil(retained)
    }

    func testFailedDeferredPurgeIsRetriedBeforeArtworkCanBeRead() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let cache = LocalArtworkDerivedCache(directory: fixture.directory)
        await cache.store(try Self.image(color: .green), key: "old", accountID: "a",
                          credentialRevision: "one", sourceFingerprint: "old", variant: .posterCard)
        await cache.setBackgroundWorkAllowed(false, revision: 1)
        await cache.purge(accountID: "a")
        var observer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.directory.appendingPathComponent("manifest.sqlite").path, &observer), SQLITE_OK)
        defer { sqlite3_close(observer) }
        XCTAssertEqual(sqlite3_exec(observer, "BEGIN IMMEDIATE;", nil, nil, nil), SQLITE_OK)
        await cache.setBackgroundWorkAllowed(true, revision: 2)
        let blocked = await cache.data(for: "old", accountID: "a", credentialRevision: "one", sourceFingerprint: "old")
        XCTAssertNil(blocked)
        XCTAssertEqual(sqlite3_exec(observer, "COMMIT;", nil, nil, nil), SQLITE_OK)
        let purged = await cache.data(for: "old", accountID: "a", credentialRevision: "one", sourceFingerprint: "old")
        XCTAssertNil(purged)
        let usage = await cache.usageBytes()
        XCTAssertEqual(usage, 0)
    }

    func testAccountAndCredentialRevisionPurgesAreScoped() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let cache = LocalArtworkDerivedCache(directory: fixture.directory)
        let image = try Self.image(color: .green)
        for (key, account, revision) in [
            ("a1", "a", "one"),
            ("a2", "a", "two"),
            ("b1", "b", "one"),
        ] {
            await cache.store(
                image,
                key: key,
                accountID: account,
                credentialRevision: revision,
                sourceFingerprint: key,
                variant: .posterCard
            )
        }

        await cache.purge(accountID: "a", credentialRevision: "one")
        let purgedRevision = await cache.data(
            for: "a1", accountID: "a", credentialRevision: "one", sourceFingerprint: "a1"
        )
        let retainedRevision = await cache.data(
            for: "a2", accountID: "a", credentialRevision: "two", sourceFingerprint: "a2"
        )
        let otherAccount = await cache.data(
            for: "b1", accountID: "b", credentialRevision: "one", sourceFingerprint: "b1"
        )
        XCTAssertNil(purgedRevision)
        XCTAssertNotNil(retainedRevision)
        XCTAssertNotNil(otherAccount)

        await cache.purge(accountID: "a")
        let purgedAccount = await cache.data(
            for: "a2", accountID: "a", credentialRevision: "two", sourceFingerprint: "a2"
        )
        let retainedAccount = await cache.data(
            for: "b1", accountID: "b", credentialRevision: "one", sourceFingerprint: "b1"
        )
        XCTAssertNil(purgedAccount)
        XCTAssertNotNil(retainedAccount)
    }

    func testCorruptManifestIsRecreatedAsCacheMiss() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try Data("not sqlite".utf8).write(
            to: fixture.directory.appendingPathComponent("manifest.sqlite")
        )
        let cache = LocalArtworkDerivedCache(directory: fixture.directory)

        let emptyUsage = await cache.usageBytes()
        XCTAssertEqual(emptyUsage, 0)
        await cache.store(
            try Self.image(color: .purple),
            key: "recovered",
            accountID: "account",
            credentialRevision: "revision",
            sourceFingerprint: "fingerprint",
            variant: .posterCard
        )
        let recoveredUsage = await cache.usageBytes()
        XCTAssertGreaterThan(recoveredUsage, 0)
    }

    private static func image(color: UIColor) throws -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_000)

    var now: Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval = 1) {
        lock.withLock { value = value.addingTimeInterval(interval) }
    }
}

private struct Fixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalArtworkDerivedCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
#endif
