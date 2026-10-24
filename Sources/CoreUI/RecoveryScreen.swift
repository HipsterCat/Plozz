import SwiftUI

/// Shared recovery layout; hosts supply identity, explanation, actions and presentation policy.
public struct RecoveryScreen<Heading: View, Actions: View>: View {
    private let heading: Heading
    private let actions: (Axis) -> Actions

    public init(
        @ViewBuilder heading: () -> Heading,
        @ViewBuilder actions: @escaping (Axis) -> Actions
    ) {
        self.heading = heading()
        self.actions = actions
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heading
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { actions(.horizontal) }
                        VStack(alignment: .leading, spacing: 16) { actions(.vertical) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Self.cardPadding)
                .frame(maxWidth: Self.cardWidth, alignment: .leading)
                .plozzSurface(.raised, cornerRadius: 28)
                .padding(Self.outerPadding)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    #if os(tvOS)
    private static var cardWidth: CGFloat { 960 }
    private static var cardPadding: CGFloat { 48 }
    private static var outerPadding: CGFloat { 60 }
    #else
    private static var cardWidth: CGFloat { 560 }
    private static var cardPadding: CGFloat { 24 }
    private static var outerPadding: CGFloat { 20 }
    #endif
}
