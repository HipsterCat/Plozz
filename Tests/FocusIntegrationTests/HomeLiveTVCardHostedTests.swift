import CoreModels
@testable import AppShell
@testable import CoreUI
import SwiftUI
import TVUIKit
import UIKit
import XCTest

@MainActor
final class HomeLiveTVCardHostedTests: XCTestCase {
    func testNativeButtonHighlightsAndColdLogosRenderThroughSidebarMask() async throws {
        let logoURL = try XCTUnwrap(URL(string: "https://fixture.invalid/\(UUID())/channel-logo.png"))
        let logo = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 60)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 10, y: 10, width: 100, height: 40))
        }
        let response = try XCTUnwrap(HTTPURLResponse(
            url: logoURL, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "image/png", "Cache-Control": "max-age=3600"]
        ))
        let cache = try XCTUnwrap(ArtworkSession.shared.configuration.urlCache)
        let request = URLRequest(url: logoURL)
        cache.storeCachedResponse(
            CachedURLResponse(response: response, data: try XCTUnwrap(logo.pngData())), for: request
        )
        defer { cache.removeCachedResponse(for: request) }
        let logoKey = HeroLogoMemo.key(for: [.remote(logoURL)])
        XCTAssertNil(HeroLogoMemo.value(for: logoKey), "Exercise cold view loading, not prewarmed prepared pixels.")
        var focused: [String] = []
        let channels = channels(count: 3, logoURL: logoURL)
        let (window, host, previous) = try makeWindow(
            PinnedSidebarLeadingFade(isActive: true, inset: 80, verticalOverhang: 40) {
                HStack(spacing: 50) {
                    ForEach(channels) { channel in
                        HomeLiveTVCard(channel: channel, width: 480) { focused.append($0.route.channelID) }
                    }
                }
            }
        )
        defer { close(window, host: host, previous: previous) }
        try await Task.sleep(for: .milliseconds(350))
        let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
        let cards = focusItems(in: window).sorted { frame($0, in: window).minX < frame($1, in: window).minX }
        XCTAssertEqual(cards.count, 3)
        XCTAssertFalse(cards.contains { $0 is TVCardView }, "Use the system Button style, not a second hosted TVCardView.")
        let logoDeadline = ContinuousClock.now + .seconds(4)
        while HeroLogoMemo.value(for: logoKey) == nil, ContinuousClock.now < logoDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(HeroLogoMemo.value(for: logoKey))
        for (index, card) in cards.enumerated() {
            try await focus(card, in: host, system: system)
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(focused.last, channels[index].route.channelID, "Actual button focus must update the Home hero.")
            let image = capture(window, name: "home-live-native-button-\(index)")
            for (otherIndex, other) in cards.enumerated() {
                let bounds = frame(other, in: window)
                XCTAssertEqual(bounds.width, 480, accuracy: 1)
                XCTAssertEqual(bounds.height, 270, accuracy: 1)
                let background = try sample(image, at: CGPoint(
                    x: bounds.minX + bounds.width * 0.85, y: bounds.minY + bounds.height * 0.85
                ))
                if otherIndex == index {
                    XCTAssertGreaterThan(background[0], 45, "The native card's dark sheen must brighten its resting surface.")
                } else {
                    XCTAssertLessThan(background[0], 45, "The previous card must relinquish its system highlight.")
                }
                let pixel = try sample(image, at: CGPoint(
                    x: bounds.minX + bounds.width * 0.20, y: bounds.minY + bounds.height * 0.56
                ))
                XCTAssertGreaterThan(Int(pixel[0]) - Int(pixel[1]), 150, "Loaded logos must be visible, not just present in a cache.")
            }
        }
    }

    func testRapidProductionRowScrollingRetiresOldFocusPresentation() async throws {
        let (window, host, previous) = try makeWindow(
            HomeChannelRowFixture(channels: channels(count: 8))
                .environment(\.plozzPinnedSidebarActive, true)
                .environment(\.plozzNavigationContentInset, 80)
        )
        defer { close(window, host: host, previous: previous) }
        try await Task.sleep(for: .milliseconds(400))
        let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
        let scroll = try XCTUnwrap(horizontalScroll(in: window))
        for fraction in [0.0, 0.3, 0.6, 1.0, 0.7, 0.1, 0.8, 0.0] {
            scroll.setContentOffset(
                CGPoint(x: (scroll.contentSize.width - scroll.bounds.width) * fraction, y: 0), animated: false
            )
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
            let visible = focusItems(in: window).filter {
                let bounds = frame($0, in: window)
                return bounds.midX > 80 && bounds.midX < window.bounds.width - 80
            }
            let target = try XCTUnwrap(visible.sorted {
                abs(frame($0, in: window).midX - window.bounds.midX)
                    < abs(frame($1, in: window).midX - window.bounds.midX)
            }.first)
            try await focus(target, in: host, system: system)
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(800))
        let current = try XCTUnwrap(system.focusedItem)
        let image = capture(window, name: "home-live-native-button-rapid-production-row")
        let cards = focusItems(in: window)
        XCTAssertTrue(cards.contains { $0 === current })
        var highlighted = 0
        for card in cards {
            let bounds = frame(card, in: window)
            guard bounds.minX > 100, bounds.maxX < window.bounds.maxX else { continue }
            let pixel = try sample(image, at: CGPoint(
                x: bounds.minX + bounds.width * 0.85, y: bounds.minY + bounds.height * 0.85
            ))
            if pixel[0] > 45 { highlighted += 1 }
            XCTAssertEqual(pixel[0] > 45, card === current, "Fast scrolling must not leave a visible former card highlighted.")
        }
        XCTAssertEqual(highlighted, 1)
    }

    private func channels(count: Int, logoURL: URL? = nil) -> [HomeLiveTVChannel] {
        (0..<count).map { index in
            .init(route: .init(
                profileID: "profile", channelID: "channel-\(index)", sourceID: "source",
                sourceAuthorizationID: "approval", serverAuthorizationID: "server"
            ), name: "Channel \(index)", sourceName: "My channels", number: index + 1, logoURL: logoURL)
        }
    }

    private func makeWindow(_ content: some View) throws -> (UIWindow, HomeChannelFocusHost, UIWindow?) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let host = HomeChannelFocusHost(rootView: AnyView(content
            .environment(\.plozzCardFocusStyle, .system)
            .environment(\.themePalette, .dark)
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)))
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return (window, host, previous)
    }

    private func close(_ window: UIWindow, host: HomeChannelFocusHost, previous: UIWindow?) {
        host.target = nil
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKeyAndVisible()
    }

    private func focus(_ target: any UIFocusItem, in host: HomeChannelFocusHost, system: UIFocusSystem) async throws {
        host.target = target
        system.requestFocusUpdate(to: host)
        system.updateFocusIfNeeded()
        let deadline = ContinuousClock.now + .seconds(2)
        while system.focusedItem !== target, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(system.focusedItem === target)
    }

    private func focusItems(in window: UIWindow) -> [any UIFocusItem] {
        var containers: [any UIFocusItemContainer] = [window]
        var seen = Set<ObjectIdentifier>()
        var items = Set<ObjectIdentifier>()
        var result: [any UIFocusItem] = []
        while let container = containers.popLast() {
            guard seen.insert(ObjectIdentifier(container)).inserted else { continue }
            let bounds = container.coordinateSpace.convert(window.bounds, from: window)
            for item in container.focusItems(in: bounds) {
                if let children = item.focusItemContainer { containers.append(children) }
                if let view = item as? UIView { containers.append(view) }
                if item.canBecomeFocused, !(item is UIScrollView), items.insert(ObjectIdentifier(item)).inserted {
                    result.append(item)
                }
            }
        }
        return result
    }

    private func frame(_ item: any UIFocusItem, in window: UIWindow) -> CGRect {
        NavigationRowFocusRequester.frame(of: item, relativeTo: window) ?? .zero
    }

    private func horizontalScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.width > scroll.bounds.width { return scroll }
        return view.subviews.lazy.compactMap { self.horizontalScroll(in: $0) }.first
    }

    private func capture(_ window: UIWindow, name: String) -> UIImage {
        let image = DetailTransitionSnapshot.image(of: window)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }

    private func sample(_ image: UIImage, at point: CGPoint) throws -> [UInt8] {
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(
            x: point.x * image.scale, y: point.y * image.scale, width: 1, height: 1
        )))
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel
    }
}

private struct HomeChannelRowFixture: View {
    let channels: [HomeLiveTVChannel]
    @State private var title = ""

    var body: some View {
        VStack {
            Text(verbatim: title).font(.title).foregroundStyle(.white).frame(height: 200)
            MediaRowView(
                title: Text(verbatim: "Live TV"), items: [], style: .landscape,
                liveChannels: channels,
                onLiveChannelFocused: { channel in
                    withAnimation(.easeInOut(duration: 0.25)) { title = channel.name }
                }, onSelect: { _ in }
            )
        }
    }
}

@MainActor
private final class HomeChannelFocusHost: UIHostingController<AnyView> {
    weak var target: (any UIFocusEnvironment)?
    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        target.map { [$0] } ?? super.preferredFocusEnvironments
    }
}
