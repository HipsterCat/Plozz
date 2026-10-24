import Foundation
import os

/// A server-authored chapter on the playback timeline, independent of skip markers.
public struct MediaChapter: Hashable, Sendable, Identifiable {
    public let start: TimeInterval
    public let title: String?
    public let imageURL: URL?

    /// Chapter starts are unique within a normalized playback request.
    public var id: TimeInterval { start }

    public init(start: TimeInterval, title: String? = nil, imageURL: URL? = nil) {
        self.start = start
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmed?.isEmpty == false ? trimmed : nil
        self.imageURL = imageURL
    }

    public static func normalized(_ chapters: [Self], duration: TimeInterval?) -> [Self] {
        let limit = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        var starts = Set<TimeInterval>()
        let result = chapters.filter { chapter in
            chapter.start.isFinite && chapter.start >= 0 && chapter.start < Double(Int.max)
                && (limit.map { chapter.start < $0 } ?? true)
                && starts.insert(chapter.start).inserted
        }.sorted { $0.start < $1.start }
        if result.count != chapters.count {
            Logger(subsystem: "com.plozz.app", category: "playback")
                .warning("Ignoring invalid or duplicate chapter positions.")
        }
        return result
    }

    /// The next chapter starts the next interval; no chapter is invented before
    /// the first supplied start, or after the end of the video.
    public static func currentID(
        in chapters: [Self], at seconds: TimeInterval, duration: TimeInterval
    ) -> ID? {
        guard seconds.isFinite, seconds >= 0,
              !duration.isFinite || duration <= 0 || seconds < duration else { return nil }
        return chapters.last { $0.start <= seconds }?.id
    }
}
