#if canImport(SwiftUI)
import SwiftUI
import CoreModels

/// The neutral stand-in for media artwork that is missing or failed to load.
///
/// One definition so a card without a poster looks the same on tvOS, iOS and
/// iPadOS. Before this existed each surface rolled its own: the tvOS cards drew
/// a glyph *and* repeated the title, while the iOS episode rows drew a bare
/// filled rectangle with no glyph at all.
///
/// Deliberately text-free. Every surface that uses this already prints the
/// item's title as a caption directly beneath the artwork, and that caption is
/// the better copy — it truncates to the card's width, follows Dynamic Type, and
/// carries the subtitle line. Repeating the title inside the artwork said the
/// same thing twice, a few points apart.
///
/// Marked decorative so VoiceOver reads the card's real label instead of
/// announcing an image.
public struct MediaArtworkPlaceholder: View {
    public enum Symbol: String, Sendable {
        case playback = "play.rectangle"
        case media = "rectangle.dashed"

        public init(for item: MediaItem) {
            self = item.scheduledAirDate != nil || TitleClassifier.isNotOwnedForBadge(item)
                ? .media : .playback
        }
    }

    private let tint: Color
    private let glyphSize: CGFloat
    private let symbol: Symbol
    private let cornerRadius: CGFloat

    /// - Parameters:
    ///   - tint: colour the wash and glyph derive from. Defaults to `.secondary`
    ///     so the placeholder tracks the theme; pass an explicit colour where the
    ///     backdrop isn't theme-controlled (e.g. over video).
    ///   - glyphSize: point size of the glyph, so a small episode thumbnail
    ///     and a full poster stay visually proportionate.
    ///   - symbol: use `.media` when no playable content is represented. It
    ///     draws an empty dashed box, without a fill or center glyph.
    ///   - cornerRadius: matches the enclosing artwork's clipping radius.
    public init(
        tint: Color = .secondary,
        glyphSize: CGFloat = 40,
        symbol: Symbol = .playback,
        cornerRadius: CGFloat = 6
    ) {
        self.tint = tint
        self.glyphSize = glyphSize
        self.symbol = symbol
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ZStack {
            if symbol == .media {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        tint.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 3])
                    )
            } else {
                tint.opacity(0.08)
                Image(systemName: symbol.rawValue)
                    .font(.system(size: glyphSize))
                    .foregroundStyle(tint)
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Placeholder") {
    MediaArtworkPlaceholder()
        .frame(width: 280, height: 420)
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(.black)
}
#endif
#endif
