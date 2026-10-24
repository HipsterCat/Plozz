#if os(tvOS)
import UIKit
import XCTest
@testable import PlozzCoreUI

@MainActor
final class ShowcaseLogoContrastTests: XCTestCase {
    func testDarkMulticolourInkImprovesWithoutChangingHighlightsOrAlpha() throws {
        let prepared = try prepare()
        let variant = try XCTUnwrap(prepared.showcaseContrast)
        let original = try pixels(prepared.image)
        let lifted = try pixels(variant.image)
        XCTAssertEqual(prepared.image.size, variant.image.size)
        XCTAssertEqual(original.count, lifted.count)
        let background = SIMD3<Double>.zero
        var darkPixels = 0, highlights = 0, translucentPixels = 0
        for i in stride(from: 0, to: original.count, by: 4) {
            XCTAssertEqual(original[i + 3], lifted[i + 3])
            guard original[i + 3] > 0 else {
                XCTAssertEqual(Array(original[i..<i + 4]), Array(lifted[i..<i + 4]))
                continue
            }
            let alpha = Double(original[i + 3])
            let before = SIMD3(Double(original[i]), Double(original[i + 1]), Double(original[i + 2])) / alpha
            let after = SIMD3(Double(lifted[i]), Double(lifted[i + 1]), Double(lifted[i + 2])) / alpha
            if alpha < 255 { translucentPixels += 1 }
            if ShowcaseLogoContrast.isDarkInk(before) {
                darkPixels += 1
                XCTAssertGreaterThan(
                    ShowcaseLogoContrast.contrast(after, background),
                    ShowcaseLogoContrast.contrast(before, background)
                )
                XCTAssertEqual(hue(before), hue(after), accuracy: 0.015)
                XCTAssertEqual(saturation(before), saturation(after), accuracy: 0.015)
            }
            if ShowcaseLogoContrast.luminance(before) >= 0.72 {
                highlights += 1
                XCTAssertEqual(Array(original[i..<i + 4]), Array(lifted[i..<i + 4]))
            }
        }
        XCTAssertGreaterThan(darkPixels, 1_000)
        XCTAssertGreaterThan(highlights, 0)
        XCTAssertGreaterThan(translucentPixels, 0)
        XCTAssertTrue(variant.improvesContrast(on: background))
        XCTAssertFalse(variant.improvesContrast(on: SIMD3(repeating: 0.28)),
                       "Keep the original if colour-preserving brightening would reduce contrast.")
        XCTAssertFalse(variant.improvesContrast(on: SIMD3(repeating: 0.9)))
        XCTAssertLessThan(prepared.luminance, 0.2, "The source image and its measurements remain original.")
    }

    func testDarkRedStaysRedRatherThanTurningPink() throws {
        let red = UIColor(red: 0.45, green: 0, blue: 0, alpha: 1)
        let prepared = try prepare(colors: [red, red])
        let variant = try XCTUnwrap(prepared.showcaseContrast)
        XCTAssertTrue(variant.improvesContrast(on: SIMD3(0.16, 0.12, 0.28)))
        let original = try pixels(prepared.image)
        let lifted = try pixels(variant.image)
        var redPixels = 0
        for i in stride(from: 0, to: original.count, by: 4) {
            guard original[i] > 0, original[i + 1] == 0, original[i + 2] == 0 else { continue }
            redPixels += 1
            XCTAssertGreaterThan(lifted[i], original[i])
            XCTAssertEqual(lifted[i + 1], 0)
            XCTAssertEqual(lifted[i + 2], 0)
            XCTAssertEqual(lifted[i + 3], original[i + 3])
        }
        XCTAssertGreaterThan(redPixels, 1_000)
    }

    func testUsefulContrastImprovementDoesNotRequireWhiteningToReachThreeToOne() {
        let original = SIMD3(0.02, 0.02, 0.18)
        let lifted = ShowcaseLogoContrast.lifted(original)
        let variant = ShowcaseLogoContrast(
            image: UIImage(), originalDarkInk: original, liftedDarkInk: lifted
        )
        XCTAssertLessThan(ShowcaseLogoContrast.contrast(lifted, .zero), 3)
        XCTAssertTrue(variant.improvesContrast(on: .zero))
        XCTAssertFalse(variant.improvesContrast(on: SIMD3(repeating: 0.28)))
        XCTAssertFalse(variant.improvesContrast(on: SIMD3(repeating: 0.9)))
    }

    func testLiftPreservesHueAndSaturationAcrossColourRangeWithoutClipping() {
        let channels = [0.0, 0.05, 0.2, 0.45, 0.75, 1.0]
        for red in channels {
            for green in channels {
                for blue in channels {
                    let original = SIMD3(red, green, blue)
                    let lifted = ShowcaseLogoContrast.lifted(original)
                    XCTAssertEqual(hue(original), hue(lifted), accuracy: 0.000001)
                    XCTAssertEqual(saturation(original), saturation(lifted), accuracy: 0.000001)
                    for channel in 0..<3 {
                        XCTAssertGreaterThanOrEqual(lifted[channel], original[channel])
                        XCTAssertLessThanOrEqual(lifted[channel], 1)
                    }
                    if ShowcaseLogoContrast.luminance(original) >= 0.72 {
                        XCTAssertEqual(lifted, original)
                    }
                }
            }
        }
    }

    func testBrightColouredMonochromeAndOutlinedLogosDoNotAllocateAVariant() throws {
        for colors in [
            [UIColor.red, .blue],
            [.white, .white],
            [.black, .black]
        ] {
            XCTAssertNil(try prepare(colors: colors).showcaseContrast)
        }
        XCTAssertNil(try prepare(highlightWidth: 55).showcaseContrast)
    }

    func testRetainedBackingIsNotLifted() throws {
        XCTAssertNotNil(try prepare(backing: .white).backgroundPlate)
        XCTAssertNil(try prepare(backing: .white).showcaseContrast)
    }

    func testWhiteAccentsDoNotHideDarkInkBehindANeutralAverage() throws {
        let prepared = try prepare(colors: [
            UIColor(red: 0.06, green: 0.07, blue: 0.20, alpha: 1),
            UIColor(red: 0.24, green: 0.06, blue: 0.04, alpha: 1)
        ], highlightWidth: 20)
        XCTAssertGreaterThan(prepared.luminance, 0.22)
        XCTAssertLessThan(max(prepared.red, prepared.green, prepared.blue)
                          - min(prepared.red, prepared.green, prepared.blue), 0.10)
        XCTAssertFalse(HeroLogoAnalysis.analyze(prepared, backgroundSample: nil).isMonochrome)
        XCTAssertNotNil(prepared.showcaseContrast)
    }

    func testRefinementAndMemoReuseTheSameBitmaps() throws {
        let prepared = try prepare()
        let variant = try XCTUnwrap(prepared.showcaseContrast)
        let processed = HeroLogoAnalysis.analyze(prepared, backgroundSample: nil)
        let url = try XCTUnwrap(URL(string: "https://logo-contrast.example.test/\(UUID()).png"))
        let key = HeroLogoMemo.key(for: [.remote(url)])
        HeroLogoMemo.store(processed, for: key)
        for _ in 0..<100 {
            let cached = try XCTUnwrap(HeroLogoMemo.value(for: key))
            let refined = HeroLogoAnalysis.refine(
                cached, backgroundSample: HeroBackgroundSample(red: 0.8, green: 0.8, blue: 0.8, luminance: 0.8)
            )
            XCTAssertTrue(refined.image === prepared.image)
            XCTAssertTrue(refined.showcaseContrast?.image === variant.image)
        }
    }

    func testPipelineCachesTheVariantAlongsideItsOriginal() async throws {
        let data = try XCTUnwrap(fixture().pngData())
        let url = try XCTUnwrap(URL(string: "https://logo-contrast.example.test/\(UUID()).png"))
        let cache = try XCTUnwrap(ArtworkSession.shared.configuration.urlCache)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "image/png", "Cache-Control": "max-age=3600"]
        ))
        cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: URLRequest(url: url))
        defer { cache.removeCachedResponse(for: URLRequest(url: url)) }
        let pipeline = HeroLogoPipeline()
        let firstResult = await pipeline.preparedLogo(for: .remote(url))
        let first = try XCTUnwrap(firstResult)
        let variant = try XCTUnwrap(first.showcaseContrast)
        let secondResult = await pipeline.preparedLogo(for: .remote(url))
        let second = try XCTUnwrap(secondResult)
        XCTAssertTrue(first.image === second.image)
        XCTAssertTrue(variant.image === second.showcaseContrast?.image)
    }

    func testToneCurvePreservesHighlightValuesAndLuminanceOrdering() {
        var previous = -1.0
        for value in stride(from: 0.0, through: 1.0, by: 0.01) {
            let rgb = SIMD3<Double>(repeating: value)
            let lifted = ShowcaseLogoContrast.lifted(rgb)
            XCTAssertGreaterThanOrEqual(lifted.x + 0.000001, previous)
            XCTAssertLessThanOrEqual(lifted.x, 1)
            if value >= 0.72 { XCTAssertEqual(lifted, rgb) }
            previous = lifted.x
        }
    }

    private func prepare(
        colors: [UIColor]? = nil, highlightWidth: CGFloat = 8, backing: UIColor = .clear
    ) throws -> PreparedLogo {
        let image = fixture(colors: colors, highlightWidth: highlightWidth, backing: backing)
        return try XCTUnwrap(HeroLogoPipeline.decodeAndPrepare(XCTUnwrap(image.pngData())))
    }

    private func fixture(
        colors: [UIColor]? = nil, highlightWidth: CGFloat = 8, backing: UIColor = .clear
    ) -> UIImage {
        let colors = colors ?? [
            UIColor(red: 0.04, green: 0.05, blue: 0.18, alpha: 1),
            UIColor(red: 0.45, green: 0.03, blue: 0.04, alpha: 1)
        ]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 160, height: 60), format: format).image { context in
            backing.setFill()
            context.fill(CGRect(x: 5, y: 5, width: 150, height: 50))
            for (index, color) in colors.enumerated() {
                color.setFill()
                context.fill(CGRect(x: 10 + index * 80, y: 10, width: 60, height: 30))
                color.withAlphaComponent(0.5).setFill()
                context.fill(CGRect(x: 10 + index * 80, y: 40, width: 60, height: 10))
                UIColor.white.setFill()
                context.fill(CGRect(x: CGFloat(12 + index * 80), y: 12, width: highlightWidth, height: 28))
            }
        }
    }

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        XCTAssertTrue(drawn)
        return bytes
    }

    private func hue(_ rgb: SIMD3<Double>) -> CGFloat {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return hue
    }

    private func saturation(_ rgb: SIMD3<Double>) -> CGFloat {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return saturation
    }
}
#endif
