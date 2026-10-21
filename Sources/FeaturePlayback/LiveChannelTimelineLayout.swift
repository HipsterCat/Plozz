import CoreModels
import Foundation

/// Where the live timeline's pieces sit, as fractions of the bar.
///
/// Without a rewind window the bar measures the programme on air, as it always
/// has. With one, the bar reaches back to cover it: when the window starts
/// before the current programme, the earlier programmes it reaches into join
/// the bar as their own sections, split the way VOD's bar splits at skip
/// markers, and the part of the bar the viewer can actually seek through is
/// filled the way VOD fills what it has buffered.
struct LiveChannelTimelineLayout: Equatable {
    /// The wall-clock span the bar measures.
    let start: Date
    let end: Date
    /// Programme boundaries inside the bar, as fractions in (0, 1).
    let boundaries: [Double]
    /// Where the seekable window begins; nil without a rewind window.
    let seekableStart: Double?
    /// What has aired so far: the live edge.
    let aired: Double
    /// What is on screen.
    let playing: Double

    /// The furthest back the bar reaches for earlier programmes, however deep
    /// the window: past this the current programme becomes a sliver.
    static let maximumLookback: TimeInterval = 4 * 3_600

    init(
        now: Date,
        program: LiveChannelProgramInfo?,
        earlierPrograms: [LiveChannelProgramInfo] = [],
        seekWindowSeconds: TimeInterval?,
        behindLiveSeconds: TimeInterval
    ) {
        let behind = behindLiveSeconds.isFinite ? max(0, behindLiveSeconds) : 0
        let window = seekWindowSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let onScreen = now.addingTimeInterval(-behind)
        let windowStart = window.map {
            now.addingTimeInterval(-min($0, Self.maximumLookback))
        }

        var start = program?.start ?? windowStart ?? now
        let end = program.map { max($0.end, now) } ?? now
        var boundaries: [Date] = []
        if let windowStart, windowStart < start {
            if program != nil {
                // Earlier programmes, newest first, until one covers the window's start.
                let earlier = earlierPrograms
                    .filter { $0.end <= start && $0.end > windowStart && $0.duration > 0 }
                    .sorted { $0.start > $1.start }
                var cursor = start
                for previous in earlier where previous.end >= cursor.addingTimeInterval(-1) {
                    boundaries.append(cursor)
                    cursor = previous.start
                    if cursor <= windowStart { break }
                }
                // Past the guide's reach the bar simply runs on to the window's start.
                if cursor > windowStart {
                    boundaries.append(cursor)
                    cursor = windowStart
                }
                start = max(cursor, now.addingTimeInterval(-Self.maximumLookback))
            } else {
                start = windowStart
            }
        }

        let span = end.timeIntervalSince(start)
        func fraction(_ date: Date) -> Double {
            guard span > 0 else { return date < start ? 0 : 1 }
            return min(max(date.timeIntervalSince(start) / span, 0), 1)
        }
        self.start = start
        self.end = end
        self.boundaries = boundaries.map(fraction).filter { $0 > 0 && $0 < 1 }.sorted()
        self.seekableStart = windowStart.map(fraction)
        self.aired = fraction(now)
        self.playing = fraction(onScreen)
    }

    /// The boundaries in the form `SkipMarkerTrackLayout.segmentedSections`
    /// cuts at: it splits at both ends of every range, so consecutive
    /// boundaries pair up, and an odd last one pairs with the bar's end.
    var maskRanges: [Range<Double>] {
        stride(from: 0, to: boundaries.count, by: 2).map { index in
            boundaries[index]..<(index + 1 < boundaries.count ? boundaries[index + 1] : 1)
        }
    }
}
