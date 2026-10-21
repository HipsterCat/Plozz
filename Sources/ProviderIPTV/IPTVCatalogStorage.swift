import CoreModels
import CoreNetworking
import Foundation
import SQLite3

/// Coordinates cache maintenance with connections, including off-main SQLite teardown.
public enum IPTVCatalogStorage {
    public static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IPTVCatalogs", isDirectory: true)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var connections: [URL: Int] = [:]
    nonisolated(unsafe) private static var deferredRemoval: [URL: @Sendable () -> Void] = [:]

    static func retain(_ url: URL) {
        lock.withLock { connections[url.standardizedFileURL, default: 0] += 1 }
    }

    static func release(_ url: URL) {
        let retry = lock.withLock { () -> (@Sendable () -> Void)? in
            let key = url.standardizedFileURL
            let remaining = connections[key, default: 1] - 1
            if remaining > 0 {
                connections[key] = remaining
                return nil
            }
            connections.removeValue(forKey: key)
            return deferredRemoval.removeValue(forKey: key)
        }
        retry?()
    }

    public static func catalogs(in directory: URL) throws -> [URL] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return [] }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw IPTVError.storage }
        let files = try manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        let names = files.compactMap { file -> String? in
            var name = file.lastPathComponent
            for suffix in ["-wal", "-shm", "-journal"] where name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                break
            }
            guard name.hasSuffix(".sqlite"), UUID(uuidString: String(name.dropLast(7))) != nil else { return nil }
            return name
        }
        return Set(names).sorted().map { directory.appendingPathComponent($0) }
    }

    /// The caller must hold its account-mutation lock and supply a complete credential inventory.
    /// Recent unowned files may be between successful sign-in and account persistence.
    public static func removeUnreferenced(
        _ catalogs: [URL], retaining identities: Set<UUID>, removed: Set<UUID>,
        now: Date = Date(), retryAfterClose: @escaping @Sendable () -> Void
    ) throws {
        try lock.withLock {
            for url in catalogs {
                guard let identity = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
                let key = url.standardizedFileURL
                guard !identities.contains(identity) else {
                    deferredRemoval.removeValue(forKey: key)
                    continue
                }
                let files = try regularFiles(for: url)
                guard !files.isEmpty else { continue }
                if !removed.contains(identity) {
                    let dates = try files.map {
                        try $0.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                    }
                    guard dates.allSatisfy({
                        guard let modified = $0.contentModificationDate, let created = $0.creationDate else { return false }
                        return max(modified, created) < now.addingTimeInterval(-86_400)
                    }) else { continue }
                }
                guard connections[key, default: 0] == 0 else {
                    deferredRemoval[key] = retryAfterClose
                    continue
                }
                // Remove the main file last so an interrupted cleanup remains discoverable.
                for file in files.reversed() { try FileManager.default.removeItem(at: file) }
                deferredRemoval.removeValue(forKey: key)
            }
        }
    }

    /// Uses SQLite recovery, never unlinking journals belonging to a saved catalogue.
    /// No account lock is held during potentially large checkpoint I/O.
    @discardableResult
    public static func reclaimJournal(at url: URL) throws -> Bool {
        retain(url)
        var closed = true
        defer { if closed { release(url) } }
        guard !(try regularFiles(for: url)).isEmpty,
              try journalBytes(url) > IPTVCatalog.maximumRetainedJournalBytes else { return true }
        var db: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let db else {
            if let db { closed = sqlite3_close(db) == SQLITE_OK }
            throw IPTVError.storage
        }
        defer {
            let status = sqlite3_close(db)
            closed = status == SQLITE_OK
            if status != SQLITE_OK { PlozzLog.networking.error("IPTV maintenance close failed sqlite=\(status)") }
        }
        // Load the schema so SQLite discovers the WAL before checkpointing.
        guard sqlite3_exec(db, "PRAGMA schema_version", nil, nil, nil) == SQLITE_OK else {
            throw IPTVError.storage
        }
        return reclaimJournal(db: db, url: url)
    }

    @discardableResult
    static func reclaimJournal(db: OpaquePointer?, url: URL) -> Bool {
        do {
            guard try journalBytes(url) > IPTVCatalog.maximumRetainedJournalBytes else { return true }
        } catch {
            PlozzLog.networking.error("IPTV journal size could not be read code=\((error as NSError).code)")
            return false
        }
        let status = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        if status == SQLITE_BUSY || status == SQLITE_LOCKED {
            PlozzLog.networking.debug("IPTV journal reclamation deferred for an active reader")
        } else if status != SQLITE_OK {
            PlozzLog.networking.error("IPTV journal reclamation failed sqlite=\(status)")
        }
        return status == SQLITE_OK
    }

    private static func journalBytes(_ url: URL) throws -> Int {
        do {
            return try URL(fileURLWithPath: url.path + "-wal")
                .resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        } catch CocoaError.fileReadNoSuchFile {
            return 0
        }
    }

    private static func regularFiles(for url: URL) throws -> [URL] {
        var files: [URL] = []
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            do {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw IPTVError.storage }
                files.append(file)
            } catch CocoaError.fileReadNoSuchFile {
                continue
            }
        }
        return files
    }
}
