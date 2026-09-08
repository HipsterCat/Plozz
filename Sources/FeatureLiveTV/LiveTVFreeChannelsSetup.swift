#if DEBUG
import CoreUI
import SwiftUI

struct LiveTVFreeChannelsSetup: View {
    let sources: LiveTVSourceManagementModel
    let didConfigurePlaylist: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text("Try free US channels").font(.headline)
                Text("This adds a public playlist from iptv-org and public program guides. Availability and guide matches vary by channel and region.")
                Text("Your other sources are kept. You can disable or remove this source whenever you like.")
                if let issue = sources.mutationIssue { Text(issue.message) }
                Button("Add free channels", systemImage: "plus") {
                    let revision = sources.mutationRevision
                    sources.addFreeChannels()
                    if revision != sources.mutationRevision {
                        didConfigurePlaylist()
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        .settingsPageSurface()
        #else
        .listStyle(.plain)
        .background { SettingsPageBackground() }
        #endif
        .navigationTitle("Free channels")
    }
}
#endif
