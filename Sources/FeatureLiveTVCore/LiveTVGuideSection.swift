#if DEBUG
import Foundation

public enum LiveTVGuideSection: String, Equatable, Sendable {
    case recent, favorites, channels
}

public struct LiveTVGuideChannel: Identifiable, Equatable, Sendable {
    public let channel: LiveTVPrototypeChannel
    public let section: LiveTVGuideSection
    public let startsSection: Bool
    public var id: String { channel.id }
}

/// Keep transport order stable while successful watching reorders Recents.
public struct LiveTVChannelSequence {
    private let ids: [String]

    public init(channels: [LiveTVPrototypeChannel]) {
        ids = channels.map(\.id)
    }

    public func neighbor(
        of channelID: String?, offset: Int, visibleChannels: [LiveTVPrototypeChannel]
    ) -> String? {
        let visible = Set(visibleChannels.map(\.id))
        let available = ids.filter { visible.contains($0) }
        guard let channelID, let index = available.firstIndex(of: channelID) else { return nil }
        let step = offset % available.count
        return available[(index + step + available.count) % available.count]
    }
}
#endif
