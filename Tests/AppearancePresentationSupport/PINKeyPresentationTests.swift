import SwiftUI
import UIKit
import XCTest
@testable import CoreUI

@MainActor
final class PINKeyPresentationTests: XCTestCase {
    func testSharedKeysKeepTheirExactSizeWithNativeGlassAndReducedTransparency() {
        for reduced in [false, true] {
            for textSize in [DynamicTypeSize.large, .accessibility3] {
                for width in [PINMetrics.keyDiameter, PINMetrics.deleteKeyWidth] {
                    let host = UIHostingController(rootView:
                        Button {} label: { Image(systemName: "delete.backward") }
                            .buttonStyle(PINKeyStyle(width: width))
                            .environment(\.plozzReduceTransparency, reduced)
                            .environment(\.dynamicTypeSize, textSize)
                    )
                    XCTAssertEqual(
                        host.sizeThatFits(in: CGSize(width: 1_920, height: 1_080)),
                        CGSize(width: width, height: PINMetrics.keyDiameter)
                    )
                }
            }
        }
    }

    func testSharedKeypadAppearanceAndLayoutAcrossDeviceSizes() async throws {
        #if os(tvOS)
        let sizes = [CGSize(width: 1920, height: 1080)]
        #else
        let sizes = [CGSize(width: 390, height: 844), CGSize(width: 1024, height: 768)]
        #endif
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        var padFrame: CGRect?
        for size in sizes {
            window.frame = CGRect(origin: .zero, size: size)
            for palette in [ThemePalette.dark, .light] {
                for reduced in [false, true] {
                    window.overrideUserInterfaceStyle = palette.isLight ? .light : .dark
                    host.rootView = AnyView(
                        PINDialPad(onDigit: { _ in }, onDelete: {})
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { padFrame = $0 }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(palette.settingsBackground)
                            .environment(\.themePalette, palette)
                            .environment(\.colorScheme, palette.isLight ? .light : .dark)
                            .environment(\.plozzReduceTransparency, reduced)
                    )
                    try await waitForHostedLayout(window)
                    let frame = try XCTUnwrap(padFrame)
                    XCTAssertEqual(frame.width, PINMetrics.padWidth, accuracy: 1)
                    XCTAssertEqual(frame.height, PINMetrics.keyDiameter * 4 + PINMetrics.keySpacing * 3, accuracy: 1)
                    XCTAssertTrue(window.bounds.contains(frame))
                    #if os(tvOS)
                    XCTAssertNotNil(UIFocusSystem.focusSystem(for: window)?.focusedItem)
                    #endif
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                        XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "pin-keys-\(Int(size.width))-light-\(palette.isLight)-reduced-\(reduced)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }
}
