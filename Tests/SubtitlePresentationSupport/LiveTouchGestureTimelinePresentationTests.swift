#if os(iOS)
import CoreModels
import CoreUI
import EnginePlozzigen
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class LiveTouchGestureTimelinePresentationTests: XCTestCase {
    func testGestureKeepsTheExistingLiveTimelineInPlaceAndHidesOtherChrome() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let input = LiveChannelInput.stream(
            url: try XCTUnwrap(URL(string: "https://fixture.invalid/live.m3u8")), httpHeaders: [:]
        )
        let tracks = LiveChannelPlayerModel(engine: try PlozzigenVideoEngine(), input: input)
        let state = TimelineFixtureState()
        let host = UIHostingController(rootView: TimelineFixture(input: input, tracks: tracks, state: state))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            tracks.stop()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        window.layoutIfNeeded()
        let layout = tracks.subtitles.controlsLayout
        try await waitUntil { layout.frame(for: .timeline) != nil && layout.frame(for: .title) != nil }
        // The window-safe-area reader settles after the first presented frame.
        _ = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        try await Task.sleep(for: .milliseconds(200))
        window.layoutIfNeeded()
        let original = try XCTUnwrap(layout.frame(for: .timeline))
        XCTAssertGreaterThan(original.width, 100)
        XCTAssertGreaterThan(original.height, 12, "Retain the actual live timeline and its labels.")
        state.timelineOnly = true
        try await waitUntil { layout.frame(for: .title) == nil && layout.frame(for: .trackControls) == nil }
        let duringGesture = try XCTUnwrap(layout.frame(for: .timeline))
        XCTAssertEqual(duringGesture, original, "Do not substitute or reposition the live timeline.")
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Live gesture retains original timeline"
        attachment.lifetime = .keepAlways
        add(attachment)
        state.timelineOnly = false
        try await waitUntil { layout.frame(for: .title) != nil }
        XCTAssertEqual(layout.frame(for: .timeline), original)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Live timeline did not settle into the expected presentation.")
    }
}

@MainActor @Observable
private final class TimelineFixtureState {
    var timelineOnly = false
}

private struct TimelineFixture: View {
    let input: LiveChannelInput
    let tracks: LiveChannelPlayerModel
    let state: TimelineFixtureState
    private let now = Date()
    @FocusState private var focus: LiveChannelControl?

    var body: some View {
        LiveChannelOverlay(
            title: "Sample Channel", logoURL: nil, plozzChannelID: nil, channelID: "sample",
            input: input,
            program: .init(title: "News", start: now.addingTimeInterval(-900), end: now.addingTimeInterval(900)),
            earlierPrograms: [], libraryItem: nil, openLibraryItem: nil, phase: .playing,
            isAtLiveEdge: false, behindLiveSeconds: 120, canPause: true, canGoLive: true,
            seekWindowSeconds: 600, onSeekBy: { _ in }, onSeekBehindLive: { _ in },
            focus: $focus, onClose: {}, onPrevious: {}, onPlayPause: {}, onGoLive: {}, onNext: {},
            onMultiview: nil, guideContent: nil, pendingGuideOpen: false, consumeGuideOpen: {},
            onGuideCardChange: { _ in }, loadOnNow: { [] }, onTuneChannel: nil,
            tracks: tracks, diagnosticsEnabled: false, toggleDiagnostics: {},
            onTracksPresentationChange: { _ in }, onControlActivity: {}, onDismissControls: {},
            hasTouchGestureSurface: true, touchTimelineOnly: state.timelineOnly
        )
        .background(.black)
        .environment(\.plozzMetrics, .touch(density: .standard))
        .environment(\.themePalette, .dark)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "en_US"))
        .ignoresSafeArea()
    }
}
#endif
