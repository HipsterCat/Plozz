#if canImport(SwiftUI) && canImport(UIKit)
import CoreModels
import CoreNetworking
import ImageIO
import SwiftUI

public struct ProviderSiteIcon<Fallback: View>: View {
    private let url: URL?
    private let size: CGFloat
    private let fallback: Fallback
    @State private var image: UIImage?

    public init(url: URL?, size: CGFloat, @ViewBuilder fallback: () -> Fallback) {
        self.url = url.flatMap(ProviderIconLoader.iconURL)
        self.size = size
        self.fallback = fallback()
    }

    public var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url else { return }
            do {
                let data = try await ProviderIconLoader().load(from: url)
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      (1...2_048).contains(width), (1...2_048).contains(height),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 128,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
                try Task.checkCancellation()
                image = UIImage(cgImage: thumbnail)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                PlozzLog.networking.debug("Provider icon unavailable; using its generic mark (code=\((error as NSError).code))")
            }
        }
    }
}
#endif
