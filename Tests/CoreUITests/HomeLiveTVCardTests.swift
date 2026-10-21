#if canImport(UIKit)
import CoreModels
import SwiftUI
import UIKit
import XCTest
@testable import CoreUI

@MainActor
final class HomeLiveTVCardTests: XCTestCase {
    func testCachedChannelLogoKeepsItsAspectRatioInsideTheFixedCard() throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/\(UUID()).png"))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
        let prepared = PreparedLogo(image: image, luminance: 0.2, red: 1, green: 0, blue: 0, coverage: 1)
        HeroLogoMemo.store(
            HeroLogoAnalysis.analyze(prepared, backgroundSample: nil),
            for: HeroLogoMemo.key(for: [.remote(url)])
        )
        for width in [CGFloat(220), 480] {
            let renderer = ImageRenderer(content: HomeLiveTVCard(channel: channel(logoURL: url), width: width)
                .environment(\.plozzCardFocusStyle, .highlight)
                .environment(\.themePalette, .dark))
            renderer.scale = 1
            let rendered = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(rendered.width, Int(width))
            XCTAssertEqual(rendered.height, Int(ceil(width * 9 / 16)))
            var pixels = [UInt8](repeating: 0, count: rendered.width * rendered.height * 4)
            try pixels.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(
                    data: bytes.baseAddress, width: rendered.width, height: rendered.height,
                    bitsPerComponent: 8, bytesPerRow: rendered.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
            }
            var bounds = CGRect.null
            for y in 0..<rendered.height {
                for x in 0..<rendered.width {
                    let offset = (y * rendered.width + x) * 4
                    if pixels[offset] > 220, pixels[offset + 1] < 40, pixels[offset + 2] < 40 {
                        bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
            }
            XCTAssertFalse(bounds.isNull, "Home must display the warmed channel logo, not just a broadcast glyph.")
            XCTAssertEqual(bounds.width / bounds.height, 2, accuracy: 0.1, "Wide logos must fit, not crop.")
            XCTAssertLessThanOrEqual(bounds.width, width * 0.30)
            XCTAssertLessThan(bounds.maxX, width * 0.4, "The logo must leave a separate title column.")
        }
    }

    func testMissingLogoAndLongNamesKeepTheSameCardFootprint() {
        for width in [CGFloat(220), 480] {
            let view = HomeLiveTVCard(channel: channel(), width: width)
                .environment(\.plozzCardFocusStyle, .highlight)
            let size = UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 1_000, height: 600))
            XCTAssertEqual(size.width, width, accuracy: 0.5)
            XCTAssertEqual(size.height, width * 9 / 16, accuracy: 0.5)
        }
    }

    private func channel(logoURL: URL? = nil) -> HomeLiveTVChannel {
        .init(
            route: .init(
                profileID: "profile", channelID: "news", sourceID: "source",
                sourceAuthorizationID: "approval", serverAuthorizationID: "server"
            ), name: "International News and Weather", sourceName: "My channels", number: 12, logoURL: logoURL
        )
    }
}
#endif
