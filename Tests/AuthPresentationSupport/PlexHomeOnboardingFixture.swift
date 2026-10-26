import CoreModels
@testable import CoreUI
import SwiftUI

struct PlexHomeOnboardingFixture: View {
    @State private var result: String?

    var body: some View {
        Group {
            if let result {
                Text(verbatim: result)
                    .accessibilityIdentifier("plex-home-result")
            } else {
                PlexHomeOnboardingContent(users: [
                    .init(id: "parent", name: "Alex", requiresPIN: true, isAdmin: true),
                    .init(id: "child", name: "Sam", requiresPIN: false, isRestricted: true),
                    .init(id: "guest", name: "Taylor", requiresPIN: false)
                ], reduceMotion: ProcessInfo.processInfo.arguments.contains("--plex-home-reduce-motion")) { user, addAll in
                    result = "\(user.id):\(addAll ? "all" : "one")"
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AppBackground(palette: .dark) }
        .environment(\.themePalette, .dark)
        .environment(\.colorScheme, .dark)
    }
}
