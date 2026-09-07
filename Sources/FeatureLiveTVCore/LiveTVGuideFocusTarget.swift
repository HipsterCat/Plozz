#if DEBUG
import Foundation

public enum LiveTVGuideFocusTarget: Hashable, Sendable {
    case channel(String, section: LiveTVGuideSection = .channels)
    case program(channelID: String, programID: String, section: LiveTVGuideSection = .channels)

    public var channelID: String {
        switch self {
        case .channel(let id, _), .program(let id, _, _): id
        }
    }

    public var rowID: LiveTVGuideRowID {
        switch self {
        case .channel(let id, let section), .program(let id, _, let section):
            LiveTVGuideRowID(channelID: id, section: section)
        }
    }

    @MainActor
    public static func returningToPlayback(
        in model: LiveTVPrototypeModel, selectedChannelID: String?,
        originRow: LiveTVGuideRowID? = nil
    ) -> Self? {
        let candidates = [model.playingChannelID, selectedChannelID, model.guideChannels.first?.channel.id]
        guard let id = candidates.compactMap({ $0 }).first(where: { id in
            model.visibleChannels.contains { $0.id == id }
        }), let row = model.guideRow(for: id, preferring: originRow?.section) else { return nil }
        if let program = model.currentProgram(for: id) {
            return .program(channelID: id, programID: program.id, section: row.section)
        }
        return .channel(id, section: row.section)
    }
}
#endif
