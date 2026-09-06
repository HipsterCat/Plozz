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
            .foregroundStyle(.secondary)
        }
    }
}
