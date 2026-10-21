import AppRuntime
import CoreModels
import CoreSecureStore
import Foundation
import XCTest
@testable import AppShelliOS

@MainActor
final class IPTVCloudOverwriteHostedTests: XCTestCase {
    func testReaddedServerSurvivesDelayedCloudRemovalBeforeCapture() async throws {
        let fixture = try makeFixture()
        try fixture.sources.save(.init(servers: [fixture.server]))
        let initial = await fixture.bridge.capture(fallback: [:])
        try fixture.sources.save(.empty)
        try fixture.suppression.setSuppressed(true, accountID: fixture.server.accountID)
        let removed = await fixture.bridge.capture(fallback: initial)
        XCTAssertNotEqual(initial[fixture.sourceKey], removed[fixture.sourceKey])
        var ledger = SyncLedger()
        _ = ledger.reconcileLocal(desired: removed, now: 1)

        try fixture.sources.save(.init(servers: [fixture.server]))
        try fixture.suppression.setSuppressed(false, accountID: fixture.server.accountID)
        await fixture.bridge.apply(
            removed.mapValues(Optional.some), localCaptureDigests: ledger.entries.compactMapValues(\.localCaptureDigest)
        )

        XCTAssertEqual(try fixture.sources.load().servers, [fixture.server])
        XCTAssertTrue(try fixture.suppression.suppressedAccountIDs().isEmpty)
        let next = await fixture.bridge.capture(fallback: removed)
        XCTAssertEqual(next[fixture.sourceKey], initial[fixture.sourceKey])
    }

    func testCapturedReenableSurvivesDelayedCloudStateAndBridgeRestart() async throws {
        let fixture = try makeFixture()
        var disabled = fixture.server
        disabled.isEnabled = false
        try fixture.sources.save(.init(servers: [disabled]))
        let old = await fixture.bridge.capture(fallback: [:])
        var ledger = SyncLedger()
        _ = ledger.reconcileLocal(desired: old, now: 1)
        let oldReceipts = ledger.entries.compactMapValues(\.localCaptureDigest)
        try fixture.sources.save(.init(servers: [fixture.server]))
        try fixture.suppression.setSuppressed(false, accountID: fixture.server.accountID)
        let local = await fixture.bridge.capture(fallback: old)
        XCTAssertNotEqual(local[fixture.sourceKey], old[fixture.sourceKey])
        let restarted = fixture.makeBridge()

        await restarted.apply(old.mapValues(Optional.some), localCaptureDigests: oldReceipts)
        XCTAssertEqual(try fixture.sources.load().servers, [fixture.server])
        let capturedAgain = await restarted.capture(fallback: old)
        XCTAssertEqual(capturedAgain[fixture.sourceKey], local[fixture.sourceKey])
        XCTAssertTrue(try fixture.suppression.suppressedAccountIDs().isEmpty)

        _ = ledger.reconcileLocal(desired: local, now: 2)
        let remoteEdit = try XCTUnwrap(ledger.entries[fixture.sourceKey]).editedAt + 1
        let changes = ledger.applyFetched(saved: [
            .init(recordName: fixture.sourceKey, value: try XCTUnwrap(old[fixture.sourceKey]),
                  editedAt: remoteEdit, systemFields: Data([1]))
        ], deleted: [], now: remoteEdit)
        XCTAssertFalse(changes.isEmpty)
        await restarted.apply(changes, localCaptureDigests: ledger.entries.compactMapValues(\.localCaptureDigest))
        XCTAssertEqual(try fixture.sources.load().servers, [disabled])
    }

    func testAcknowledgedCloudDeletionStillRemovesServer() async throws {
        let fixture = try makeFixture()
        try fixture.sources.save(.init(servers: [fixture.server]))
        let local = await fixture.bridge.capture(fallback: [:])
        var ledger = SyncLedger()
        _ = ledger.reconcileLocal(desired: local, now: 1)
        _ = ledger.applyFetched(saved: local.map {
            .init(recordName: $0.key, value: $0.value, editedAt: 1, systemFields: Data([1]))
        }, deleted: [], now: 1)
        let receipts = ledger.entries.compactMapValues(\.localCaptureDigest)
        let changes = ledger.applyFetched(saved: [], deleted: [fixture.sourceKey], now: 2)
        XCTAssertTrue(changes.keys.contains(fixture.sourceKey))
        XCTAssertNil(ledger.entries[fixture.sourceKey])
        let snapshot = SyncChannelSnapshot(
            sequence: 1, authority: "isolated-test", records: ledger.entries.mapValues(\.localValue),
            deleted: [fixture.sourceKey], localCaptureDigests: receipts, changes: changes
        )

        let channel = PlozziOSAppModel.makeLiveTVSyncChannel(
            bridge: fixture.bridge, stateFileURL: fixture.directory.appendingPathComponent("ledger.json")
        )
        let apply = try XCTUnwrap(channel.applySnapshot)
        await apply(snapshot)

        XCTAssertTrue(try fixture.sources.load().servers.isEmpty)
        XCTAssertEqual(try fixture.suppression.suppressedAccountIDs(), [fixture.server.accountID])
    }

    func testSplitCloudDisableAndReenableConvergeThroughApprovalStore() async throws {
        let fixture = try makeFixture()
        try fixture.sources.save(.init(servers: [fixture.server]))
        let initial = await fixture.bridge.capture(fallback: [:])
        var ledger = SyncLedger()
        _ = ledger.reconcileLocal(desired: initial, now: 1)
        let receipts = ledger.entries.compactMapValues(\.localCaptureDigest)
        let enrollmentKey = LiveTVPortableRecordKey(
            profileID: fixture.profiles.activeProfileID, kind: .serverEnrollment, entityID: fixture.server.accountID
        ).recordName
        await fixture.bridge.apply([
            fixture.sourceKey: try LiveTVPortableRecord(source: .init(
                kind: .server, name: fixture.server.name, isEnabled: false, accountID: fixture.server.accountID
            )).encoded()
        ], localCaptureDigests: receipts)
        XCTAssertEqual(try fixture.sources.load().servers.first?.isEnabled, false)
        let restarted = fixture.makeBridge()
        await restarted.apply([
            enrollmentKey: try LiveTVPortableRecord(serverEnrollmentSuppressed: true).encoded()
        ], localCaptureDigests: receipts)
        await restarted.apply([
            fixture.sourceKey: try XCTUnwrap(initial[fixture.sourceKey])
        ], localCaptureDigests: receipts)
        await restarted.apply([
            enrollmentKey: try XCTUnwrap(initial[enrollmentKey])
        ], localCaptureDigests: receipts)

        XCTAssertEqual(try fixture.sources.load().servers, [fixture.server])
        XCTAssertTrue(try fixture.suppression.suppressedAccountIDs().isEmpty)
    }

    func testRemovingDisabledServerKeepsEnrollmentSuppressedUntilCaptureAcknowledgment() async throws {
        let fixture = try makeFixture()
        try fixture.sources.save(.init(servers: [fixture.server]))
        let initial = await fixture.bridge.capture(fallback: [:])
        var ledger = SyncLedger()
        _ = ledger.reconcileLocal(desired: initial, now: 1)
        let receipts = ledger.entries.compactMapValues(\.localCaptureDigest)
        let enrollmentKey = LiveTVPortableRecordKey(
            profileID: fixture.profiles.activeProfileID, kind: .serverEnrollment, entityID: fixture.server.accountID
        ).recordName
        let disabled: [String: Data] = [
            fixture.sourceKey: try LiveTVPortableRecord(source: .init(
                kind: .server, name: fixture.server.name, isEnabled: false, accountID: fixture.server.accountID
            )).encoded(),
            enrollmentKey: try LiveTVPortableRecord(serverEnrollmentSuppressed: true).encoded()
        ]
        await fixture.bridge.apply(disabled.mapValues(Optional.some), localCaptureDigests: receipts)
        try fixture.sources.save(.empty)
        let removal = await fixture.bridge.capture(fallback: disabled)
        let restarted = fixture.makeBridge()
        let reenable: SyncLocalChanges = [enrollmentKey: try XCTUnwrap(initial[enrollmentKey])]
        await restarted.apply(reenable, localCaptureDigests: receipts)
        XCTAssertTrue(try fixture.sources.load().servers.isEmpty)
        XCTAssertEqual(try fixture.suppression.suppressedAccountIDs(), [fixture.server.accountID])

        _ = ledger.reconcileLocal(desired: removal, now: 2)
        await restarted.apply(reenable, localCaptureDigests: ledger.entries.compactMapValues(\.localCaptureDigest))
        XCTAssertTrue(try fixture.suppression.suppressedAccountIDs().isEmpty)
    }

    func testSourceSaveSurvivesJournalFailureAndBridgeRestart() async throws {
        let fixture = try makeFixture()
        try fixture.sources.save(.init(servers: [fixture.server]))
        let initial = await fixture.bridge.capture(fallback: [:])
        var ledger = SyncLedger()
        _ = ledger.reconcileLocal(desired: initial, now: 1)
        let receipts = ledger.entries.compactMapValues(\.localCaptureDigest)
        let sourceKey = fixture.sourceKey
        let adapter = LiveTVPortableSyncAdapter(
            directory: fixture.directory, profileID: fixture.profiles.activeProfileID,
            defaults: fixture.defaults, namespace: fixture.profiles.activeNamespace,
            requiresPreparedJournal: true, includesPlaylistSources: false,
            writeFile: { data, url in
                if url.pathExtension == "record",
                   let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   record["name"] as? String == sourceKey {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try data.write(to: url, options: .atomic)
            }
        )
        let disable: SyncLocalChanges = [
            sourceKey: try LiveTVPortableRecord(source: .init(
                kind: .server, name: fixture.server.name, isEnabled: false,
                accountID: fixture.server.accountID
            )).encoded()
        ]
        try await adapter.prepareForOperation(records: disable)
        do {
            _ = try await adapter.committingJournal {
                try adapter.apply(disable, sourceStore: fixture.sources, localCaptureDigests: receipts)
            }
            XCTFail("The source journal write must fail")
        } catch {
            XCTAssertEqual((error as NSError).code, CocoaError.fileWriteNoPermission.rawValue)
        }
        XCTAssertEqual(try fixture.sources.loadSyncConfiguration().servers.first?.isEnabled, false)
        XCTAssertNotNil(try fixture.sources.loadSyncConfiguration().serverSyncCheckpoint)
        let restarted = fixture.makeBridge()
        _ = await restarted.capture(fallback: initial)
        await restarted.apply(initial.mapValues(Optional.some), localCaptureDigests: receipts)
        XCTAssertEqual(try fixture.sources.load().servers, [fixture.server])
        XCTAssertTrue(try fixture.suppression.suppressedAccountIDs().isEmpty)
    }

    private func makeFixture() throws -> IPTVCloudOverwriteFixture {
        let suite = "IPTVCloudOverwriteHostedTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let keychain = KeychainStore(service: suite, userIndependent: false)
        addTeardownBlock {
            try keychain.removeValue(for: LiveTVSourcesStore.baseKey)
            defaults.removePersistentDomain(forName: suite)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        return IPTVCloudOverwriteFixture(defaults: defaults, directory: directory, keychain: keychain)
    }
}

@MainActor
private final class IPTVCloudOverwriteFixture {
    let defaults: UserDefaults
    let directory: URL
    let profiles: ProfilesModel
    let sources: LiveTVApprovalAwareSourcesStore
    let server = LiveTVServerSource(id: "test-server", name: "Test IPTV", accountID: "test-iptv-account")
    lazy var bridge = makeBridge()
    var sourceKey: String {
        LiveTVPortableRecordKey(profileID: profiles.activeProfileID, kind: .source, entityID: server.id).recordName
    }
    var suppression: LiveTVServerEnrollmentSuppressionStore {
        .init(defaults: defaults, profileID: profiles.activeProfileID, namespace: profiles.activeNamespace)
    }

    init(defaults: UserDefaults, directory: URL, keychain: KeychainStore) {
        self.defaults = defaults
        self.directory = directory
        profiles = ProfilesModel(store: ProfileStore(defaults: defaults))
        sources = LiveTVApprovalAwareSourcesStore(
            underlying: LiveTVSourcesStore(secureStore: keychain),
            approvals: .init(
                defaults: defaults, profileID: profiles.activeProfileID, namespace: profiles.activeNamespace
            )
        )
        SyncSetupFeatureFlag(defaults: defaults).isEnabled = true
    }

    func makeBridge() -> LiveTVPortableSyncBridge {
        let bridge = LiveTVPortableSyncBridge(
            profiles: profiles, directory: directory, defaults: defaults, followsMainSync: true,
            sourceStore: { [sources] _ in sources }
        )
        bridge.refreshParticipation()
        return bridge
    }
}
