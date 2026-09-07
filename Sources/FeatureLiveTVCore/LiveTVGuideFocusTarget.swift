#if DEBUG
import Foundation

public enum LiveTVGuideFocusTarget: Hashable, Sendable {
    case channel(String)
    case program(channelID: String, programID: String)

    public var channelID: String {
        switch self {
        case .channel(let id), .program(let id, _): id
        }
    }

    @MainActor
    public static func returningToPlayback(
        in model: LiveTVPrototypeModel, selectedChannelID: String?
    ) -> Self? {
        let candidates = [model.playingChannelID, selectedChannelID, model.guideChannels.first?.id]
        guard let id = candidates.compactMap({ $0 }).first(where: { id in
            model.visibleChannels.contains { $0.id == id }
        }) else { return nil }
        if let program = model.currentProgram(for: id) {
            return .program(channelID: id, programID: program.id)
        }
        return .channel(id)
    }
}
#endif
