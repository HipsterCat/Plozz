import XCTest
@testable import CoreModels

final class ProfileSyncDeletionTests: XCTestCase {
    @MainActor
    func testPeerAppliesDefaultProfileDeletionWithoutPublishingItBack() throws {
        let defaults = try makeDefaults()
        let receiver = ProfilesModel(store: ProfileStore(defaults: defaults))
        let original = receiver.activeProfileID
        let survivor = receiver.add(name: "Survivor")
        var ledger = SyncLedger()
        let before = try capture(receiver)
        _ = ledger.applyFetched(saved: before.map {
            SyncRemoteRecord(recordName: $0.key, value: $0.value, editedAt: 1, systemFields: Data())
        }, deleted: [], now: 1)
        let deletedRecord = SyncRecordKey(kind: .profile, id: original).recordName
        let changes = ledger.applyFetched(saved: [], deleted: [deletedRecord], now: 2)
        XCTAssertTrue(changes.keys.contains(deletedRecord))

        receiver.applySyncedProfileDTOs([:], deletions: [original])

        XCTAssertEqual(receiver.profiles.map(\.id), [survivor.id])
        XCTAssertEqual(receiver.activeProfileID, survivor.id)
        XCTAssertNil(receiver.rootNamespaceOwnerID)
        XCTAssertEqual(receiver.activeNamespace, survivor.id)
        let plan = ledger.reconcileLocal(desired: try capture(receiver), now: 3)
        XCTAssertTrue(plan.isEmpty, "Applying a cloud deletion must not recreate that cloud record")
        let reopened = ProfilesModel(store: ProfileStore(defaults: defaults))
        XCTAssertEqual(reopened.profiles.map(\.id), [survivor.id])
        XCTAssertEqual(reopened.activeNamespace, survivor.id)
    }

    @MainActor
    func testLocalDeleteProducesCloudDeletesForProfileAndOwnedRecords() throws {
        let model = ProfilesModel(store: ProfileStore(defaults: try makeDefaults()))
        let removed = model.activeProfileID
        let survivor = model.add(name: "Survivor")
        let profileKey = SyncRecordKey(kind: .profile, id: removed).recordName
        let membershipKey = SyncRecordKey(kind: .membership, id: removed).recordName
        let settingKey = SyncRecordKey(kind: .setting, id: removed, subkey: "com.plozz.appTheme").recordName
        var before = try capture(model)
        before[membershipKey] = Data("[]".utf8)
        before[settingKey] = Data("0".utf8)
        var ledger = SyncLedger()
        _ = ledger.applyFetched(saved: before.map {
            SyncRemoteRecord(recordName: $0.key, value: $0.value, editedAt: 1, systemFields: Data())
        }, deleted: [], now: 1)

        model.remove(removed)
        let desired = SyncCaptureFallback.merge(
            live: try capture(model), fallback: before, localProfileIDs: Set(model.profiles.map(\.id))
        )
        let plan = ledger.reconcileLocal(desired: desired, now: 2)
        XCTAssertEqual(Set(plan.deletes), [profileKey, membershipKey, settingKey])
        XCTAssertTrue(plan.uploads.isEmpty)
        XCTAssertEqual(model.profiles.map(\.id), [survivor.id])
        let restored = try JSONDecoder().decode(SyncLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(Set(restored.pendingDeletes()), Set(plan.deletes))
    }

    @MainActor
    func testSurvivorsIPTVSourcesDoNotDisappearAfterDeletingOwnerAndRestarting() throws {
        let defaults = try makeDefaults()
        let model = ProfilesModel(store: ProfileStore(defaults: defaults))
        let removed = model.activeProfileID
        let survivor = model.add(name: "Survivor")
        let secure = SourceMemory()
        let configuration = LiveTVSourcesConfiguration(servers: [.init(name: "IPTV", accountID: "iptv-account")])
        try LiveTVSourcesStore(secureStore: secure, namespace: survivor.id).save(configuration)

        model.remove(removed)
        let reopened = ProfilesModel(store: ProfileStore(defaults: defaults))

        XCTAssertEqual(reopened.activeProfileID, survivor.id)
        XCTAssertEqual(
            try LiveTVSourcesStore(secureStore: secure, namespace: reopened.activeNamespace).load(), configuration
        )
    }

    @MainActor
    func testSplitCloudDeletionSurvivesRestartWithoutRepublishingThePlaceholder() throws {
        let defaults = try makeDefaults()
        let model = ProfilesModel(store: ProfileStore(defaults: defaults))
        let removed = model.activeProfile
        model.applySyncedProfileDTOs([:], deletions: [removed.id])
        XCTAssertFalse(model.profiles.isEmpty, "A partial delivery must not empty the runtime roster")
        XCTAssertEqual(model.pendingSyncedDeletionProfileIDs, [removed.id])
        XCTAssertTrue(try capture(model).isEmpty, "The temporary placeholder must not recreate a cloud record")

        let reopened = ProfilesModel(store: ProfileStore(defaults: defaults))
        XCTAssertTrue(try capture(reopened).isEmpty)
        XCTAssertNil(reopened.rootNamespaceOwnerID)
        let survivor = Profile(name: "Survivor")
        reopened.applySyncedProfileDTOs([
            removed.id: ProfileSyncDTO(profile: removed),
            survivor.id: ProfileSyncDTO(profile: survivor)
        ], deletions: [])
        XCTAssertEqual(reopened.profiles.map(\.id), [survivor.id])
        XCTAssertEqual(reopened.activeNamespace, survivor.id)
        XCTAssertEqual(try capture(reopened).count, 1)
        XCTAssertNil(reopened.profiles.first?.pendingSyncedDeletion)
        XCTAssertTrue(reopened.pendingSyncedDeletionProfileIDs.isEmpty)
    }

    @MainActor
    func testAddingProfileCompletesDeferredCloudDeletion() throws {
        let model = ProfilesModel(store: ProfileStore(defaults: try makeDefaults()))
        model.applySyncedProfileDTOs([:], deletions: [model.activeProfileID])
        let replacement = model.add(name: "Replacement")
        XCTAssertEqual(model.profiles.map(\.id), [replacement.id])
        XCTAssertEqual(model.activeProfileID, replacement.id)
        XCTAssertEqual(model.profilesForSync.map(\.id), [replacement.id])
    }

    @MainActor
    func testDeletingPINAnchorPreservesHouseholdProtectionLocallyAndThroughSync() throws {
        for synced in [false, true] {
            let defaults = try makeDefaults()
            let model = ProfilesModel(store: ProfileStore(defaults: defaults))
            let removed = model.activeProfileID
            let survivor = model.add(name: "Kids", isKidsProfile: true)
            XCTAssertTrue(model.setParentalPIN(try XCTUnwrap(ParentalPIN.make(pin: "1234", iterations: 1))))
            let revision = model.activeProfile.effectiveParentalPINRevision
            if synced { model.applySyncedProfileDTOs([:], deletions: [removed]) }
            else { model.remove(removed) }
            let reopened = ProfilesModel(store: ProfileStore(defaults: defaults))
            XCTAssertEqual(reopened.activeProfileID, survivor.id)
            XCTAssertEqual(reopened.activeProfile.effectiveParentalPINRevision, revision)
            XCTAssertTrue(reopened.matchesParentalPIN("1234"))
            XCTAssertTrue(reopened.managementRequiresParentalPIN)
        }
    }

    @MainActor
    private func capture(_ model: ProfilesModel) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: model.profilesForSync.map { profile in
            (SyncRecordKey(kind: .profile, id: profile.id).recordName,
             try XCTUnwrap(CanonicalJSON.encode(ProfileSyncDTO(profile: profile))))
        })
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "ProfileSyncDeletionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}

private final class SourceMemory: SecureStoring, @unchecked Sendable {
    private var values: [String: String] = [:]
    func setString(_ value: String, for key: String) throws { values[key] = value }
    func readString(for key: String) throws -> String? { values[key] }
    func string(for key: String) -> String? { values[key] }
    func removeValue(for key: String) throws { values[key] = nil }
}
