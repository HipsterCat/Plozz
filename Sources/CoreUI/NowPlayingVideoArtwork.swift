#if canImport(UIKit) && canImport(MediaPlayer)
import CoreModels
import MediaPlayer
import MetadataKit
import UIKit

/// A backdrop and title logo, without the Continue Watching card's playback
/// chrome. Posters and sources already known to carry a title stay untouched.
public enum NowPlayingVideoArtwork {
    public static func references(for item: MediaItem) -> [ArtworkReference] {
        if item.kind == .episode { return item.seriesArtworkReferences() }
        let references = item.artworkReferences(for: .detailBackdrop) + item.artworkReferences(for: .poster)
        var seen = Set<ArtworkReference>()
        return references.filter { seen.insert($0).inserted }
    }

    @MainActor
    public static func load(
        for item: MediaItem,
        onUpdate: @escaping @MainActor (MPMediaItemArtwork) -> Void
    ) async {
        await load(
            for: item,
            textlessBackdrop: TextlessBackdropStore.shared.backdrop(for: item),
            suppressesLogo: TextlessBackdropStore.shared.suppressesLogo(for: item),
            imageLoader: { reference in
                await ArtworkImageCache.shared.image(for: reference, variant: .landscapeCard)
            },
            logoLoader: { item in
                let target = item.kind == .episode ? PosterCardView.seriesArtworkItem(for: item) : item
                return await HeroUIKitLogoRenderer.render(
                    references: item.artworkReferences(for: .logo),
                    asyncFallbackURL: {
                        await ArtworkSession.artworkResolveLimiter.run {
                            guard !Task.isCancelled else { return nil }
                            return await ArtworkRouter.shared.artworkURL(.logo, for: target)
                        }
                    }
                )
            },
            onUpdate: onUpdate
        )
    }

    @MainActor
    static func load(
        for item: MediaItem,
        textlessBackdrop: URL? = nil,
        suppressesLogo: Bool = false,
        imageLoader: @MainActor (ArtworkReference) async -> UIImage?,
        logoLoader: @MainActor (MediaItem) async -> HeroUIKitLogo?,
        onUpdate: @MainActor (MPMediaItemArtwork) -> Void
    ) async {
        let candidates = PosterCardPresentation.preferringTextless(textlessBackdrop, over: references(for: item))
        let titled = PosterCardPresentation.titleBearingArtwork(for: item)
        for reference in candidates {
            guard !Task.isCancelled else { return }
            guard let image = await imageLoader(reference) else { continue }
            guard !Task.isCancelled else { return }

            // The picture is useful immediately. An optional logo lookup must
            // never leave the system card blank or delay playback metadata.
            let usesBackdrop = !suppressesLogo && !titled.contains(reference)
                && image.size.width > image.size.height
            onUpdate(usesBackdrop ? artwork(background: image) : NowPlayingSession.artwork(from: image))
            guard usesBackdrop else { return }
            guard let logo = await logoLoader(item), !Task.isCancelled else { return }
            onUpdate(artwork(background: image, logo: logo))
            return
        }
    }

    static func artwork(background: UIImage, logo: HeroUIKitLogo? = nil) -> MPMediaItemArtwork {
        let image = logo.map {
            $0.isMonochrome ? $0.image.withTintColor(.white, renderingMode: .alwaysOriginal) : $0.image
        }
        // System controls primarily show square artwork. Supply that shape
        // ourselves instead of shrinking the logo to survive a crop of wide art.
        let side = min(background.size.width, background.size.height)
        return MPMediaItemArtwork(boundsSize: CGSize(width: side, height: side)) { size in
            composite(background: background, logo: image, coverage: logo?.coverage ?? 1, size: size)
        }
    }

    /// Use the Continue Watching picture-band budget, without its chrome.
    static func logoRect(imageSize: CGSize, coverage: Double, canvas: CGSize) -> CGRect {
        let box = ContinueWatchingCardShape.logoBox(
            cardWidth: canvas.width,
            stage: min(canvas.height, canvas.width * 9 / 16),
            edgeInset: 0
        )
        let fitted = HeroLogoFit.fittedSize(
            for: imageSize,
            maxWidth: box.width,
            maxHeight: box.height,
            coverage: coverage
        )
        return CGRect(
            x: (canvas.width - fitted.width) / 2,
            y: (canvas.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private static func composite(
        background: UIImage, logo: UIImage?, coverage: Double, size: CGSize
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let scale = max(size.width / background.size.width, size.height / background.size.height)
            let picture = CGSize(width: background.size.width * scale, height: background.size.height * scale)
            background.draw(in: CGRect(
                x: (size.width - picture.width) / 2, y: (size.height - picture.height) / 2,
                width: picture.width, height: picture.height
            ))
            guard let logo else { return }
            UIColor.black.withAlphaComponent(ContinueWatchingCardShape.artworkDim).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: size.height * 0.008),
                blur: size.height * 0.022,
                color: UIColor.black.withAlphaComponent(0.48).cgColor
            )
            logo.draw(in: logoRect(imageSize: logo.size, coverage: coverage, canvas: size))
        }
    }
}
#endif
