import CoreModels
import SwiftUI

public struct SeasonDownloadRowLabel: View {
    private let title: LocalizedStringResource
    private let status: LocalizedStringResource
    private let statusSystemImage: String

    public init(
        title: LocalizedStringResource,
        status: LocalizedStringResource,
        statusSystemImage: String
    ) {
        self.title = title
        self.status = status
        self.statusSystemImage = statusSystemImage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(Color.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Label {
                Text(status)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: statusSystemImage)
            }
            .font(.caption)
            .foregroundStyle(Color.secondary)
        }
    }
}

private enum SeasonDownloadRowMetrics {
    static let artworkWidth: CGFloat = 46
    static let artworkHeight: CGFloat = 68
    static let spacing: CGFloat = 12
}

public struct SeasonDownloadRowArtwork<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(
                width: SeasonDownloadRowMetrics.artworkWidth,
                height: SeasonDownloadRowMetrics.artworkHeight
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .plozzMediaEdge(cornerRadius: 6)
            .accessibilityHidden(true)
    }
}

public struct SeasonDownloadRowContent<Artwork: View, Accessory: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let title: LocalizedStringResource
    private let status: LocalizedStringResource
    private let statusSystemImage: String
    private let showsRequestAction: Bool
    private let completedDownloadCount: Int
    private let artwork: Artwork
    private let accessory: Accessory

    public init(
        title: LocalizedStringResource,
        status: LocalizedStringResource,
        statusSystemImage: String,
        showsRequestAction: Bool = false,
        completedDownloadCount: Int = 0,
        @ViewBuilder artwork: () -> Artwork,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.status = status
        self.statusSystemImage = statusSystemImage
        self.showsRequestAction = showsRequestAction
        self.completedDownloadCount = completedDownloadCount
        self.artwork = artwork()
        self.accessory = accessory()
    }

    public var body: some View {
        let contentLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: SeasonDownloadRowMetrics.spacing))
        HStack(
            alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center,
            spacing: SeasonDownloadRowMetrics.spacing
        ) {
            artwork
            contentLayout {
                VStack(alignment: .leading, spacing: 4) {
                    SeasonDownloadRowLabel(
                        title: title,
                        status: status,
                        statusSystemImage: statusSystemImage
                    )
                    if completedDownloadCount > 0 {
                        Text("Downloaded: \(completedDownloadCount.formatted())")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsRequestAction {
                    Text("Request")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }
                accessory
            }
        }
        .contentShape(Rectangle())
        #if os(iOS)
        .alignmentGuide(.listRowSeparatorLeading) {
            $0[.leading] + SeasonDownloadRowMetrics.artworkWidth + SeasonDownloadRowMetrics.spacing
        }
        #endif
    }
}
