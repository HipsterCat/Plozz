import Foundation

public enum EpisodeCountBadgeStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case attached, floating

    public var id: String { rawValue }
    public static let `default`: Self = .attached

    public var displayName: LocalizedStringResource {
        switch self {
        case .attached:
            LocalizedStringResource(
                "episodeCountStyle.attached", defaultValue: "Attached",
                comment: "Episode-count badge style: the numbered badge touches the top trailing corner of the poster."
            )
        case .floating:
            LocalizedStringResource(
                "episodeCountStyle.floating", defaultValue: "Floating",
                comment: "Episode-count badge style: the numbered badge is inset from the poster edges."
            )
        }
    }
}
