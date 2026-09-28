import CoreModels
@testable import CoreUI
@testable import FeatureHome
import SwiftUI
import UIKit
import XCTest

@MainActor
final class HeroLogoPresentationHostedTests: XCTestCase {
    func testCompactSeriesLogoStaysAboveSeasonsForTallSquareAndWideArtwork() async throws {
        let fixture = try await makeFixture()
        defer { fixture.close() }

        for size in [CGSize(width: 120, height: 200), CGSize(width: 200, height: 200),
                     CGSize(width: 500, height: 100)] {
            let url = try seedLogo(size: size)
            defer { removeSeededLogo(url) }
            let series = MediaItem(
                id: UUID().uuidString, title: "Series fixture", kind: .series,
                backdropURL: url, logoURL: url
            )
            let model = SeriesHeroRecedeModel()
            model.isReceded = true
            let host = UIHostingController(rootView:
                Color.black.overlay(alignment: .top) {
                    SeriesEpisodeBrowser(
                        series: series, recedeModel: model, showsSeasons: true,
                        focusAnchorID: "logo-fixture",
                        seasonContent: {
                            Color.purple.frame(height: SeriesEpisodeBrowserLayout.seasonBarHeight)
                        },
                        episodeContent: { Color.blue }
                    )
                    .padding(.top, SeriesEpisodeBrowserLayout.browserColumnTopInset)
                }
                .ignoresSafeArea()
            )
            fixture.window.rootViewController = host
            fixture.window.layoutIfNeeded()
            let key = HeroLogoMemo.key(for: [.remote(url)], hasFallback: true)
            try await waitUntil { HeroLogoMemo.value(for: key) != nil }
            try await waitUntil { (try? redBounds(in: fixture.window)) != nil }
            let bounds = try XCTUnwrap(redBounds(in: fixture.window))
            XCTAssertGreaterThan(bounds.height, 50, "A missing or clipped logo is not a spacing fix.")
            XCTAssertLessThanOrEqual(bounds.height, 201, "Source shape: \(size)")
            XCTAssertGreaterThanOrEqual(
                bounds.minY,
                SeriesEpisodeBrowserLayout.browserColumnTopInset
                    - SeriesEpisodeBrowserLayout.recededLogoHeight - 1
            )
            XCTAssertLessThanOrEqual(
                bounds.maxY, SeriesEpisodeBrowserLayout.browserColumnTopInset + 1,
                "The wordmark must not draw into the Seasons row."
            )
        }
    }

    private func seedLogo(size: CGSize) throws -> URL {
        let url = try XCTUnwrap(URL(string: "https://logo-fixture.example.test/\(UUID()).png"))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: size.width + 20, height: size.height + 20), format: format
        ).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: CGPoint(x: 10, y: 10), size: size))
        }
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "image/png", "Cache-Control": "max-age=3600"]
        ))
        let cache = try XCTUnwrap(ArtworkSession.shared.configuration.urlCache)
        cache.storeCachedResponse(
            CachedURLResponse(response: response, data: try XCTUnwrap(image.pngData())),
            for: URLRequest(url: url)
        )
        return url
    }

    private func removeSeededLogo(_ url: URL) {
        ArtworkSession.shared.configuration.urlCache?.removeCachedResponse(for: URLRequest(url: url))
    }

    private func redBounds(in window: UIWindow) throws -> CGRect? {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var bounds = CGRect.null
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if pixels[offset] > 150 && pixels[offset + 1] < 80 && pixels[offset + 2] < 80 {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return bounds.isNull ? nil : bounds
    }

    private func makeFixture() async throws -> Fixture {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        return Fixture(scene: scene)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(6)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Logo fixture did not settle.")
    }

    @MainActor
    private final class Fixture {
        let window: UIWindow
        let previous: UIWindow?

        init(scene: UIWindowScene) {
            previous = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            window.rootViewController = UIViewController()
            window.makeKeyAndVisible()
        }

        func close() {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
    }
}
