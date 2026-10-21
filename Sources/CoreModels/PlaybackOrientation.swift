import Foundation

public enum PlaybackOrientation: String, Codable, CaseIterable, Sendable {
    case auto
    case landscape
    case portrait

    public var title: LocalizedStringResource {
        switch self {
        case .auto:
            return LocalizedStringResource(
                "playback.orientation.auto", defaultValue: "Auto",
                comment: "Playback orientation preference. Follow device rotation and the system rotation lock."
            )
        case .landscape:
            return LocalizedStringResource(
                "playback.orientation.landscape", defaultValue: "Landscape",
                comment: "Playback orientation preference. Keep the full-screen video player sideways, in either landscape direction."
            )
        case .portrait:
            return LocalizedStringResource(
                "playback.orientation.portrait", defaultValue: "Portrait",
                comment: "Playback orientation preference. Keep the full-screen video player upright."
            )
        }
    }
}
