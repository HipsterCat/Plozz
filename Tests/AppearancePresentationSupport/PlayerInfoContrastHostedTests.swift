import CoreModels
import CoreUI
@testable import FeaturePlayback
import SwiftUI
import UIKit
import XCTest

@MainActor
final class PlayerInfoContrastHostedTests: XCTestCase {
    func testInfoBadgesRemainReadableAcrossAppAndDeviceAppearances() async throws {
        let window = try await makeWindow()
        let previous = window.windowScene?.windows.first(where: \.isKeyWindow)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        for system in [ColorScheme.light, .dark] {
            for theme in AppTheme.pickerOrder {
                let palette = ThemePalette.palette(for: theme, systemColorScheme: system)
                for effects in [
                    (name: "glass", flat: false, opaque: false, contrast: UIAccessibilityContrast.normal),
                    (name: "flat", flat: true, opaque: false, contrast: UIAccessibilityContrast.normal),
                    (name: "opaque", flat: false, opaque: true, contrast: UIAccessibilityContrast.normal),
                    (name: "increased-contrast", flat: false, opaque: false, contrast: UIAccessibilityContrast.high)
                ] {
                    let model = makeModel()
                    let probe = ContrastProbe()
                    let name = "Info-app-\(theme.rawValue)-device-\(system)-\(effects.name)"
                    window.overrideUserInterfaceStyle = system == .light ? .light : .dark
                    window.traitOverrides.accessibilityContrast = effects.contrast
                    window.rootViewController = UIHostingController(rootView:
                        ContrastInfoFixture(model: model)
                            .frame(width: 1700, height: PlayerCardMetrics.tv.cardHeight)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                probe.frame = $0
                            }
                            .environment(\.playerCardMetrics, .tv)
                            .padding(80)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(.black)
                            .environment(\.themePalette, palette)
                            .environment(\.colorScheme, palette.isLight ? .light : .dark)
                            .environment(\.plozzReducePanelGlass, effects.flat)
                            .environment(\.plozzReduceTransparency, effects.opaque)
                    )
                    window.makeKeyAndVisible()
                    let image = try await capture(window)
                    attach(image, name: name)
                    let metrics = PlayerCardMetrics.tv
                    let badgeRect = CGRect(
                        x: probe.frame.minX + metrics.contentPadding + metrics.contentHeight * 16 / 9 + metrics.columnSpacing,
                        y: probe.frame.maxY - metrics.contentPadding - 36,
                        width: 150, height: 36
                    )
                    #if os(tvOS)
                    let lightBackground = false
                    #else
                    let lightBackground = palette.isLight && (effects.flat || effects.opaque)
                    #endif
                    XCTAssertGreaterThan(try contrastingPixels(
                        image, in: badgeRect, lightBackground: lightBackground
                    ), 60, "\(name): Dolby and 5.1 must contrast with the playback surface.")
                }
            }
        }
    }

    #if os(tvOS)
    func testNativePlayerHostingPreservesReadableBadges() async throws {
        let window = try await makeWindow()
        let previous = window.windowScene?.windows.first(where: \.isKeyWindow)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        for system in [ColorScheme.light, .dark] {
            for theme in AppTheme.pickerOrder {
                let palette = ThemePalette.palette(for: theme, systemColorScheme: system)
                let model = makeModel()
                let engine = NativeVideoEngine()
                let probe = ContrastProbe()
                let name = "Native-app-\(theme.rawValue)-device-\(system)"
                window.overrideUserInterfaceStyle = system == .light ? .light : .dark
                window.rootViewController = UIHostingController(rootView:
                    CustomPlayerContainer(
                        engine: engine, model: model, subtitleModel: LiveSubtitleModel(),
                        actions: PlayerActions(), scrubPreview: nil, authenticatedHTTPResolver: nil,
                        themePalette: ThemePaletteBox(
                            makeControls: { model, actions, exit in
                                AnyView(PlayerControls(
                                    model: model, palette: palette, actions: actions, onExitToSurface: exit
                                ).background(ContrastPaletteProbe(probe: probe)))
                            },
                            makeSkipButton: { _, _, _, _ in AnyView(EmptyView()) },
                            makeUpNextCard: { _, _, _, _ in AnyView(EmptyView()) }
                        )
                    )
                    .environment(\.themePalette, palette)
                    .environment(\.colorScheme, palette.isLight ? .light : .dark)
                    .environment(\.plozzReducePanelGlass, true)
                    .ignoresSafeArea()
                )
                window.makeKeyAndVisible()
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(300))
                model.controlsVisible = true
                model.controlBar.entry = .info
                model.controlBar.focusArmed = false
                model.controlBar.settled = false
                model.controlBarVisible = true
                try await Task.sleep(for: .milliseconds(650))
                model.controlBar.settled = true
                let image = try await capture(window)
                attach(image, name: name)
                let card = try XCTUnwrap(model.subtitleLayout.frame(for: .card), name)
                let metrics = PlayerCardMetrics.tv
                let badgeRect = CGRect(
                    x: card.minX + metrics.contentPadding + metrics.contentHeight * 16 / 9 + metrics.columnSpacing,
                    y: card.maxY - metrics.contentPadding - 36,
                    width: 150, height: 36
                )
                XCTAssertGreaterThan(try contrastingPixels(image, in: badgeRect, lightBackground: false), 60,
                                     "\(name): the real native-hosted Info badges must remain readable.")
                XCTAssertEqual(probe.palette, palette, "Info must not change the surrounding browsing palette.")
                XCTAssertEqual(probe.scheme, palette.isLight ? .light : .dark,
                               "Info must not override the surrounding appearance.")
                window.rootViewController = nil
                engine.stop()
            }
        }
    }
    #endif

    func testSharedBadgeRowStillRespectsBrowsingThemes() throws {
        for system in [ColorScheme.light, .dark] {
            for theme in AppTheme.pickerOrder {
                let palette = ThemePalette.palette(for: theme, systemColorScheme: system)
                let renderer = ImageRenderer(content:
                    MediaBadgeRow(badges: makeModel().infoCard.badges)
                        .padding(12)
                        .background(palette.backgroundBase)
                        .environment(\.themePalette, palette)
                        .environment(\.colorScheme, palette.isLight ? .light : .dark)
                )
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertGreaterThan(
                    try contrastingPixels(image, in: CGRect(origin: .zero, size: image.size),
                                          lightBackground: palette.isLight),
                    60, "Browsing badges must retain \(theme.rawValue) on a \(system) device."
                )
            }
        }
    }

    private func makeModel() -> PlayerControlsModel {
        let model = PlayerControlsModel()
        model.controlsVisible = true
        model.title = "Info badge contrast"
        model.infoCard.headline = "Info badge contrast"
        model.infoCard.overview = "The playback card must stay readable independently of the browsing theme."
        model.infoCard.badges = [MediaBadge("Dolby Digital+", style: .dolby, detail: "5.1")]
        return model
    }

    private func makeWindow() async throws -> UIWindow {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return window
    }

    private func capture(_ window: UIWindow) async throws -> UIImage {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
    }

    private func contrastingPixels(
        _ image: UIImage, in rect: CGRect, lightBackground: Bool = false
    ) throws -> Int {
        let source = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(source.cropping(to: rect.integral))
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        var count = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let red = bytes[offset]
            let green = bytes[offset + 1]
            let blue = bytes[offset + 2]
            let matches = lightBackground
                ? max(red, green, blue) < 70
                : min(red, green, blue) > 180
            if matches { count += 1 }
        }
        return count
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class ContrastProbe {
    var frame: CGRect = .zero
    var palette: ThemePalette?
    var scheme: ColorScheme?
}

private struct ContrastInfoFixture: View {
    let model: PlayerControlsModel
    @FocusState private var focus: PlayerControls.FocusSlot?

    var body: some View {
        InfoPanelView(model: model, actions: PlayerOptionsActions(), focus: $focus, onClose: {})
            .playerPlatformAppearance()
    }
}

private struct ContrastPaletteProbe: View {
    let probe: ContrastProbe
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear.onAppear {
            probe.palette = palette
            probe.scheme = colorScheme
        }
    }
}
