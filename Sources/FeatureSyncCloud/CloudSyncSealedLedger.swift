import CoreModels
import CoreNetworking
import CryptoKit
import Darwin
import Foundation

/// Entry files avoid repeatedly serializing large imported playlists on each
/// CloudKit acknowledgement. The index is the atomic commit point. Credential
/// channels remain sealed; non-secret Live TV state uses a versioned plain index.
enum CloudSyncSealedLedger {
    private struct Reference: Codable {
        let file: UUID
        let digest: Data
        let bytes: Int
    }
    private struct Index: Codable {
        let format: Int
        let checkpoint: SyncLedger.Checkpoint
        let records: [String: Reference]
        let authority: String?
    }
    private struct LegacyWrapper: Decodable {
        let ledger: SyncLedger
    }
    private struct StoredEntry: Codable {
        var entry: SyncLedgerEntry
        let syncedValueMatchesLocal: Bool

        init(_ entry: SyncLedgerEntry) {
            self.entry = entry
            syncedValueMatchesLocal = entry.syncedValue == entry.localValue
            if syncedValueMatchesLocal { self.entry.syncedValue = nil }
        }

        var restored: SyncLedgerEntry {
            var result = entry
            if syncedValueMatchesLocal { result.syncedValue = result.localValue }
            return result
        }
    }
    private static let indexPrefix = Data("Plozz.CloudSync.RecordIndex.v2\n".utf8)
    private static let maximumEntryBytes = 4 * 1_024 * 1_024
    private static let maximumTotalBytes = 768 * 1_024 * 1_024

    static func load(from url: URL, codec: CloudSyncStateCodec? = nil, authority: String? = nil) throws -> SyncLedger? {
        try withFileLock(at: url) { try loadLocked(from: url, codec: codec, authority: authority) }
    }

    private static func loadLocked(from url: URL, codec: CloudSyncStateCodec?, authority: String?) throws -> SyncLedger? {
        // Legacy whole-ledger JSON may exceed the per-envelope bound. Migration
        // retains it until every entry and the new index have committed.
        guard let data = try readIfPresent(url, maximumBytes: maximumTotalBytes) else {
            if FileManager.default.fileExists(atPath: directory(url).path) {
                reclaimUnreferencedFiles(at: url, retained: [], codec: codec)
            }
            return nil
        }
        let plaintext = try decodeIndex(data, codec: codec)
        if (CloudSyncStateCodec.isSealed(data) || data.starts(with: indexPrefix)),
           let index = try? JSONDecoder().decode(Index.self, from: plaintext) {
            guard (CloudSyncStateCodec.isSealed(data) || data.starts(with: indexPrefix)),
                  (1...2).contains(index.format), index.records.count <= 50_000,
                  index.records.values.allSatisfy({ (1...maximumEntryBytes).contains($0.bytes) }),
                  index.records.values.reduce(0, { $0 + $1.bytes }) <= maximumTotalBytes else {
                throw CloudSyncStateCodec.Failure.tooLarge
            }
            guard index.authority == authority else { return nil }
            var entries: [String: SyncLedgerEntry] = [:]
            for (name, reference) in index.records {
                let file = entryURL(reference.file, indexURL: url, codec: codec)
                guard let sealed = try readIfPresent(file, maximumBytes: maximumEntryBytes + 1_024) else {
                    throw CloudSyncStateCodec.Failure.invalidEnvelope
                }
                let entryData = try codec?.decode(sealed) ?? sealed
                guard entryData.count == reference.bytes, Data(SHA256.hash(data: entryData)) == reference.digest else {
                    throw CloudSyncStateCodec.Failure.invalidEnvelope
                }
                var entry = try index.format == 1
                    ? JSONDecoder().decode(SyncLedgerEntry.self, from: entryData)
                    : JSONDecoder().decode(StoredEntry.self, from: entryData).restored
                if entry.syncedValue == entry.localValue { entry.syncedValue = entry.localValue }
                entries[name] = entry
            }
            reclaimUnreferencedFiles(at: url, retained: Set(index.records.values.map(\.file)), codec: codec)
            reclaimLegacyWritesAfterLoad(at: url, codec: codec)
            return SyncLedger(checkpoint: index.checkpoint, entries: entries)
        }
        guard !data.starts(with: indexPrefix) else { throw CloudSyncStateCodec.Failure.invalidEnvelope }
        guard authority == nil else { return nil }
        var ledger: SyncLedger
        if let bare = try? JSONDecoder().decode(SyncLedger.self, from: plaintext) {
            ledger = bare
        } else {
            ledger = try JSONDecoder().decode(LegacyWrapper.self, from: plaintext).ledger
        }
        ledger = SyncLedger(checkpoint: ledger.checkpoint, entries: ledger.entries.mapValues { original in
            var entry = original
            if entry.syncedValue == entry.localValue { entry.syncedValue = entry.localValue }
            return entry
        })
        try saveLocked(ledger, to: url, codec: codec, authority: authority)
        reclaimLegacyWritesAfterLoad(at: url, codec: codec)
        return ledger
    }

    static func save(_ ledger: SyncLedger, to url: URL, codec: CloudSyncStateCodec? = nil, authority: String? = nil) throws {
        try withFileLock(at: url) { try saveLocked(ledger, to: url, codec: codec, authority: authority) }
    }

    private static func saveLocked(_ ledger: SyncLedger, to url: URL, codec: CloudSyncStateCodec?, authority: String?) throws {
        var previous: Index?
        if let data = try readIfPresent(url, maximumBytes: maximumTotalBytes),
           CloudSyncStateCodec.isSealed(data) || data.starts(with: indexPrefix) {
            let plaintext = try decodeIndex(data, codec: codec)
            previous = try? JSONDecoder().decode(Index.self, from: plaintext)
        }
        var folder = directory(url)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try folder.setResourceValues(attributes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var records: [String: Reference] = [:]
        var total = 0
        var created: [URL] = []
        var committed = false
        defer {
            if !committed {
                for file in created {
                    do { try FileManager.default.removeItem(at: file) }
                    catch CocoaError.fileNoSuchFile {}
                    catch { PlozzLog.sync.error("Sync staging cleanup failed code=\((error as NSError).code)") }
                }
            }
        }
        for (name, entry) in ledger.entries {
            let data = try encoder.encode(StoredEntry(entry))
            total += data.count
            guard data.count <= maximumEntryBytes, total <= maximumTotalBytes,
                  ledger.entries.count <= 50_000 else { throw CloudSyncStateCodec.Failure.tooLarge }
            let digest = Data(SHA256.hash(data: data))
            if previous?.format == 2, let reference = previous?.records[name], reference.digest == digest {
                records[name] = reference
            } else {
                let reference = Reference(file: UUID(), digest: digest, bytes: data.count)
                let file = entryURL(reference.file, indexURL: url, codec: codec)
                created.append(file)
                try write(codec?.encode(data) ?? data, to: file, atomic: false)
                records[name] = reference
            }
        }
        let index = try encoder.encode(Index(
            format: 2, checkpoint: ledger.checkpoint, records: records, authority: authority
        ))
        try write(codec?.encode(index) ?? (indexPrefix + index), to: url) { committed = true }
        reclaimUnreferencedFiles(at: url, retained: Set(records.values.map(\.file)), codec: codec)
    }

    private static func withFileLock<T>(at url: URL, operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.appendingPathExtension("lock").path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        // A second owner must retry rather than collect another writer's pending files.
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private static func reclaimLegacyWritesAfterLoad(at url: URL, codec: CloudSyncStateCodec?) {
        guard codec == nil else { return }
        do {
            try reclaimLegacyAtomicWrites(
                in: FileManager.default.temporaryDirectory, fileName: url.lastPathComponent
            )
        } catch {
            PlozzLog.sync.error("Live TV legacy write cleanup failed code=\((error as NSError).code)")
        }
    }

    private static func decodeIndex(_ data: Data, codec: CloudSyncStateCodec?) throws -> Data {
        if CloudSyncStateCodec.isSealed(data) {
            guard let codec else { throw CloudSyncStateCodec.Failure.keyUnavailable }
            return try codec.decode(data)
        }
        if data.starts(with: indexPrefix) {
            guard codec == nil else { throw CloudSyncStateCodec.Failure.invalidEnvelope }
            return data.dropFirst(indexPrefix.count)
        }
        return data
    }

    private static func entryURL(_ id: UUID, indexURL: URL, codec: CloudSyncStateCodec?) -> URL {
        directory(indexURL).appendingPathComponent(id.uuidString + (codec == nil ? ".record" : ".sealed"))
    }

    private static func reclaimUnreferencedFiles(
        at url: URL, retained: Set<UUID>, codec: CloudSyncStateCodec?
    ) {
        do {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
            for file in try FileManager.default.contentsOfDirectory(
                at: directory(url), includingPropertiesForKeys: Array(keys)
            ) {
                guard file.pathExtension == (codec == nil ? "record" : "sealed"),
                      let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      !retained.contains(id) else { continue }
                let values = try file.resourceValues(forKeys: keys)
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            PlozzLog.sync.error("Sync retired entry cleanup failed code=\((error as NSError).code)")
        }
    }

    /// Called before the channel starts writing, after its committed state loaded.
    static func reclaimLegacyAtomicWrites(in root: URL, fileName: String) throws {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        for folder in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys))
        where folder.lastPathComponent.hasPrefix("NSIRD_") {
            let attributes = try folder.resourceValues(forKeys: keys)
            guard attributes.isDirectory == true, attributes.isSymbolicLink != true else { continue }
            let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))
            guard files.count == 1, let file = files.first, file.lastPathComponent == fileName else { continue }
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try manager.removeItem(at: file)
            try manager.removeItem(at: folder)
        }
    }

    private static func directory(_ url: URL) -> URL { url.appendingPathExtension("entries") }

    private static func write(
        _ data: Data, to url: URL, atomic: Bool = true, onCommit: () -> Void = {}
    ) throws {
        // Entry names are immutable and unreferenced until the index commits.
        try data.write(to: url, options: atomic ? .atomic : .withoutOverwriting)
        onCommit()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var file = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }

    private static func readIfPresent(_ url: URL, maximumBytes: Int) throws -> Data? {
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= maximumBytes else { throw CloudSyncStateCodec.Failure.tooLarge }
            return try Data(contentsOf: url, options: .alwaysMapped)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }
}
