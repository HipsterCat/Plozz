#if os(iOS)
import CoreUI
import FeatureHomeCore
import SwiftUI
import UIKit
import XCTest
@testable import AppShelliOS

@MainActor
final class HeroReflectionPresentationTests: XCTestCase {
    func testTopBandReflectsTheImageBeforeTheOriginalStarts24PointsDown() throws {
        for height in [CGFloat(200), 340] {
            for scheme in [ColorScheme.light, .dark] {
                let image = try render(
                    PlozziOSExtendedHeroArtwork(height: height) { layout in
                        VStack(spacing: 0) {
                            Color(red: 1, green: 0, blue: 0).frame(height: 12)
                            Color(red: 0, green: 0, blue: 1).frame(height: 12)
                            Color(red: 0, green: 1, blue: 0)
                            Color(red: 1, green: 1, blue: 0).frame(height: 12)
                        }
                        .frame(width: layout.width, height: layout.height)
                    }
                    .environment(\.colorScheme, scheme)
                    .background(scheme == .dark ? Color.black : Color.white),
                    height: height
                )
                XCTAssertEqual(image.size, CGSize(width: 200, height: height))
                try assertColor(image, y: 4, red: false, green: false, blue: true)
                try assertColor(image, y: 18, red: true, green: false, blue: false)
                try assertColor(image, y: 30, red: true, green: false, blue: false)
                try assertColor(image, y: 42, red: false, green: false, blue: true)
                try assertColor(image, y: 60, red: false, green: true, blue: false)
                if height == 340 {
                    try assertColor(image, y: 300, red: true, green: true, blue: false)
                    try assertColor(image, y: 306, red: true, green: true, blue: false)
                    try assertColor(image, y: 330, red: false, green: true, blue: false)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "hero-top-reflection-\(height)-\(scheme)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testTopAndBottomSeamsDoNotBrightenDuringSwipeFadesOrPullScaling() throws {
        for scale in [CGFloat(1), 1.17] {
            let image = try render(
                PlozziOSExtendedHeroArtwork(height: 340) { layout in
                    Color.white.frame(width: layout.width, height: layout.height)
                }
                .scaleEffect(scale, anchor: .topLeading)
                .opacity(0.5)
                .background(Color.black),
                height: 400
            )
            for seam in [CGFloat(24), 304] {
                for offset in [-2, -1, 0, 1, 2] {
                    let y = (seam + CGFloat(offset)) * scale
                    let pixel = try rgb(image, y: y)
                    for channel in pixel {
                        XCTAssertGreaterThan(channel, 0.44, "scale=\(scale), y=\(y)")
                        XCTAssertLessThan(channel, 0.53, "Overlapping reflections must fade as one layer.")
                    }
                }
            }
        }
    }

    func testReflectedLayoutRemainsLimitedToCompactStillArtwork() {
        for role in [HeroTrailerSurfaceRole.home, .detail] {
            XCTAssertTrue(PlozziOSHeroMetrics.extendsArtwork(style: .compactPortrait, surfaceRole: role))
            XCTAssertFalse(PlozziOSHeroMetrics.extendsArtwork(style: .landscape, surfaceRole: role))
        }
    }

    private func render<Content: View>(_ content: Content, height: CGFloat) throws -> UIImage {
        let renderer = ImageRenderer(content: content
            .frame(width: 200, height: height, alignment: .topLeading)
            .clipped())
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage)
    }

    private func assertColor(
        _ image: UIImage, y: CGFloat, red: Bool, green: Bool, blue: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for (actual, expected) in zip(try rgb(image, y: y), [red, green, blue]) {
            if expected {
                XCTAssertGreaterThan(actual, 0.7, "y=\(y)", file: file, line: line)
            } else {
                XCTAssertLessThan(actual, 0.2, "y=\(y)", file: file, line: line)
            }
        }
    }

    private func rgb(_ image: UIImage, y: CGFloat) throws -> [CGFloat] {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        let offset = (Int(y * image.scale) * cgImage.width + cgImage.width / 2) * 4
        return pixels[offset..<(offset + 3)].map { CGFloat($0) / 255 }
    }
}
#endif
