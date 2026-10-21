import Foundation
import os

/// Worker-written backing, immutable after publication; never an authoritative sync store.
final class LiveTVPortableRecordStorage: @unchecked Sendable {
    static let maximumResidentBytes = 4 * 1_024 * 1_024
    static let maximumStoredBytes = 128 * 1_024 * 1_024
    private static let logger = Logger(subsystem: "com.plozz.app", category: "live-tv-sync")
    private(set) var residentBytes = 0
    private(set) var storedBytes = 0
    private let temporaryDirectory: URL

    init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.temporaryDirectory = temporaryDirectory
    }

    func store(_ bytes: Data) throws -> Data {
        try Task.checkCancellation()
        guard bytes.count <= Self.maximumStoredBytes - storedBytes else {
            throw LiveTVPortableStateError.tooLarge
        }
        if bytes.count <= Self.maximumResidentBytes - residentBytes {
            storedBytes += bytes.count
            residentBytes += bytes.count
            return bytes
        }
        let mapped = try TemporaryMappedData.store(bytes, in: temporaryDirectory)
        storedBytes += bytes.count
        return mapped
    }

    static func reclaimLegacyFiles(in root: URL) throws {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        for folder in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) {
            let prefix = "plozz-live-tv-records-"
            guard folder.lastPathComponent.hasPrefix(prefix),
                  UUID(uuidString: String(folder.lastPathComponent.dropFirst(prefix.count))) != nil else { continue }
            let attributes = try folder.resourceValues(forKeys: keys)
            guard attributes.isDirectory == true, attributes.isSymbolicLink != true else { continue }
            let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))
            guard try files.allSatisfy({ file in
                let values = try file.resourceValues(forKeys: keys)
                return values.isRegularFile == true && values.isSymbolicLink != true
                    && file.pathExtension == "record"
                    && Int(file.deletingPathExtension().lastPathComponent).map { $0 >= 0 } == true
            }) else { continue }
            for file in files { try manager.removeItem(at: file) }
            try manager.removeItem(at: folder)
        }
    }

    static let reclaimLegacyFilesOnce: Void = {
        do { try reclaimLegacyFiles(in: FileManager.default.temporaryDirectory) }
        catch { logger.error("Unable to reclaim obsolete Live TV staging: \(error.localizedDescription, privacy: .private)") }
    }()
}
