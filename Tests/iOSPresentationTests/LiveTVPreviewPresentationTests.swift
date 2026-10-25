#if os(iOS)
import AVFoundation
import CoreModels
import CoreUI
import FeatureLiveTVCore
@testable import FeatureLiveTV
@testable import FeaturePlayback
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class LiveTVPreviewPresentationTests: XCTestCase {
    func testPreviewRespectsEitherVerticalBarWithoutMirroringItsInset() {
        for leading in [false, true] {
            let insets = EdgeInsets(
                top: 24, leading: leading ? 96 : 0,
                bottom: 20, trailing: leading ? 0 : 96
            )
            let layout = PrototypePreviewLayout(
                size: CGSize(width: 640, height: 800), safeAreaInsets: insets,
                showsVideoPreview: true, toolbarControlsBottom: 24
            )
            XCTAssertEqual(layout.sidebarWidth, 0)
            XCTAssertEqual(layout.videoFrame.minX, 0)
            XCTAssertEqual(layout.videoFrame.maxX, 640)
            XCTAssertEqual(layout.videoFrame.minY, 32)
            XCTAssertEqual(layout.contentFrame.minX, leading ? 0 : 16)
            XCTAssertEqual(layout.contentFrame.maxX, leading ? 624 : 640)
            XCTAssertEqual(layout.guideSideBleed, 0)
            XCTAssertEqual(layout.videoLeadingReflectionWidth, leading ? 96 : 0)
            XCTAssertEqual(layout.videoTrailingReflectionWidth, leading ? 0 : 96)
        }
    }

    func testPreviewSitsBelowToolbarAndLeavesRoomForTheGuide() {
        for size in [CGSize(width: 393, height: 700), CGSize(width: 852, height: 320),
                     CGSize(width: 834, height: 1000), CGSize(width: 1194, height: 700)] {
            let insets = EdgeInsets(top: 100, leading: 0, bottom: 34, trailing: 0)
            let collapsed = PrototypePreviewLayout(size: size, safeAreaInsets: insets)
            let playing = PrototypePreviewLayout(size: size, safeAreaInsets: insets, showsVideoPreview: true)
            XCTAssertEqual(collapsed.heroHeight, 0)
            XCTAssertEqual(playing.videoFrame.minY, playing.contentFrame.minY + 8)
            XCTAssertEqual(playing.videoFrame.maxX, playing.bounds.maxX)
            if playing.sidebarWidth > 0 {
                XCTAssertEqual(playing.videoFrame.minX,
                               playing.contentFrame.minX + playing.sidebarWidth
                                   + PrototypeLayout.sectionGap - playing.guideLeadingExtension)
            } else {
                XCTAssertEqual(playing.videoFrame.width, playing.bounds.width)
            }
            XCTAssertEqual(playing.contentFrame.minY + playing.heroHeight, playing.videoFrame.maxY)
            XCTAssertLessThanOrEqual(playing.videoFrame.height, playing.bounds.height * 0.48)
            XCTAssertGreaterThan(playing.heroHeight, 80)
            XCTAssertEqual(playing.guideWidth, collapsed.guideWidth)
            XCTAssertEqual(playing.contentFrame, collapsed.contentFrame)
            let searching = PrototypePreviewLayout(
                size: size, safeAreaInsets: insets, isSearching: true, showsVideoPreview: true)
            XCTAssertEqual(searching.heroHeight, 0)
            let measured = PrototypePreviewLayout(
                size: size, safeAreaInsets: insets, showsVideoPreview: true, toolbarControlsBottom: -14)
            XCTAssertEqual(measured.videoFrame.minY, -6, "Keep an 8 pt gap below the actual toolbar controls.")
            XCTAssertEqual(searching.videoReflectionHeight, 0)
            XCTAssertEqual(collapsed.videoReflectionHeight, 0)
            XCTAssertEqual(collapsed.videoTopReflectionHeight, 0)
            XCTAssertEqual(searching.videoTopReflectionHeight, 0)
            XCTAssertGreaterThan(playing.videoReflectionHeight, 0)
            XCTAssertEqual(playing.videoTopReflectionHeight,
                           min(playing.videoFrame.height, playing.videoFrame.minY - playing.bounds.minY))
            XCTAssertLessThanOrEqual(playing.videoReflectionHeight, playing.videoFrame.height)
        }
    }

    func testNativeVideoRetunePresentsFramesOnItsExistingSurface() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        let engine = NativeVideoEngine(startsMuted: true)
        let video = VideoPresentationView(frame: CGRect(x: 0, y: 100, width: 380, height: 214))
        host.view.addSubview(video)
        defer {
            engine.stop()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        let folder = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Fixtures", withExtension: nil))
        video.attach(engine)
        let surface = engine.makeVideoOutputView()
        for _ in 0..<2 {
            await engine.load(request: PlaybackRequest(
                item: MediaItem(id: "retune", title: "Synthetic video", kind: .movie),
                streamURL: folder.appendingPathComponent("live-continuity.mp4")
            ), startPosition: 0)
            video.attach(engine)
            try await settle(window)
            let deadline = ContinuousClock.now + .seconds(10)
            while !engine.hasPresentedVideoFrame, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(engine.hasPresentedVideoFrame)
            XCTAssertTrue(engine.makeVideoOutputView() === surface)
            video.updateReflection(height: 180, topHeight: 100)
            try await settle(window)
            video.updateReflection(height: 0, topHeight: 0)
        }
    }

    func testNativeVideoReflectionRetainsSurfaceAndPlayer() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.makeKeyAndVisible()
        let engine = NativeVideoEngine(startsMuted: true)
        let video = VideoPresentationView(frame: CGRect(
            x: 0, y: 100, width: window.bounds.width, height: window.bounds.width * 9 / 16))
        host.view.addSubview(video)
        video.attach(engine)
        defer {
            engine.stop()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        let folder = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Fixtures", withExtension: nil))
        await engine.load(request: PlaybackRequest(
            item: MediaItem(id: "reflection", title: "Synthetic video", kind: .movie),
            streamURL: folder.appendingPathComponent("live-continuity.mp4")
        ), startPosition: 0)
        let deadline = ContinuousClock.now + .seconds(10)
        while !engine.hasPresentedVideoFrame, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(engine.hasPresentedVideoFrame)
        engine.pause()
        try await settle(window)
        let player = try XCTUnwrap(engine.nowPlayingPlayer)
        let output = engine.makeVideoOutputView()
        let originalHost = try XCTUnwrap(output.superview)
        video.updateReflection(height: video.bounds.height)
        try await settle(window)
        XCTAssertTrue(engine.nowPlayingPlayer === player)
        XCTAssertTrue(engine.makeVideoOutputView() === output)
        XCTAssertTrue(output.isDescendant(of: video))
        XCTAssertFalse(video.clipsToBounds)
        let compositor = try XCTUnwrap(video.subviews.first)
        let fade = try XCTUnwrap(compositor.layer.mask as? CAGradientLayer)
        XCTAssertGreaterThan(fade.frame.height, video.bounds.height)
        XCTAssertEqual((fade.colors as? [CGColor])?.last?.alpha, 0,
                       "The reflection and blur must disappear into the actual guide background.")
        let colors = try XCTUnwrap(fade.colors as? [CGColor])
        let locations = try XCTUnwrap(fade.locations).map { CGFloat($0.doubleValue) }
        XCTAssertEqual(colors.count, locations.count)
        XCTAssertEqual(colors[1].alpha, 1, "Keep full intensity at the start of the reflection.")
        let samples: [(CGFloat, CGFloat)] = [(0.25, 0.6), (0.75, 0.1)]
        for (fraction, maximumAlpha) in samples {
            let position = (video.bounds.height + (fade.frame.height - video.bounds.height) * fraction)
                / fade.frame.height
            let upper = try XCTUnwrap(locations.firstIndex { $0 > position })
            let lower = upper - 1
            let progress = (position - locations[lower]) / (locations[upper] - locations[lower])
            let alpha = colors[lower].alpha + (colors[upper].alpha - colors[lower].alpha) * progress
            XCTAssertLessThan(alpha, maximumAlpha, "Fade early, leaving only a faint final quarter.")
        }
        XCTAssertTrue(compositor.subviews.contains { $0 is UIVisualEffectView },
                      "The same transparency mask must cover the blur, not only the video replica.")
        let originalFrame = output.convert(output.bounds, to: video)
        video.updateReflection(height: video.bounds.height, topHeight: 100)
        try await settle(window)
        let twoSidedFade = try XCTUnwrap(compositor.layer.mask as? CAGradientLayer)
        let twoSidedColors = try XCTUnwrap(twoSidedFade.colors as? [CGColor])
        XCTAssertEqual(twoSidedColors.first?.alpha, 0)
        XCTAssertEqual(twoSidedColors.last?.alpha, 0)
        XCTAssertEqual(compositor.frame.minY, -100)
        XCTAssertEqual(output.convert(output.bounds, to: video), originalFrame,
                       "Adding an upper reflection must not move or resize the original video.")
        XCTAssertTrue(output.superview === originalHost)
        XCTAssertEqual(compositor.subviews.filter { $0 is UIVisualEffectView && !$0.isHidden }.count, 1)
        video.frame.size = CGSize(width: 600, height: 200)
        video.updateReflection(height: 120, topHeight: 40, leftWidth: 60, rightWidth: 80, previewCornerRadius: 16)
        try await settle(window)
        XCTAssertEqual(compositor.frame, CGRect(x: -60, y: -40, width: 740, height: 360))
        XCTAssertTrue(output.superview === originalHost)
        XCTAssertTrue(engine.nowPlayingPlayer === player)
        let picture = try XCTUnwrap(video.videoRect)
        let roundedCrop = try XCTUnwrap(originalHost.layer.mask as? CAShapeLayer)
        let picturePath = try XCTUnwrap(roundedCrop.path)
        XCTAssertEqual(picturePath.boundingBoxOfPath, picture)
        XCTAssertFalse(picturePath.contains(CGPoint(x: picture.minX + 1, y: picture.minY + 1)))
        XCTAssertTrue(picturePath.contains(CGPoint(x: picture.midX, y: picture.midY)))
        let verticalFade = try XCTUnwrap(compositor.layer.mask as? CAGradientLayer)
        let sideFade = try XCTUnwrap(verticalFade.mask as? CAGradientLayer)
        let sideColors = try XCTUnwrap(sideFade.colors as? [CGColor])
        XCTAssertEqual(sideColors.first?.alpha, 0)
        XCTAssertEqual(sideColors.last?.alpha, 0)
        let blur = try XCTUnwrap(compositor.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        let blurMask = try XCTUnwrap(blur.layer.mask as? CAShapeLayer)
        XCTAssertEqual(blurMask.fillRule, .evenOdd)
        let center = video.convert(CGPoint(x: picture.midX, y: picture.midY), to: blur)
        XCTAssertFalse(try XCTUnwrap(blurMask.path).contains(center, using: .evenOdd),
                       "Keep the original video sharp; only its surroundings receive blur.")

        for light in [true, false] {
            let previousEffect = blur.effect
            video.updateReflection(
                height: 120, topHeight: 40, leftWidth: 60, rightWidth: 80,
                previewCornerRadius: 16, lightAppearance: light
            )
            try await settle(window)
            XCTAssertNotNil(blur.effect as? UIBlurEffect)
            XCTAssertFalse(blur.effect === previousEffect)
            XCTAssertEqual(blur.contentView.backgroundColor?.cgColor.alpha ?? 0, 0)
            let fadeColors = try XCTUnwrap(verticalFade.colors as? [CGColor])
            XCTAssertEqual(fadeColors[2].alpha, light ? 0.4 : 0.16, accuracy: 0.001,
                           "Light-page colors need a longer fade, not an extra white wash.")
            var replica = try XCTUnwrap(compositor.subviews.first)
            for _ in 0..<4 {
                let layer = try XCTUnwrap(replica.layer as? CAReplicatorLayer)
                XCTAssertEqual(layer.instanceAlphaOffset, light ? -0.3 : 0, accuracy: 0.001)
                replica = try XCTUnwrap(replica.subviews.first)
            }
            XCTAssertTrue(replica === originalHost)
            XCTAssertEqual(originalHost.alpha, 1, "Light mode must not wash out the playing picture.")
            XCTAssertTrue(output.superview === originalHost)
            XCTAssertTrue(engine.nowPlayingPlayer === player)
            XCTAssertEqual(video.videoRect, picture)
            XCTAssertEqual(try XCTUnwrap(blurMask.path).boundingBoxOfPath, blur.bounds)
        }

        video.updateReflection(height: 0, previewCornerRadius: 16)
        try await settle(window)
        XCTAssertTrue(blur.isHidden, "Reduce Transparency keeps the rounded picture without any reflection blur.")
        XCTAssertNil(compositor.layer.mask)
        XCTAssertNotNil(originalHost.layer.mask)
        video.updateReflection(height: 0)
        try await settle(window)
        XCTAssertTrue(output.superview === originalHost, "Fullscreen must not reparent the playing surface.")
        XCTAssertTrue(video.clipsToBounds)
        XCTAssertNil(compositor.layer.mask)
        XCTAssertNil(originalHost.layer.mask, "Fullscreen restores the unmasked native video surface.")
        XCTAssertTrue(engine.nowPlayingPlayer === player)
        for size in [CGSize(width: 874, height: 402), CGSize(width: 402, height: 874)] {
            video.frame.size = size
            try await settle(window)
            XCTAssertTrue(output.superview === originalHost)
            XCTAssertTrue(engine.nowPlayingPlayer === player)
            XCTAssertEqual(output.bounds.size, size)
        }
    }

    func testSidebarRemainsInteractiveBesidePreviewInBothLayoutDirections() {
        let bounds = CGRect(x: 0, y: 0, width: 1_024, height: 768)
        for trailing in [false, true] {
            let path = PrototypeGuideHitRegion(top: 300, sidebarWidth: 240, sidebarOnTrailing: trailing)
                .path(in: bounds)
            XCTAssertTrue(path.contains(CGPoint(x: trailing ? 900 : 100, y: 100)))
            XCTAssertFalse(path.contains(CGPoint(x: 500, y: 100)), "Preview taps must reach player controls.")
            XCTAssertTrue(path.contains(CGPoint(x: 500, y: 500)))
        }
    }

    func testOpeningPreviewResizesExistingGuideWithoutChangingScrollOffset() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let state = PreviewState()
        let host = UIHostingController(rootView: PreviewGuideFixture(state: state))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        for size in [CGSize(width: 393, height: 700), CGSize(width: 834, height: 700)] {
            state.showsPreview = false
            window.frame = CGRect(origin: .zero, size: size)
            host.view.frame = window.bounds
            try await settle(window)
            let scrolling = scrollViews(window).filter {
                $0.contentSize.height > $0.bounds.height + 400
            }
            let scroll = try XCTUnwrap(scrolling.max { $0.bounds.width < $1.bounds.width })
            let sidebar = scrolling.first { $0 !== scroll }
            if size.width > 700 { XCTAssertNotNil(sidebar) }
            sidebar?.setContentOffset(CGPoint(x: 0, y: 91), animated: false)
            scroll.setContentOffset(CGPoint(x: 0, y: 367), animated: false)
            try await settle(window)
            let offset = scroll.contentOffset
            let before = scroll.convert(scroll.bounds, to: window)
            let sidebarFrame = sidebar.map { $0.convert($0.bounds, to: window) }
            state.showsPreview = true
            try await settle(window)
            XCTAssertTrue(scrollViews(window).contains { $0 === scroll }, "Keep the original guide scroll view.")
            XCTAssertEqual(scroll.contentOffset.y, offset.y, accuracy: 1, "Keep partial-row position, not just a row ID.")
            let after = scroll.convert(scroll.bounds, to: window)
            XCTAssertGreaterThan(after.minY, before.minY + 100)
            XCTAssertEqual(after.maxY, before.maxY, accuracy: 1)
            XCTAssertEqual(after.width, before.width, accuracy: 1)
            if let sidebar {
                XCTAssertTrue(scrollViews(window).contains { $0 === sidebar })
                XCTAssertEqual(sidebar.convert(sidebar.bounds, to: window), sidebarFrame)
                XCTAssertEqual(sidebar.contentOffset.y, 91, accuracy: 1)
            }
            state.showsPreview = false
            try await settle(window)
            XCTAssertEqual(scroll.contentOffset.y, offset.y, accuracy: 1)
        }
    }

    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        window.layoutIfNeeded()
    }

    private func scrollViews(_ view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }
}

@MainActor @Observable
private final class PreviewState {
    var showsPreview = false
}

private struct PreviewGuideFixture: View {
    let state: PreviewState
    @State private var model = LiveTVPrototypeModel()
    @State private var imports = LiveTVPrototypeImportModel(configuration: .empty)
    @State private var selectedID: String?
    @State private var selectedRowID: LiveTVGuideRowID?
    @State private var active = false
    @State private var focusedProgram: LiveTVPrototypeProgram?
    @State private var hasFocus = false
    @State private var offset: TimeInterval = 0
    @State private var time = Date()
    @State private var timeline: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let layout = PrototypePreviewLayout(size: geometry.size, showsVideoPreview: state.showsPreview)
            PrototypeGuidePlacement(frame: layout.contentFrame, canvasWidth: geometry.size.width) {
                PrototypeBrowseLayout(layout: layout) {
                    Color.clear.frame(height: layout.heroHeight).allowsHitTesting(false)
                } sidebar: {
                    ScrollView {
                        LazyVStack {
                            ForEach(0..<50) { index in
                                Text("Category \(index)").frame(height: 44)
                            }
                        }
                    }
                } guide: {
                    PrototypeBrowser(
                        model: model, imports: imports, selectedID: $selectedID, selectedRowID: $selectedRowID,
                        railActive: $active, focusedProgram: $focusedProgram, hasFocus: $hasFocus,
                        topRequest: 0, nowRequest: 0, guideOffset: $offset, timeAnchor: $time,
                        timelineOffset: $timeline, restoreFocusRequest: 0, isPresented: true,
                        isRestoringFocus: false, restoresPlaybackFocus: false, watchOrigin: nil,
                        focusRestored: { _ in }, tune: { _ in }, details: { _ in },
                        openControls: {}, openSources: {}, openGuideTime: {}, openToolbar: nil,
                        isLoading: false, loadFailed: false, reload: {}
                    )
                }
            }
        }
    }
}
#endif
