#if DEBUG
import CoreUI
import FeatureLiveTVCore
import SwiftUI

struct PrototypeInspector: View {
    let model: LiveTVPrototypeModel
    let selectedID: String?
    let watch: (String) -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        ScrollView {
            if let id = selectedID ?? model.visibleChannels.first?.id,
               let channel = model.channel(id: id) {
                VStack(alignment: .leading, spacing: PrototypeLayout.gap) {
                    PrototypeStationMark(channel: channel, size: 110)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PrototypeLayout.gap)
                    Text(channel.name).font(.title2.bold())
                    Text(channel.category)
                        .font(.subheadline).foregroundStyle(palette.secondaryText)
                    Text(channel.tagline)
                    Button("Watch channel", systemImage: "play.fill") { watch(id) }
                        .buttonStyle(PrototypeButtonStyle())
                    Button(
                        model.favoriteIDs.contains(id) ? "Remove favorite" : "Add favorite",
                        systemImage: model.favoriteIDs.contains(id) ? "star.fill" : "star"
                    ) { model.toggleFavorite(id) }
                        .buttonStyle(PrototypeButtonStyle())
                    Divider()
                    Label("No guide connected", systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(PrototypeLayout.gap)
            }
        }
        .background(palette.cardSurface, in: RoundedRectangle(cornerRadius: PrototypeLayout.radius))
    }
}
#endif
