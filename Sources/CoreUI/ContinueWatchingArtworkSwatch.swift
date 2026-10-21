#if canImport(SwiftUI)
import SwiftUI
import CoreModels

public extension ContinueWatchingCardLayout {
    var cardStyle: PosterCardView.Style { self == .portrait ? .poster : .landscape }
}

/// The three supported Continue Watching presentations; portrait never uses thumbnails.
public enum ContinueWatchingArtworkStyle: String, CaseIterable, Sendable {
    /// Landscape artwork with a logo.
    case logoAndArtwork
    /// Episode thumbnails or movie artwork, respecting spoiler settings.
    case thumbnail
    case portraitPosters

    public var layout: ContinueWatchingCardLayout {
        self == .portraitPosters ? .portrait : .landscape
    }

    public var showsSeriesArtwork: Bool { self != .thumbnail }

    public var displayName: LocalizedStringResource {
        switch self {
        case .logoAndArtwork:
            return LocalizedStringResource(
                "continueWatchingArtwork.logo",
                defaultValue: "Artwork + logo",
                comment: "Continue Watching card style option in Settings: artwork with the title laid over it as a logo."
            )
        case .thumbnail:
            return LocalizedStringResource(
                "continueWatchingArtwork.thumbnail",
                defaultValue: "Thumbnail",
                comment: "Continue Watching artwork option in Settings: episode thumbnails or movie artwork."
            )
        case .portraitPosters:
            return "Poster"
        }
    }

    public var detail: LocalizedStringResource {
        switch self {
        case .logoAndArtwork:
            return "Landscape artwork with a logo."
        case .thumbnail:
            return "Episode thumbnails and movie artwork."
        case .portraitPosters:
            return "Movie and show posters."
        }
    }

    public func showsCaptions(
        settings: CardCaptionSettings, in view: CardCaptionView = .home, isShowcase: Bool = false
    ) -> Bool {
        settings.showsLabels(
            in: view, isShowcase: isShowcase, hasArtworkTitle: showsSeriesArtwork, isContinueWatching: true
        )
    }
}

/// A picture of one Continue Watching card in each
/// ``ContinueWatchingArtworkStyle``.
///
/// Fabricated throughout, like ``SpoilerModeSwatch`` — no media, network or theme.
public struct ContinueWatchingArtworkSwatch: View {
    private let style: ContinueWatchingArtworkStyle
    private var layout: ContinueWatchingCardLayout { style.layout }
    private let cornerRadius: CGFloat
    private let playbackDetails: ContinueWatchingPlaybackDetails
    private let showsCaptions: Bool
    @Environment(\.plozzReduceTransparency) private var reduceTransparency
    @Environment(\.plozzMetrics) private var metrics

    private var usesProgressOnlyPortrait: Bool { layout == .portrait && playbackDetails == .progressOnly }

    public init(
        style: ContinueWatchingArtworkStyle, cornerRadius: CGFloat = 12,
        playbackDetails: ContinueWatchingPlaybackDetails = .default, showsCaptions: Bool
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.playbackDetails = playbackDetails
        self.showsCaptions = showsCaptions
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let barHeight = max(3, height * 0.03)
            let captionHeight = barHeight * 2 + height * 0.025
            let gap = min(8, width * 0.05)
            let available = height - (showsCaptions ? captionHeight + gap : 0)
            let size = metrics.artworkSize(
                for: style.layout.cardStyle, showsSeriesArtwork: style.showsSeriesArtwork, playbackDetails: playbackDetails
            )
            let scale = ContinueWatchingArtworkStyle.allCases.reduce(CGFloat.infinity) { scale, option in
                let artwork = metrics.artworkSize(
                    for: option.layout.cardStyle, showsSeriesArtwork: option.showsSeriesArtwork,
                    playbackDetails: playbackDetails
                )
                return min(scale, min(width / artwork.width, available / artwork.height))
            }
            let cardWidth = size.width * scale
            let cardHeight = size.height * scale
            VStack(spacing: gap) {
                card(width: cardWidth, height: cardHeight, chromeScale: scale)
                if showsCaptions {
                    caption(width: cardWidth, barHeight: barHeight, spacing: height * 0.025)
                }
            }
            .frame(width: width, height: height, alignment: .center)
        }
    }

    private func card(width: CGFloat, height: CGFloat, chromeScale: CGFloat) -> some View {
        let radius = min(cornerRadius, width * 0.06)
        #if os(tvOS)
        // Keep miniature playback details legible at TV viewing distance.
        let chromeScale = chromeScale * 1.4
        #endif
        return ZStack {
            artwork(width: width, height: height)
                .frame(width: width, height: height)
            if style == .logoAndArtwork {
                wordmark(width: width)
                    .offset(y: -height * (1 - ContinueWatchingCardShape.mirrorLine) / 2)
            }
            if playbackDetails == .progressOnly {
                MediaCardPlaybackIndicators(
                    item: MediaItem(id: "continue-watching-preview", title: "", kind: .movie, runtime: 100, resumePosition: 42),
                    hidesStatus: true, badgeInset: 0,
                    progressHeight: max(1, metrics.progressBarHeight * chromeScale),
                    progressHorizontalInset: metrics.resumeChipInset * chromeScale,
                    progressBottomInset: metrics.resumeChipInset * chromeScale
                )
            } else {
                ResumeChipOverlay(
                    item: MediaItem(id: "continue-watching-preview", title: "", kind: .movie, runtime: 3600, resumePosition: 1800),
                    bottomScrimStart: style.showsSeriesArtwork ? ContinueWatchingCardShape.scrimStart : 0.60,
                    bottomScrimDepth: style.showsSeriesArtwork ? ContinueWatchingCardShape.scrimDepth : 0.60
                )
                .frame(width: width / chromeScale, height: height / chromeScale)
                .scaleEffect(chromeScale)
                .frame(width: width, height: height)
            }
        }
        .plozzChromeFocused(true)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color(white: 0.5).opacity(0.3), lineWidth: 1)
        )
    }

    /// The word itself, rather than an invented title: a plausible one is read as
    /// *that* title's logo and leaves you wondering what it is, where "LOGO" is
    /// instantly understood as "whatever your logo is". Still lettering, which is
    /// the one unmistakable way to draw "a logo sits here".
    private static let logoPlaceholder = LocalizedStringResource(
        "continueWatchingArtwork.logoPlaceholder",
        defaultValue: "LOGO",
        comment: "Stand-in wordmark drawn inside the Continue Watching card preview, in place of a real title's logo."
    )

    private func wordmark(width: CGFloat) -> some View {
        Text(Self.logoPlaceholder)
            .font(.system(size: width * 0.10, weight: .black, design: .rounded))
            .tracking(width * 0.012)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .shadow(color: .black.opacity(0.55), radius: width * 0.02, y: width * 0.006)
            .padding(.horizontal, width * 0.08)
    }

    @ViewBuilder
    private func artwork(width: CGFloat, height: CGFloat) -> some View {
        switch style {
        case .logoAndArtwork:
            ExtendedArtworkFill(picture: seriesPicture(width: width))
        case .portraitPosters:
            if usesProgressOnlyPortrait {
                posterPicture(width: width)
            } else {
                ExtendedArtworkFill(
                    picture: posterPicture(width: width), artworkAspectRatio: 2.0 / 3.0, sideCrop: 0,
                    progressivelyBlursReflection: !reduceTransparency
                )
            }
        case .thumbnail:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.86, green: 0.44, blue: 0.22),
                        Color(red: 0.52, green: 0.18, blue: 0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Rectangle()
                    .fill(Color(red: 0.99, green: 0.82, blue: 0.60).opacity(0.65))
                    .frame(width: width * 0.23, height: height * 0.76)
                    .offset(x: -width * 0.26, y: -height * 0.12)
                PreviewPortraitSilhouette()
                    .fill(Color(red: 0.26, green: 0.16, blue: 0.30))
                    .frame(width: width * 0.38, height: height * 0.86)
                    .offset(x: -width * 0.08, y: height * 0.20)
                PreviewPortraitSilhouette()
                    .fill(Color(red: 0.12, green: 0.10, blue: 0.20))
                    .frame(width: width * 0.52, height: height * 1.18)
                    .offset(x: width * 0.35, y: height * 0.23)
            }
        }
    }

    private func posterPicture(width: CGFloat) -> some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.24, green: 0.52, blue: 0.62),
                        Color(red: 0.14, green: 0.28, blue: 0.44)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color(red: 0.87, green: 0.91, blue: 0.81).opacity(0.85))
                    .frame(width: width * 0.62, height: width * 0.62)
                    .offset(y: -height * 0.17)
                PreviewPortraitSilhouette()
                    .fill(Color(red: 0.10, green: 0.22, blue: 0.32))
                    .frame(width: width * 0.78, height: height * 0.56)
                    .offset(y: height * 0.03)
            }
            .frame(width: width, height: height)
        }
    }

    private func seriesPicture(width: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.20, blue: 0.46),
                    Color(red: 0.38, green: 0.16, blue: 0.48)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.45, green: 0.72, blue: 1.0).opacity(0.38), .clear],
                center: .init(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: width * 0.62
            )
            Canvas { context, size in
                var ridge = Path()
                ridge.move(to: CGPoint(x: 0, y: size.height * 0.76))
                ridge.addLine(to: CGPoint(x: size.width * 0.22, y: size.height * 0.46))
                ridge.addLine(to: CGPoint(x: size.width * 0.46, y: size.height * 0.82))
                ridge.addLine(to: CGPoint(x: size.width * 0.74, y: size.height * 0.56))
                ridge.addLine(to: CGPoint(x: size.width, y: size.height * 0.80))
                ridge.addLine(to: CGPoint(x: size.width, y: size.height))
                ridge.addLine(to: CGPoint(x: 0, y: size.height))
                ridge.closeSubpath()
                context.fill(ridge, with: .color(Color(red: 0.10, green: 0.14, blue: 0.30).opacity(0.55)))
            }
        }
    }

    struct PreviewPortraitSilhouette: Shape {
        func path(in rect: CGRect) -> Path {
            let height = min(rect.height, rect.width * 14 / 13)
            let width = height * 13 / 14
            var path = Path()
            path.addEllipse(in: CGRect(x: width * 0.34, y: 0, width: width * 0.32, height: height * 0.38))
            path.move(to: CGPoint(x: 0, y: height))
            path.addCurve(
                to: CGPoint(x: width * 0.40, y: height * 0.38),
                control1: CGPoint(x: 0, y: height * 0.52),
                control2: CGPoint(x: width * 0.36, y: height * 0.55)
            )
            path.addLine(to: CGPoint(x: width * 0.60, y: height * 0.38))
            path.addCurve(
                to: CGPoint(x: width, y: height),
                control1: CGPoint(x: width * 0.64, y: height * 0.55),
                control2: CGPoint(x: width, y: height * 0.52)
            )
            path.closeSubpath()
            return path.offsetBy(dx: rect.midX - width / 2, dy: rect.midY - height / 2)
        }
    }

    /// Optional title and detail lines, independent of artwork and playback chrome.
    private func caption(width: CGFloat, barHeight: CGFloat, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Capsule().fill(Color.primary.opacity(0.34))
                .frame(width: width * 0.58, height: barHeight)
            Capsule().fill(Color.primary.opacity(0.17))
                .frame(width: width * 0.34, height: barHeight)
        }
        .frame(width: width, alignment: .leading)
    }
}

#endif
