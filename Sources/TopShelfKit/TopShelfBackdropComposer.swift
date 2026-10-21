import CryptoKit
import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

enum TopShelfBackdropComposer {
    static func imageURL(data: Data?) -> URL? {
        guard !Task.isCancelled, let directory = TopShelfStore.artworkDirectoryURL else { return nil }
        let key = SHA256.hash(data: data ?? Data()).map { String(format: "%02x", $0) }.joined()
        let destination = directory.appendingPathComponent("backdrop_\(key)_v1.jpg")
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        guard let output = imageData(data: data), !Task.isCancelled else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try output.write(to: destination, options: .atomic)
            return destination
        } catch {
            Logger(subsystem: "com.plozz.app", category: "top-shelf")
                .error("Unable to save full-screen Top Shelf artwork.")
            return nil
        }
    }

    static func imageData(data: Data?) -> Data? {
        #if canImport(UIKit)
        guard !Task.isCancelled else { return nil }
        let image = data.flatMap(UIImage.init(data:))
        if data != nil, image == nil {
            Logger(subsystem: "com.plozz.app", category: "top-shelf")
                .warning("Full-screen Top Shelf artwork could not be decoded; using a neutral background.")
        }
        let size = CGSize(width: 1920, height: 1080)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.jpegData(withCompressionQuality: 0.88) { context in
            UIColor(white: 0.10, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            guard let image, image.size.width > 0, image.size.height > 0 else { return }
            let widthScale = size.width / image.size.width
            let heightScale = size.height / image.size.height
            // A poster fallback stays intact instead of being cropped into a giant face.
            let scale = image.size.width > image.size.height
                ? max(widthScale, heightScale) : min(widthScale, heightScale) * 0.85
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                width: drawn.width, height: drawn.height
            ))
        }
        #else
        return nil
        #endif
    }
}
