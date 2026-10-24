import Foundation

/// User-requested downloads may use space the OS can reclaim, just like the
/// capacity shown in Downloads. tvOS does not expose important-usage capacity.
public struct DownloadStorageCapacity: Sendable {
    private let readCapacity: @Sendable (URL, URLResourceKey) throws -> Int64?

    public static let device = DownloadStorageCapacity { url, key in
        let values = try url.resourceValues(forKeys: [key])
        #if os(tvOS)
        return values.volumeAvailableCapacity.map(Int64.init)
        #else
        return values.volumeAvailableCapacityForImportantUsage
        #endif
    }

    init(readCapacity: @escaping @Sendable (URL, URLResourceKey) throws -> Int64?) {
        self.readCapacity = readCapacity
    }

    public func availableBytes(at url: URL) throws -> Int64? {
        #if os(tvOS)
        return try readCapacity(url, .volumeAvailableCapacityKey)
        #else
        return try readCapacity(url, .volumeAvailableCapacityForImportantUsageKey)
        #endif
    }
}
