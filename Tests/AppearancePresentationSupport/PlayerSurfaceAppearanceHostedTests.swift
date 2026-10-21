import CoreUI
@testable import FeaturePlayback
import SwiftUI
import UIKit
import XCTest

@MainActor
final class PlayerSurfaceAppearanceHostedTests: XCTestCase {
    func testPlayerSurfacesInheritAppearanceAndUseUntintedNativeGlass() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }

        let state = SurfaceState()
        let probe = SurfaceProbe()
        window.rootViewController = UIHostingController(rootView: SurfaceFixture(state: state, probe: probe))
        window.makeKeyAndVisible()
        for backdrop in [Color.black, .white] {
            state.backdrop = backdrop
            #if os(tvOS)
            state.focusNativeButton = false
            #endif
            for reduced in [false, true] {
                state.reduced = reduced
                var snapshots: [[String: [UInt8]]] = []
                for scheme in [ColorScheme.dark, .light] {
                    state.scheme = scheme
                    window.overrideUserInterfaceStyle = scheme == .light ? .light : .dark
                    let image = try await capture(window)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Player-\(reduced ? "fallback" : "native")-\(scheme)-\(backdrop)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    XCTAssertEqual(probe.surroundingScheme, scheme, "Do not override the player/sheet host.")
                    XCTAssertEqual(probe.surroundingPalette, scheme == .light ? .light : .dark)
                    #if os(tvOS)
                    XCTAssertEqual(probe.surfaceScheme, .dark, "TV playback retains build 57's dark glass.")
                    XCTAssertEqual(probe.surfacePalette, .dark)
                    #else
                    XCTAssertEqual(probe.surfaceScheme, scheme)
                    XCTAssertEqual(probe.surfacePalette, scheme == .light ? .light : .dark)
                    #endif
                    var samples: [String: [UInt8]] = [:]
                    for name in ["circle", "tab", "track", "panel", "card", "native-button"] {
                        let rect = try XCTUnwrap(probe.frames[name], name)
                        samples[name] = try pixels(image, rect: rect.insetBy(dx: 4, dy: 4))
                    }
                    snapshots.append(samples)
                    if !reduced, #available(iOS 26.0, tvOS 26.0, *) {
                        let reference = try XCTUnwrap(probe.frames["reference-panel"])
                        let native = try pixels(image, rect: reference.insetBy(dx: 12, dy: 12))
                        let panel = try XCTUnwrap(probe.frames["panel"])
                        let actual = try pixels(image, rect: panel.insetBy(dx: 12, dy: 12))
                        XCTAssertEqual(luminance(actual), luminance(native), accuracy: 0.05,
                                       "Player video cards must match the unmodified native material.")
                    }

                    let circle = try XCTUnwrap(probe.frames["circle"])
                    let ink = try pixels(image, rect: CGRect(
                        x: circle.midX - 3, y: circle.midY - 3, width: 6, height: 6
                    ))
                    let surface = try pixels(image, rect: CGRect(
                        x: circle.minX + 12, y: circle.midY - 3, width: 6, height: 6
                    ))
                    let inkLevel = luminance(ink)
                    let surfaceLevel = luminance(surface)
                    #if os(iOS)
                    if reduced && scheme == .light {
                        XCTAssertLessThan(inkLevel, 0.15)
                        XCTAssertGreaterThan(surfaceLevel, 0.65)
                    } else if reduced {
                        XCTAssertGreaterThan(inkLevel, 0.85)
                        XCTAssertLessThan(surfaceLevel, 0.6)
                    }
                    #endif
                    #if os(tvOS)
                    let button = try XCTUnwrap(probe.frames["native-button"])
                    let buttonInk = luminance(try pixels(image, rect: CGRect(
                        x: button.midX - 3, y: button.midY - 3, width: 6, height: 6
                    )))
                    if reduced {
                        XCTAssertGreaterThan(buttonInk, 0.85, "Dark fallback needs a light play icon.")
                    }
                    #endif
                    #if os(iOS)
                    if !reduced {
                        XCTAssertGreaterThan(inkLevel, 0.85, "Native video controls retain white ink in Light mode.")
                    }
                    let options = try XCTUnwrap(descendant(in: window, identifier: "player-playback-options") as? UIButton)
                    XCTAssertEqual(options.tintColor, reduced && scheme == .light ? .black : .white)
                    XCTAssertEqual(options.traitCollection.userInterfaceStyle, .dark,
                                   "Only the native media menu owner uses dark appearance; the host still follows the theme.")
                    #endif
                }
                for name in ["circle", "tab", "track", "panel", "card", "native-button"] {
                    let dark = try XCTUnwrap(snapshots[0][name])
                    let light = try XCTUnwrap(snapshots[1][name])
                    XCTAssertEqual(dark.count, light.count, "Appearance must not change \(name) geometry.")
                    #if os(tvOS)
                    if reduced {
                        XCTAssertEqual(luminance(light), luminance(dark), accuracy: 0.01,
                                       "TV fallback chrome keeps its dark playback scope.")
                    }
                    #else
                    if reduced && name == "track" {
                        XCTAssertEqual(luminance(light), luminance(dark), accuracy: 0.01,
                                       "Playback tracks must not invert to a pale slab in Light mode.")
                    } else if reduced {
                        XCTAssertGreaterThan(luminance(light) - luminance(dark), 0.25, name)
                    }
                    #endif
                }
            }
            #if os(tvOS)
            state.reduced = false
            _ = try await capture(window)
            state.focusNativeButton = true
            let focusedImage = try await capture(window)
            XCTAssertTrue(probe.nativeButtonFocused)
            let attachment = XCTAttachment(image: focusedImage)
            attachment.name = "Player-native-focused-\(backdrop)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let button = try XCTUnwrap(probe.frames["native-button"])
            let focusedFrame = try XCTUnwrap(nativeFocusFrame(in: window))
            XCTAssertTrue(button.contains(CGPoint(x: focusedFrame.midX, y: focusedFrame.midY)),
                          "The native focus system must actually focus the play button.")
            let ink = try pixels(focusedImage, rect: CGRect(
                x: button.midX - 3, y: button.midY - 3, width: 6, height: 6
            ))
            let surface = try pixels(focusedImage, rect: CGRect(
                x: button.minX + 10, y: button.midY - 3, width: 6, height: 6
            ))
            XCTAssertGreaterThan(abs(luminance(ink) - luminance(surface)), 0.45,
                                 "Native focus must keep the play icon readable.")
            #endif
        }
    }

    private func capture(_ window: UIWindow) async throws -> UIImage {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
    }

    private func pixels(_ image: UIImage, rect: CGRect) throws -> [UInt8] {
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: rect.integral))
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        return bytes
    }

    private func luminance(_ pixels: [UInt8]) -> Double {
        stride(from: 0, to: pixels.count, by: 4).reduce(0.0) {
            $0 + Double(pixels[$1]) * 0.2126 + Double(pixels[$1 + 1]) * 0.7152 + Double(pixels[$1 + 2]) * 0.0722
        } / Double(max(1, pixels.count / 4)) / 255
    }

    #if os(tvOS)
    private func nativeFocusFrame(in window: UIWindow) -> CGRect? {
        guard let item = UIFocusSystem(for: window)?.focusedItem else { return nil }
        var environment: (any UIFocusEnvironment)? = item
        while let current = environment {
            if let container = current.focusItemContainer {
                return container.coordinateSpace.convert(item.frame, to: window)
            }
            environment = current.parentFocusEnvironment
        }
        return nil
    }
    #endif

    #if os(iOS)
    private func descendant(in view: UIView, identifier: String) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        for child in view.subviews {
            if let result = descendant(in: child, identifier: identifier) { return result }
        }
        return nil
    }
    #endif
}

@MainActor
private final class SurfaceState: ObservableObject {
    @Published var scheme = ColorScheme.dark
    @Published var reduced = false
    @Published var backdrop = Color.black
    #if os(tvOS)
    @Published var focusNativeButton = false
    #endif
}

@MainActor
private final class SurfaceProbe {
    var frames: [String: CGRect] = [:]
    var surroundingScheme: ColorScheme?
    var surroundingPalette: ThemePalette?
    var surfaceScheme: ColorScheme?
    var surfacePalette: ThemePalette?
    #if os(tvOS)
    var nativeButtonFocused = false
    #endif
}

private struct SurfaceFixture: View {
    @ObservedObject var state: SurfaceState
    let probe: SurfaceProbe
    #if os(tvOS)
    private enum Focus { case parking, native }
    @FocusState private var focus: Focus?
    #endif

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 24) {
                Button {} label: {
                    Image(systemName: "plus").font(.system(size: 30, weight: .bold))
                }
                .buttonStyle(PlayerGlassCircleButtonStyle(diameter: 80))
                .disabled(true)
                .recordSurface("circle", probe: probe)
                Button("Info") {}
                    .buttonStyle(PlayerTabButtonStyle(focused: false))
                    .disabled(true)
                    .recordSurface("tab", probe: probe)
                PlayerControlButton("Play", systemImage: "play.fill") {}
                    #if os(iOS)
                    .disabled(true)
                    #else
                    .focused($focus, equals: .native)
                    #endif
                    .recordSurface("native-button", probe: probe)
                #if os(iOS)
                PlayerOptionsMenuButton(makeMenu: { UIMenu() }, onPresentationChange: { _ in })
                    .frame(width: 60, height: 60)
                    .background { PlayerGlassCircleSurface() }
                #endif
            }
            PlayerScrubTrackSurface(height: 20)
                .frame(width: 700)
                .recordSurface("track", probe: probe)
            Text(verbatim: "Player panel")
                .font(.title)
                .foregroundStyle(Color.primary)
                .frame(width: 700, height: 120)
                .background(SurfaceEnvironmentProbe(probe: probe, surface: true))
                .modifier(PanelGlassBackground(mediaGlass: true))
                .recordSurface("panel", probe: probe)
            if #available(iOS 26.0, tvOS 26.0, *) {
                Text(verbatim: "Player panel")
                    .font(.title)
                    .foregroundStyle(Color.primary)
                    .frame(width: 700, height: 120)
                    .background {
                        #if os(iOS)
                        Color.clear.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 32))
                        #else
                        Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))
                        #endif
                    }
                    .recordSurface("reference-panel", probe: probe)
            }
            Button {} label: {
                Text(verbatim: "Cast card")
                    .font(.title)
                    .foregroundStyle(Color.primary)
                    .frame(width: 700, height: 120)
            }
            .buttonStyle(PlayerOverVideoCardStyle(focused: false, cornerRadius: 32, mediaGlass: true))
            .disabled(true)
            .recordSurface("card", probe: probe)
            #if os(tvOS)
            Button("Focus parking") {}
                .foregroundStyle(.black)
                .focused($focus, equals: .parking)
                .onAppear { focus = .parking }
                .onChange(of: state.focusNativeButton) { _, value in
                    focus = value ? .native : .parking
                }
            #endif
        }
        .playerPlatformAppearance()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(state.backdrop)
        .background(SurfaceEnvironmentProbe(probe: probe, surface: false))
        .environment(\.colorScheme, state.scheme)
        .environment(\.themePalette, state.scheme == .light ? .light : .dark)
        .environment(\.plozzReduceTransparency, state.reduced)
        #if os(tvOS)
        .onChange(of: focus, initial: true) { _, value in
            probe.nativeButtonFocused = value == .native
        }
        #endif
    }
}

private struct SurfaceEnvironmentProbe: View {
    let probe: SurfaceProbe
    let surface: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.themePalette) private var palette

    var body: some View {
        Color.clear
            .onChange(of: scheme, initial: true) { _, value in
                if surface { probe.surfaceScheme = value } else { probe.surroundingScheme = value }
            }
            .onChange(of: palette, initial: true) { _, value in
                if surface { probe.surfacePalette = value } else { probe.surroundingPalette = value }
            }
    }
}

private extension View {
    func recordSurface(_ name: String, probe: SurfaceProbe) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe.frames[name] = $0 }
    }
}
