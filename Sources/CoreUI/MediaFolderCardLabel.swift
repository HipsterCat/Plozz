#if canImport(SwiftUI)
import CoreModels
import SwiftUI

/// A folder rendered with the same stable poster footprint as neighboring media.
/// The 2:3 slot stays fixed if catalog enrichment later promotes it to a show or
/// movie, avoiding grid reflow or a tvOS focus jump while scanning.
public struct MediaFolderCardLabel: View {
    private let item: MediaItem
    private let reservesSubtitleSpace: Bool
    private let action: () -> Void

    public init(
        item: MediaItem,
        reservesSubtitleSpace: Bool = true,
        action: @escaping () -> Void = {}
    ) {
        self.item = item
        self.reservesSubtitleSpace = reservesSubtitleSpace
        self.action = action
    }

    public var body: some View {
        PosterCardView(
            item: item,
            style: .poster,
            enablesAsyncArtworkFallback: false,
            reservesSubtitleSpace: reservesSubtitleSpace,
            action: action
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.title))
        .accessibilityValue(Text("Folder"))
        .accessibilityHint(Text("Open folder"))
    }
}

#if DEBUG
#Preview("Folder") {
    MediaFolderCardLabel(item: MediaItem(id: "f1", title: "Collections", kind: .folder))
        .frame(width: 280)
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(.black)
}
#endif
#endif
