#if DEBUG
import FeatureLiveTVCore
import Foundation

struct PrototypeServerGuideRequest: Equatable {
    struct Channel: Equatable {
        let id: String
        let reference: LiveTVServerChannelReference
    }

    static let rowLimit = 12
    let channels: [Channel]
    let from: Date
    let to: Date

    init?(
        rows: [LiveTVGuideRowID],
        anchor: LiveTVGuideRowID?,
        references: [String: LiveTVServerChannelReference],
        from: Date,
        to: Date
    ) {
        guard !rows.isEmpty else { return nil }
        let center = anchor.flatMap { anchor in
            rows.firstIndex(of: anchor) ?? rows.firstIndex { $0.channelID == anchor.channelID }
        } ?? 0
        let lower = max(0, min(center - 3, rows.count - Self.rowLimit))
        let upper = min(rows.count, lower + Self.rowLimit)
        var seen = Set<String>()
        let channels = rows[lower..<upper].compactMap { row -> Channel? in
            guard let reference = references[row.channelID], seen.insert(row.channelID).inserted else {
                return nil
            }
            return Channel(id: row.channelID, reference: reference)
        }
        guard !channels.isEmpty else { return nil }
        self.channels = channels
        self.from = from
        self.to = to
    }
}
#endif
