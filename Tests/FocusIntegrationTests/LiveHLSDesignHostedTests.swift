import CoreModels
import CoreUI
import EnginePlozzigen
import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class LiveHLSDesignHostedTests: XCTestCase {
    func testLiveWindowAndDiagnosticsRemainVisible() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        window.makeKeyAndVisible()
        let input = LiveChannelInput.stream(url: try XCTUnwrap(URL(string: "https://fixture.invalid/live.m3u8")), httpHeaders: [:])
        let tracks = LiveChannelPlayerModel(engine: try PlozzigenVideoEngine(), input: input)
        defer {
            tracks.stop()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        for showsDiagnostics in [false, true] {
            host.rootView = AnyView(
                LiveHLSDesignFixture(input: input, tracks: tracks, showsDiagnostics: showsDiagnostics)
                    .environment(\.playerCardMetrics, .tv)
                    .environment(\.themePalette, .dark)
                    .environment(\.colorScheme, .dark)
                    .environment(\.locale, Locale(identifier: "en_US"))
                    .transaction { $0.disablesAnimations = true }
            )
            window.layoutIfNeeded()
            window.setNeedsFocusUpdate()
            window.updateFocusIfNeeded()
            let deadline = ContinuousClock.now + .seconds(3)
            while UIFocusSystem.focusSystem(for: window)?.focusedItem == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertNotNil(UIFocusSystem.focusSystem(for: window)?.focusedItem)
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = showsDiagnostics ? "live-hls-playback-info" : "live-hls-rewind-timeline"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

private struct LiveHLSDesignFixture: View {
    let input: LiveChannelInput
    let tracks: LiveChannelPlayerModel
    let showsDiagnostics: Bool
    private let now = Date()
    @FocusState private var focus: LiveChannelControl?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.08)
            LiveChannelOverlay(
                title: "Sample Channel", logoURL: nil, plozzChannelID: nil, channelID: "sample",
                input: input,
                program: .init(title: "Evening News", start: now.addingTimeInterval(-900), end: now.addingTimeInterval(900)),
                earlierPrograms: [
                    .init(title: "World Report", start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800)),
                    .init(title: "Weather", start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(-900))
                ],
                libraryItem: nil, openLibraryItem: nil, phase: .playing,
                isAtLiveEdge: false, behindLiveSeconds: 1200, canPause: true, canGoLive: true,
                seekWindowSeconds: 3600, onSeekBy: { _ in }, onSeekBehindLive: { _ in },
                focus: $focus, onClose: {}, onPrevious: {}, onPlayPause: {}, onGoLive: {}, onNext: {},
                onMultiview: {}, guideContent: nil, pendingGuideOpen: false, consumeGuideOpen: {},
                onGuideCardChange: { _ in }, loadOnNow: { [] }, onTuneChannel: nil,
                tracks: tracks, diagnosticsEnabled: showsDiagnostics, toggleDiagnostics: {},
                onTracksPresentationChange: { _ in }, onControlActivity: {}, onDismissControls: {}
            )
            if showsDiagnostics {
                PlaybackDiagnosticsOverlay(diagnostics: diagnostics)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .onAppear { focus = .timeline }
    }

    private var diagnostics: PlaybackDiagnostics {
        var result = PlaybackDiagnostics()
        result.mode = .directPlay
        result.engineName = "AetherEngine v7.44.0"
        result.sourceProvider = .iptv
        result.serverName = "Sample IPTV"
        result.resolution = .init(width: 1920, height: 1080)
        result.videoCodec = "H.264"
        result.frameRate = 25
        result.audioCodec = "AAC"
        result.audioChannels = 2
        result.liveStream = .init(
            route: "Native HLS (AVPlayer)", playlistType: "LIVE",
            behindLiveSeconds: 1200, windowSeconds: 3600, programDate: now.addingTimeInterval(-1200),
            startupSeconds: 1.2, tuneToFirstFrameSeconds: 1.8,
            variantSwitches: 1, segmentRequests: 42, bytesTransferred: 32_000_000, overdueSegments: 0
        )
        result.liveStream?.variantWidth = 1920
        result.liveStream?.variantHeight = 1080
        result.liveStream?.variantBitrate = 5_000_000
        return result
    }
}
