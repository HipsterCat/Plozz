import Foundation

/// Explicit per-profile discovery decisions. A removed source must not return
/// merely because its still-signed-in server reports Live TV again.
public final class LiveTVServerEnrollmentSuppressionStore: @unchecked Sendable {
    private struct Document: Codable {
        var version = 1
        var records: [String: Bool] = [:]
        var syncedAccountIDs: Set<String>?
    }

    private let defaults: UserDefaults
    private let key: String
    private let profileID: String
    private let namespace: String?
    private static let lock = NSLock()

    public convenience init(defaults: UserDefaults = .standard, profileID: String) {
        self.init(
            defaults: defaults, profileID: profileID,
            namespace: profileID == ProfileStore.defaultProfileID ? nil : profileID
        )
    }

    public init(defaults: UserDefaults = .standard, profileID: String, namespace: String?) {
        self.defaults = defaults
        self.profileID = profileID
        self.namespace = namespace
        key = SettingsKey.scoped(
            "com.plozz.liveTV.serverEnrollment.v1",
            namespace: namespace
        )
    }

    public func records() throws -> [String: Bool] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try read().records
    }

    public func suppressedAccountIDs() throws -> Set<String> {
        Set(try records().filter(\.value).keys)
    }

    public func wasAppliedFromSync(accountID: String) throws -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try read().syncedAccountIDs?.contains(accountID) == true
    }

    public func setSuppressed(_ value: Bool, accountID: String, fromSync: Bool = false) throws {
        try setSuppressed(value, accountID: accountID, fromSync: fromSync, preservingExistingDecision: false)
    }

    private func setSuppressed(
        _ value: Bool, accountID: String, fromSync: Bool, preservingExistingDecision: Bool
    ) throws {
        guard !accountID.isEmpty, accountID.utf8.count <= 512,
              !accountID.contains("://"), !accountID.contains("?") else {
            throw LiveTVPortableStateError.invalidRecord
        }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var document = try read()
        guard document.records[accountID] != nil || document.records.count < 1_000 else {
            throw LiveTVPortableStateError.tooLarge
        }
        guard !preservingExistingDecision || document.records[accountID] != value else { return }
        document.records[accountID] = value
        var synced = document.syncedAccountIDs ?? []
        if fromSync { synced.insert(accountID) }
        else { synced.remove(accountID) }
        document.syncedAccountIDs = synced.isEmpty ? nil : synced
        let data = try JSONEncoder().encode(document)
        guard data.count <= 1_024 * 1_024 else { throw LiveTVPortableStateError.tooLarge }
        defaults.set(data, forKey: key)
        LiveTVSourceDiagnostics.shared.record(
            .suppressionChanged,
            identities: [.profile: profileID, .namespace: namespace ?? "default", .account: accountID],
            flags: [.suppressed: value], deduplicate: true
        )
    }

    /// Restrictions precede the write. A failed source save may keep a server
    /// suppressed, but cannot unexpectedly enroll it.
    public func prepareChange(
        previous: LiveTVSourcesConfiguration, updated: LiveTVSourcesConfiguration, fromSync: Bool = false
    ) throws {
        let retained = Set(updated.servers.map(\.accountID))
        let removed = Set(previous.servers.map(\.accountID)).subtracting(retained)
        let disabled = Set(updated.servers.filter { !$0.isEnabled }.map(\.accountID))
        for accountID in removed.union(disabled) {
            try setSuppressed(
                true, accountID: accountID, fromSync: fromSync, preservingExistingDecision: fromSync
            )
        }
    }

    /// Only a successful explicit addition/re-enable relaxes an earlier removal.
    public func completeChange(
        previous: LiveTVSourcesConfiguration, updated: LiveTVSourcesConfiguration
    ) throws {
        for source in updated.servers where source.isEnabled {
            let old = previous.servers.first { $0.accountID == source.accountID }
            if old == nil || old?.isEnabled == false {
                try setSuppressed(false, accountID: source.accountID)
            }
        }
    }

    private func read() throws -> Document {
        guard let object = defaults.object(forKey: key) else { return Document() }
        guard let bytes = object as? Data, bytes.count <= 1_024 * 1_024 else {
            throw LiveTVPortableStateError.invalidRecord
        }
        let document = try JSONDecoder().decode(Document.self, from: bytes)
        guard document.version == 1 else { throw LiveTVPortableStateError.unsupportedVersion }
        guard document.records.count <= 1_000,
              document.records.keys.allSatisfy({
                  !$0.isEmpty && $0.utf8.count <= 512 && !$0.contains("://") && !$0.contains("?")
              }) else { throw LiveTVPortableStateError.tooLarge }
        guard (document.syncedAccountIDs ?? []).isSubset(of: Set(document.records.keys)) else {
              throw LiveTVPortableStateError.invalidRecord
        }
        return document
    }
}
