import CoreImage
import CoreModels
import CoreUI
import FeatureSyncSetup
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import AppShell

@MainActor
final class SetupPickerHostedTests: XCTestCase {
    func testSummaryScrollsToPageTopAndFadesOnlyAboveTheFooter() async throws {
        let groups = SyncedServerAccountGroup.groups(from: (0..<50).map { index in
            SyncedAccountDescriptor(
                id: "account-\(index)", provider: .jellyfin, serverID: "server-\(index)",
                serverName: String(format: "Library %02d", index), userID: "viewer", userName: "Viewer"
            )
        })
        try await withWindow(scheme: .dark) { window in
            window.rootViewController = UIHostingController(rootView:
                SetupSummaryView(
                    title: "Your other device is set up", serverGroups: groups,
                    profileCount: 0, actionTitle: "Done", onAction: {}
                ) { EmptyView() }
                .padding(.horizontal, 70)
                .padding(.bottom, 24)
                .background(Color.red)
                .environment(\.themePalette, ThemePalette.dark)
            )
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            let scroll = try XCTUnwrap(findScrollView(in: window))
            scroll.setContentOffset(CGPoint(x: 0, y: 400), animated: false)
            try await Task.sleep(for: .milliseconds(300))
            let viewport = scroll.convert(scroll.bounds, to: window)
            XCTAssertEqual(viewport.minY, window.bounds.minY, accuracy: 1)
            let image = snapshot(window)
            attach(image, name: "summary-page-top-and-footer-fade")
            let bitmap = try XCTUnwrap(image.cgImage)
            let pixels = try rgba(bitmap)
            func red(at y: CGFloat) -> Int {
                Int(pixels[(Int(y) * bitmap.width + Int(viewport.midX)) * 4])
            }
            XCTAssertLessThan(red(at: viewport.minY + 3), 80, "Content must reach the page edge without a top fade.")
            XCTAssertGreaterThan(red(at: viewport.maxY - 3), red(at: viewport.maxY - 70) + 100)
            for _ in 0..<5 {
                scroll.setContentOffset(CGPoint(
                    x: 0, y: scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
                ), animated: false)
                try await Task.sleep(for: .milliseconds(80))
            }
            let end = snapshot(window)
            attach(end, name: "summary-mask-at-end")
            let endBitmap = try XCTUnwrap(end.cgImage)
            let endPixels = try rgba(endBitmap)
            let offset = (Int(viewport.maxY - 30) * endBitmap.width + Int(viewport.midX)) * 4
            XCTAssertLessThan(endPixels[offset], 80, "The final card must remain opaque at the real bottom.")
        }
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }

    func testMatchingCodePresentationFitsBothRolesAndThemes() async throws {
        for (name, scheme, palette) in appearances {
            for sending in [false, true] {
                try await withWindow(scheme: scheme) { window in
                    window.rootViewController = UIHostingController(rootView:
                        SetupCodeComparisonView(code: "123 456", onResult: sending ? { _ in } : nil)
                            .padding(70)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(palette.settingsBackground)
                            .environment(\.themePalette, palette)
                    )
                    window.makeKeyAndVisible()
                    try await Task.sleep(for: .milliseconds(700))
                    attach(snapshot(window), name: "matching-code-\(name)-sending-\(sending)")
                }
            }
        }
    }

    func testSourceQRCodeIsScannableInEveryTheme() async throws {
        let invite = SyncSetupSourceInvite()
        for (name, scheme, palette) in appearances {
            try await withWindow(scheme: scheme) { window in
                window.rootViewController = UIHostingController(rootView:
                    SyncSetupSenderPicker(
                        invite: invite, inviteExpired: false,
                        devices: [DiscoveredPairingDevice(serviceName: "856E", displayName: "Living Room iPhone")],
                        code: .constant(""), onRefresh: {}, onSelect: { _ in }, onSendCode: {}, onClose: {}
                    )
                    .padding(70)
                    .background(palette.settingsBackground)
                    .environment(\.themePalette, palette)
                    .environment(\.colorScheme, scheme)
                )
                window.makeKeyAndVisible()
                let detector = try XCTUnwrap(CIDetector(
                    ofType: CIDetectorTypeQRCode,
                    context: CIContext(options: [.useSoftwareRenderer: true]),
                    options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
                ))
                let deadline = ContinuousClock.now + .seconds(5)
                var codes: [CIQRCodeFeature] = []
                repeat {
                    let image = snapshot(window)
                    let bitmap = try XCTUnwrap(image.cgImage)
                    codes = detector.features(in: CIImage(cgImage: bitmap)).compactMap { $0 as? CIQRCodeFeature }
                    if codes.map(\.messageString) == [invite.encoded()] || ContinuousClock.now >= deadline {
                        try await Task.sleep(for: .milliseconds(700))
                        attach(snapshot(window), name: "setup-picker-\(name)")
                        break
                    }
                    try await Task.sleep(for: .milliseconds(50))
                } while true
                XCTAssertEqual(codes.map(\.messageString), [invite.encoded()])
                XCTAssertGreaterThan(try XCTUnwrap(codes.first).bounds.width, 300)
            }
        }
    }

    func testNearbyCodeRetainsBodyContrastAcrossNativeFocusChanges() async throws {
        for (name, scheme, palette) in appearances {
            try await withWindow(scheme: scheme) { window in
                let probe = SetupPickerFocusProbe()
                window.rootViewController = UIHostingController(rootView:
                    SetupPickerFocusFixture(probe: probe)
                        .environment(\.themePalette, palette)
                        .environment(\.colorScheme, scheme)
                        .background(palette.settingsBackground)
                )
                window.makeKeyAndVisible()
                for row in [0, 1, 0] {
                    probe.requested = row
                    try await waitUntil { probe.focused == row && probe.frames.count == 2 }
                    // Focus state changes before the native material transition finishes.
                    try await Task.sleep(for: .milliseconds(650))
                    let focus = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem)
                    let focusedFrame = try XCTUnwrap(NavigationRowFocusRequester.frame(of: focus, relativeTo: window))
                    let label = try XCTUnwrap(probe.frames[row])
                    XCTAssertTrue(focusedFrame.contains(CGPoint(x: label.midX, y: label.midY)))
                    let image = snapshot(window)
                    attach(image, name: "setup-code-\(name)-focus-\(row)")
                    let bitmap = try XCTUnwrap(image.cgImage)
                    let pixels = try rgba(bitmap)
                    for frame in probe.frames.values {
                        let background = luminance(pixels, x: Int(frame.maxX - 8), y: Int(frame.maxY - 15),
                                                   width: bitmap.width)
                        let region = CGRect(x: frame.minX + 100, y: frame.maxY - 28,
                                            width: frame.width - 140, height: 24)
                            .intersection(window.bounds).integral
                        var readable = 0
                        for y in Int(region.minY)..<Int(region.maxY) {
                            for x in Int(region.minX)..<Int(region.maxX) {
                                let ink = luminance(pixels, x: x, y: y, width: bitmap.width)
                                if (max(ink, background) + 0.05) / (min(ink, background) + 0.05) >= 4.5 {
                                    readable += 1
                                }
                            }
                        }
                        XCTAssertGreaterThan(readable, 100, "Pairing-code glyphs must retain at least 4.5:1 contrast.")
                    }
                }
            }
        }
    }

    private var appearances: [(String, ColorScheme, ThemePalette)] {
        [("dark", .dark, .dark), ("black", .dark, .pureBlack), ("light", .light, .light)]
    }

    private func withWindow(
        scheme: ColorScheme, exercise: (UIWindow) async throws -> Void
    ) async throws {
        try await waitUntil { UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive } }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await exercise(window)
    }

    private func snapshot(_ window: UIWindow) -> UIImage {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes {
            let context = try XCTUnwrap(CGContext(
                data: $0.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    private func luminance(_ pixels: [UInt8], x: Int, y: Int, width: Int) -> Double {
        let offset = (y * width + x) * 4
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(pixels[offset]) + 0.7152 * linear(pixels[offset + 1]) + 0.0722 * linear(pixels[offset + 2])
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(predicate(), "Native focus did not reach the requested device.")
    }
}

@MainActor @Observable
private final class SetupPickerFocusProbe {
    var requested = 0
    var focused: Int?
    var frames: [Int: CGRect] = [:]
}

private struct SetupPickerFocusFixture: View {
    let probe: SetupPickerFocusProbe
    @FocusState private var focused: Int?

    var body: some View {
        VStack(spacing: 40) {
            ForEach(0..<2) { row in
                Button {} label: {
                    SyncSetupNearbyDeviceLabel(device: DiscoveredPairingDevice(
                        serviceName: "856E", displayName: row == 0 ? "Living Room iPhone" : "Family iPad"
                    ))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        probe.frames[row] = $0
                    }
                }
                .focused($focused, equals: row)
            }
        }
        .frame(width: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: probe.requested, initial: true) { _, row in focused = row }
        .onChange(of: focused) { _, row in probe.focused = row }
    }
}
