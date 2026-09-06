#if canImport(SwiftUI)
import SwiftUI

/// A compact filesystem container, visually distinct from a movie/show poster.
public struct MediaFolderCardLabel: View {
    private let title: String
    private let usesFocusSurface: Bool
    @Environment(\.isFocused) private var isFocused
    @Environment(\.plozzReduceTransparency) private var reduceTransparency
    @Environment(\.plozzMetrics) private var metrics
    @Environment(\.themePalette) private var palette

    public init(title: String, usesFocusSurface: Bool = false) {
        self.title = title
        self.usesFocusSurface = usesFocusSurface
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.landscapeCaptionTopSpacing) {
            RoundedRectangle(
                cornerRadius: PlozzTheme.Metrics.mediumMediaCornerRadius,
                style: .continuous
            )
            .fill(palette.fill)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .overlay {
                Image(systemName: "folder")
                    .font(.largeTitle)
                    .foregroundStyle(palette.secondaryText)
                    .accessibilityHidden(true)
            }
            .plozzMediaEdge(
                cornerRadius: PlozzTheme.Metrics.mediumMediaCornerRadius
            )

            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(PlozzCardCaption.titleColor(
                isFocused: usesFocusSurface && isFocused,
                reduceTransparency: reduceTransparency
            ))
            .padding(.horizontal, metrics.landscapeCaptionInset)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("Folder"))
        .accessibilityHint(Text("Open folder"))
    }
}
#endif
