import SwiftUI

/// Horizontal candidates report their readable width to `ViewThatFits`.
/// The vertical fallback uses the available width and lets labels grow in height.
public struct HeroActionRow<Content: View>: View {
    private let stacksVertically: Bool
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat
    private let content: Content

    public init(
        stacksVertically: Bool = false,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.stacksVertically = stacksVertically
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let layout = stacksVertically
            ? AnyLayout(VStackLayout(alignment: alignment, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
            .fixedSize(horizontal: !stacksVertically, vertical: true)
    }
}

/// STEAL baseline buttons
#if DEBUG
#Preview("Actions") {
    HeroActionRow(alignment: .leading, spacing: 16) {
        Button("Play", systemImage: "play.fill") {}
        Button("Trailer", systemImage: "film") {}
    }
    .padding(80)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    .background(.black)
}
#endif
