import Foundation

/// Retained-pixel limits for the in-memory artwork caches, scaled to device memory.
///
/// Apple TV 4K draws at 2x, where one six-column Browse poster is about 2.5 MB
/// decoded and 1.6 MB composited. The former fixed limits held fewer composites
/// than one visible grid, so returning to an earlier row decoded and composited
/// every poster again, the composite on the main thread. Devices with at least
/// 3 GB keep several grid screens; smaller devices keep the original limits.
/// Every cache here is purged on a memory warning.
struct ArtworkMemoryBudget: Equatable {
    /// Decoded source images in `ArtworkImageCache`.
    let decodedBytes: Int
    /// Composited Browse posters.
    let compositeBytes: Int
    /// Status and count indicator layers.
    let indicatorBytes: Int
    /// Entry limit for each composite cache.
    let compositeCount: Int

    static let current = ArtworkMemoryBudget(physicalMemory: ProcessInfo.processInfo.physicalMemory)

    init(physicalMemory: UInt64) {
        // The smallest Apple TV 4K has 3 GB; its reported size can fall a little short.
        if physicalMemory >= 2_560 << 20 {
            decodedBytes = 192 << 20
            compositeBytes = 128 << 20
            indicatorBytes = 96 << 20
            compositeCount = 96
        } else {
            decodedBytes = 96 << 20
            compositeBytes = 24 << 20
            indicatorBytes = 24 << 20
            compositeCount = 64
        }
    }
}
