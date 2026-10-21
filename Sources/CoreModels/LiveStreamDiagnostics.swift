import Foundation

public extension PlaybackDiagnostics {
    /// How a live channel's HLS session is tracking its playlist: the route the
    /// engine chose, how far behind the edge it plays, how deep the rewind
    /// window is, and what AVPlayer's access and error logs say about getting
    /// segments in. Values are raw numbers; the overlay formats them.
    struct LiveStreamFacts: Equatable, Sendable {
        /// The engine's route, e.g. `Native HLS` or `Ingest (loopback HLS)`.
        public var route: String? // l10n:content — developer-facing engine route name
        /// The playlist type AVPlayer reports: `LIVE`, `EVENT` or `VOD`.
        public var playlistType: String? // l10n:content — HLS protocol token
        public var behindLiveSeconds: Double?
        /// The seekable window's length: how far back the stream can be rewound.
        public var windowSeconds: Double?
        /// EXT-X-PROGRAM-DATE-TIME at the playhead, when the playlist carries it.
        public var programDate: Date?
        /// From AVPlayer asking for the playlist to its first frame.
        public var startupSeconds: Double?
        /// From the tune to the first frame on screen, as the viewer waited it.
        public var tuneToFirstFrameSeconds: Double?
        /// Variant switches: each new access-log event after the first.
        public var variantSwitches: Int?
        public var segmentRequests: Int?
        public var bytesTransferred: Int64?
        /// Segments that arrived after they were due.
        public var overdueSegments: Int?
        public var errorCount: Int?
        /// The last error-log entry's HTTP status, or NSURLError code.
        public var lastErrorStatus: Int?
        /// The variant playing now: its picture size and declared bandwidth.
        public var variantWidth: Int?
        public var variantHeight: Int?
        public var variantBitrate: Double?

        public init(
            route: String? = nil, playlistType: String? = nil, behindLiveSeconds: Double? = nil,
            windowSeconds: Double? = nil, programDate: Date? = nil, startupSeconds: Double? = nil,
            tuneToFirstFrameSeconds: Double? = nil, variantSwitches: Int? = nil, segmentRequests: Int? = nil,
            bytesTransferred: Int64? = nil, overdueSegments: Int? = nil, errorCount: Int? = nil,
            lastErrorStatus: Int? = nil
        ) {
            self.route = route
            self.playlistType = playlistType
            self.behindLiveSeconds = behindLiveSeconds
            self.windowSeconds = windowSeconds
            self.programDate = programDate
            self.startupSeconds = startupSeconds
            self.tuneToFirstFrameSeconds = tuneToFirstFrameSeconds
            self.variantSwitches = variantSwitches
            self.segmentRequests = segmentRequests
            self.bytesTransferred = bytesTransferred
            self.overdueSegments = overdueSegments
            self.errorCount = errorCount
            self.lastErrorStatus = lastErrorStatus
        }

        /// One access-log event, reduced to what the totals need.
        public struct AccessEvent: Equatable, Sendable {
            public var playbackType: String?
            /// The variant's declared BANDWIDTH; negative when unknown.
            public var indicatedBitrate: Double = -1
            public var startupTime: Double
            public var mediaRequests: Int
            public var bytesTransferred: Int64
            public var downloadOverdue: Int

            public init(
                playbackType: String?, indicatedBitrate: Double = -1, startupTime: Double, mediaRequests: Int,
                bytesTransferred: Int64, downloadOverdue: Int
            ) {
                self.playbackType = playbackType
                self.indicatedBitrate = indicatedBitrate
                self.startupTime = startupTime
                self.mediaRequests = mediaRequests
                self.bytesTransferred = bytesTransferred
                self.downloadOverdue = downloadOverdue
            }
        }

        /// Fold an item's access log in. AVFoundation opens a new event per
        /// variant switch and reports negative values for "unknown".
        public mutating func apply(accessLog events: [AccessEvent]) {
            guard let last = events.last else { return }
            playlistType = last.playbackType.flatMap { $0.isEmpty ? nil : $0 }
            if last.indicatedBitrate > 0, last.indicatedBitrate.isFinite { variantBitrate = last.indicatedBitrate }
            if let first = events.first, first.startupTime > 0, first.startupTime.isFinite {
                startupSeconds = first.startupTime
            }
            variantSwitches = events.count - 1
            segmentRequests = events.reduce(0) { $0 + max(0, $1.mediaRequests) }
            bytesTransferred = events.reduce(0) { $0 + max(0, $1.bytesTransferred) }
            overdueSegments = events.reduce(0) { $0 + max(0, $1.downloadOverdue) }
        }

        /// `5:42 · 1:58:00 window`-style summary pieces for the overlay.
        public var windowText: String? {
            guard let windowSeconds, windowSeconds.isFinite, windowSeconds > 0 else { return nil }
            return PlaybackDiagnostics.formatTimecode(windowSeconds)
        }

        /// `1280×720 · 3.2 Mbps`: what the stream has switched to right now.
        public var variantText: String? { // l10n:content — developer-facing figures
            var parts: [String] = []
            if let variantWidth, let variantHeight, variantWidth > 0, variantHeight > 0 {
                parts.append("\(variantWidth)×\(variantHeight)")
            }
            if variantBitrate != nil { parts.append(PlaybackDiagnostics.formatBitrate(variantBitrate)) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        public var behindText: String? {
            guard let behindLiveSeconds, behindLiveSeconds.isFinite, behindLiveSeconds >= 0 else { return nil }
            return String(format: "%.1fs", behindLiveSeconds)
        }

        public var startupText: String? { // l10n:content — developer-facing timing figures
            let parts = [
                startupSeconds.map { String(format: "AVPlayer %.2fs", $0) },
                tuneToFirstFrameSeconds.map { String(format: "tune %.2fs", $0) }
            ].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        public var segmentsText: String? { // l10n:content — developer-facing counters
            guard let segmentRequests else { return nil }
            var parts = ["\(segmentRequests) req"]
            if let bytes = PlaybackDiagnostics.formatBytes(bytesTransferred) { parts.append(bytes) }
            if let overdueSegments, overdueSegments > 0 { parts.append("\(overdueSegments) late") }
            if let variantSwitches, variantSwitches > 0 { parts.append("\(variantSwitches) switches") }
            return parts.joined(separator: " · ")
        }

        public var errorsText: String? { // l10n:content — developer-facing counters
            guard let errorCount, errorCount > 0 else { return nil }
            return lastErrorStatus.map { "\(errorCount) · last \($0)" } ?? "\(errorCount)"
        }
    }
}
