import CoreModels
import Observation
@testable import CoreUI
@testable import FeaturePlayback
import SwiftUI
import TVUIKit
import UIKit
import XCTest

@MainActor
final class PlayerEpisodeArtworkHostedTests: XCTestCase {
    func testOnlyCurrentArtworkKeepsNativeFocusAndOverflowStaysInsidePanel() async throws {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let model = EpisodeArtworkFixtureModel()
        let entries = (1...6).map { (number: Int) in
            PlayerEpisodeEntry(
                item: MediaItem(
                    id: "episode-\(number)", title: "Episode \(number)",
                    kind: .episode, episodeNumber: number
                ),
                seasonID: "season", seasonNumber: 2
            )
        }
        let host = UIHostingController(rootView: EpisodeArtworkFixture(
            model: model, entries: entries
        ))
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }

        try await waitUntil { self.nativePosters(in: window).count == entries.count }
        for index in [0, 1, 2, 3, 2] {
            model.target = entries[index].id
            try await waitUntil {
                (UIFocusSystem.focusSystem(for: window)?.focusedItem as? TVPosterView)?
                    .accessibilityLabel == entries[index].item.title
            }
            try await Task.sleep(for: .milliseconds(250))
            let posters = nativePosters(in: window)
            XCTAssertEqual(posters.filter(\.isFocused).count, 1)
            XCTAssertEqual(model.observedFocus, .episodeItem(entries[index].id))
            XCTAssertTrue(posters.filter { $0.accessibilityLabel != entries[index].item.title }
                .allSatisfy { !$0.isFocused })
            XCTAssertTrue(posters.allSatisfy { $0.footerView == nil },
                          "Titles must remain outside the native artwork projection.")
        }

        let screenshot = DetailTransitionSnapshot.image(of: window)
        let image = try XCTUnwrap(screenshot.cgImage)
        let scale = CGFloat(image.width) / window.bounds.width
        for x: CGFloat in [448, 1468] {
            let strip = try XCTUnwrap(image.cropping(to: CGRect(
                x: x * scale, y: 440 * scale, width: 4 * scale, height: 180 * scale
            )))
            var pixels = [UInt8](repeating: 0, count: strip.width * strip.height * 4)
            let context = try XCTUnwrap(CGContext(
                data: &pixels, width: strip.width, height: strip.height,
                bitsPerComponent: 8, bytesPerRow: strip.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(strip, in: CGRect(x: 0, y: 0, width: strip.width, height: strip.height))
            let brightPixels = stride(from: 0, to: pixels.count, by: 4).filter {
                max(pixels[$0], pixels[$0 + 1], pixels[$0 + 2]) > 30
            }
            XCTAssertTrue(brightPixels.isEmpty,
                          "Artwork and native focus projection must not bleed past the panel.")
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Episode row native focus and clipped edges"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func nativePosters(in view: UIView) -> [TVPosterView] {
        (view as? TVPosterView).map { [$0] } ?? view.subviews.flatMap { nativePosters(in: $0) }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Native episode artwork did not receive the requested focus.")
        throw EpisodeArtworkFixtureError.focusTimeout
    }
}

private enum EpisodeArtworkFixtureError: Error { case focusTimeout }

@MainActor @Observable
private final class EpisodeArtworkFixtureModel {
    var target: PlayerEpisodeEntry.ID?
    var observedFocus: PlayerControls.FocusSlot?
}

private struct EpisodeArtworkFixture: View {
    let model: EpisodeArtworkFixtureModel
    let entries: [PlayerEpisodeEntry]
    @FocusState private var focus: PlayerControls.FocusSlot?
    private let layout = PlayerSequenceLayout(
        metrics: .tv, cardMetrics: .standard, contained: true, hasError: false
    )

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: layout.columnSpacing) {
                        ForEach(entries) { entry in
                            PlayerEpisodeArtworkCard(entry: entry, layout: layout, focus: $focus) {}
                                .id(entry.id)
                        }
                    }
                }
                .scrollClipDisabled()
                .modifier(PlayerEpisodePanelSurface(layout: layout))
                .frame(width: 1000)
                .onChange(of: model.target) { _, id in
                    if let id {
                        proxy.scrollTo(id, anchor: .center)
                        focus = .episodeItem(id)
                    }
                }
            }
        }
        .environment(\.plozzCardFocusStyle, .system)
        .onChange(of: focus) { _, value in model.observedFocus = value }
    }
}
