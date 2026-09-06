#if DEBUG
import Foundation

/// The real DVR window advertised by a live `AVPlayerItem`.
///
/// Kept independent of AVFoundation so the range normalization and live-edge
/// decisions can be covered without constructing a player item.
struct LiveSeekableWindow: Equatable {
    let lowerBound: TimeInterval
    let upperBound: TimeInterval

    init?(ranges: [(start: TimeInterval, duration: TimeInterval)]) {
        let validRanges = ranges.compactMap { range -> (TimeInterval, TimeInterval)? in
            guard range.start.isFinite,
                  range.duration.isFinite,
                  range.duration > 0 else {
                return nil
            }
            let end = range.start + range.duration
            guard end.isFinite, end > range.start else { return nil }
            return (range.start, end)
        }

        // A live playlist can briefly expose disjoint ranges while refreshing.
        // The range with the newest endpoint is the only one that owns "live".
        guard let liveRange = validRanges.max(by: { $0.1 < $1.1 }) else {
            return nil
        }

        self.lowerBound = liveRange.0
        self.upperBound = liveRange.1
    }

    var duration: TimeInterval {
        upperBound - lowerBound
    }

    /// A tiny range can be a transient playlist update rather than useful DVR.
    var supportsTimeShift: Bool {
        duration >= 3
    }

    func isAtLiveEdge(
        currentTime: TimeInterval,
        tolerance: TimeInterval = 3
    ) -> Bool {
        guard currentTime.isFinite else { return false }
        return upperBound - currentTime <= tolerance
    }

    /// Seeking a fraction behind the exact boundary is more reliable for HLS
    /// playlists whose newest segment is still being finalized.
    var liveTarget: TimeInterval {
        max(lowerBound, upperBound - min(0.5, duration / 2))
    }
}
#endif
