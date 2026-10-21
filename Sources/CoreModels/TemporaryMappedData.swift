import Foundation
import os
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Immutable temporary bytes backed by an unlinked file, reclaimed with the last Data owner.
public enum TemporaryMappedData {
    private static let logger = Logger(subsystem: "com.plozz.app", category: "temporary-storage")

    public static func store(_ bytes: Data, in directory: URL = FileManager.default.temporaryDirectory) throws -> Data {
        try Task.checkCancellation()
        guard !bytes.isEmpty else { return bytes }
        var name = Array(directory.appendingPathComponent(".plozz-data-XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&name)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        // Unlink before writing so process termination cannot leave payload files.
        guard unlink(name) == 0 else {
            let error = posixError()
            if unlink(name) != 0 { logger.error("Unable to unlink temporary data file errno=\(errno)") }
            throw error
        }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                try Task.checkCancellation()
                let count = write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
        try Task.checkCancellation()
        let mapping = mmap(nil, bytes.count, PROT_READ, MAP_PRIVATE, descriptor, 0)
        guard mapping != MAP_FAILED, let mapping else { throw posixError() }
        return Data(bytesNoCopy: mapping, count: bytes.count, deallocator: .unmap)
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
