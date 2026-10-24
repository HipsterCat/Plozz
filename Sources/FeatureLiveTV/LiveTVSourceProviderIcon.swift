import CoreModels
import PlozzCoreUI
import FeatureLiveTVCore
import SwiftUI

struct LiveTVSourceProviderIcon: View {
    let source: LiveTVPrototypeSource?

    var provider: ProviderKind? {
        switch source {
        case .jellyfin: .jellyfin
        case .plex: .plex
        case .emby: .emby
        case .iptv: .iptv
        case .plozz, nil: nil
        }
    }

    var body: some View {
        if let provider {
            ProviderBrandMark(provider: provider, size: size)
        } else {
            Image(systemName: "server.rack")
                .font(.system(size: 22))
                .settingsRowIcon()
                .frame(width: size, height: size)
        }
    }

    private var size: CGFloat {
        #if os(tvOS)
        40
        #else
        30
        #endif
    }
}
