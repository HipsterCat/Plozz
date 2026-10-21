#if canImport(SwiftUI)
import CoreModels
import SwiftUI

private struct ContinueWatchingPlaybackDetailsKey: EnvironmentKey {
    static let defaultValue = ContinueWatchingPlaybackDetails.default
}

public extension EnvironmentValues {
    var plozzContinueWatchingPlaybackDetails: ContinueWatchingPlaybackDetails {
        get { self[ContinueWatchingPlaybackDetailsKey.self] }
        set { self[ContinueWatchingPlaybackDetailsKey.self] = newValue }
    }
}

public extension ContinueWatchingPlaybackDetails {
    var cardAspectRatio: CGFloat {
        self == .detailed ? ContinueWatchingCardShape.portraitAspectRatio : 2.0 / 3.0
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .detailed: "Detailed"
        case .progressOnly: "Progress only"
        }
    }
    var detail: LocalizedStringResource {
        switch self {
        case .detailed: "Play icon, progress, and playback information."
        case .progressOnly: "A progress bar without playback text."
        }
    }
}
#endif
