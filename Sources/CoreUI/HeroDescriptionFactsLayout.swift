#if canImport(SwiftUI)
import SwiftUI

/// Gives the description the facts row's natural width without a measurement/state feedback loop.
public struct HeroDescriptionFactsLayout: Layout {
    public static let minimumWidth: CGFloat = 800
    public static let maximumWidth: CGFloat = 1200
    private let spacing: CGFloat

    public init(spacing: CGFloat = 12) {
        self.spacing = spacing
    }

    func columnWidth(factsWidth: CGFloat, availableWidth: CGFloat?) -> CGFloat {
        min(
            max(1, availableWidth ?? Self.maximumWidth),
            Self.maximumWidth,
            max(Self.minimumWidth, factsWidth)
        )
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        precondition(subviews.count == 2)
        let width = columnWidth(
            factsWidth: subviews[1].sizeThatFits(.unspecified).width,
            availableWidth: proposal.width
        )
        let column = ProposedViewSize(width: width, height: nil)
        return CGSize(
            width: width,
            height: subviews[0].sizeThatFits(column).height + spacing + subviews[1].sizeThatFits(column).height
        )
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        precondition(subviews.count == 2)
        let column = ProposedViewSize(width: bounds.width, height: nil)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: column)
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + subviews[0].sizeThatFits(column).height + spacing),
            anchor: .topLeading, proposal: column
        )
    }
}
#endif
