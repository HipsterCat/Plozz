#if canImport(SwiftUI)
import CoreModels
import PlozzCoreUI
import SwiftUI

public struct ContentRatingToggle: View {
    @Bindable private var model: ContentRatingSettingsModel

    public init(model: ContentRatingSettingsModel) {
        self.model = model
    }

    public var body: some View {
        Toggle(isOn: $model.showsRatings) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    title.fixedSize()
                    examples
                }
                VStack(alignment: .leading, spacing: 6) {
                    title
                    examples
                }
            }
        }
        .accessibilityLabel(Text("Show content ratings") + Text(verbatim: ", PG-13, R"))
        .accessibilityIdentifier("show-content-ratings")
    }

    private var title: some View {
        Text("Show content ratings")
    }

    private var examples: some View {
        HStack(spacing: 5) {
            MediaBadgeChip(badge: MediaBadge("PG-13", style: .rating))
            MediaBadgeChip(badge: MediaBadge("R", style: .rating))
        }
        .environment(\.mediaBadgeScale, 0.65)
        .environment(\.plozzShowsContentRatings, true)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
#endif
