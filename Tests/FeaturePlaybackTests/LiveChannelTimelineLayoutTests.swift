#if DEBUG
import CoreModels
import XCTest
#if os(tvOS)
import UIKit
#endif

@testable import FeaturePlayback

final class LiveChannelTimelineLayoutTests: XCTestCase {
    private let ten = Date(timeIntervalSince1970: 36_000)

    private func program(_ startHour: Double, _ endHour: Double) -> LiveChannelProgramInfo {
        LiveChannelProgramInfo(
            title: "P", start: Date(timeIntervalSince1970: startHour * 3_600),
            end: Date(timeIntervalSince1970: endHour * 3_600)
        )
    }

    func testWithoutAWindowTheBarMeasuresTheProgramme() {
        let layout = LiveChannelTimelineLayout(
            now: ten.addingTimeInterval(1_800), program: program(10, 11),
            seekWindowSeconds: nil, behindLiveSeconds: 0
        )
        XCTAssertEqual(layout.start, ten)
        XCTAssertEqual(layout.boundaries, [])
        XCTAssertNil(layout.seekableStart)
        XCTAssertEqual(layout.aired, 0.5, accuracy: 0.0001)
        XCTAssertEqual(layout.playing, 0.5, accuracy: 0.0001)
    }

    func testWindowReachesBackIntoEarlierProgrammes() {
        let layout = LiveChannelTimelineLayout(
            now: ten.addingTimeInterval(1_800), program: program(10, 11),
            earlierPrograms: [program(8, 9), program(9, 10)],
            seekWindowSeconds: 7_200, behindLiveSeconds: 1_800
        )
        // 08:00–11:00, split at 09:00 and 10:00, seekable from 08:30.
        XCTAssertEqual(layout.start, Date(timeIntervalSince1970: 8 * 3_600))
        XCTAssertEqual(layout.boundaries.count, 2)
        XCTAssertEqual(layout.boundaries[0], 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(layout.boundaries[1], 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(layout.seekableStart), 1.0 / 6, accuracy: 0.0001)
        XCTAssertEqual(layout.aired, 2.5 / 3, accuracy: 0.0001)
        XCTAssertEqual(layout.playing, 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(layout.maskRanges.count, 1)
    }

    func testWindowPastTheGuideRunsOnToTheWindowStart() {
        let layout = LiveChannelTimelineLayout(
            now: ten.addingTimeInterval(1_800), program: program(10, 11),
            seekWindowSeconds: 7_200, behindLiveSeconds: 0
        )
        XCTAssertEqual(layout.start, ten.addingTimeInterval(-5_400))
        XCTAssertEqual(layout.boundaries.count, 1)
        XCTAssertEqual(try XCTUnwrap(layout.seekableStart), 0, accuracy: 0.0001)
    }

    func testVeryDeepWindowIsCappedToTheLookback() {
        let now = ten.addingTimeInterval(1_800)
        let layout = LiveChannelTimelineLayout(
            now: now, program: program(10, 11),
            seekWindowSeconds: 24 * 3_600, behindLiveSeconds: 0
        )
        XCTAssertEqual(layout.start, now.addingTimeInterval(-LiveChannelTimelineLayout.maximumLookback))
    }

    func testWindowWithoutGuideFillsToTheEdge() {
        let layout = LiveChannelTimelineLayout(
            now: ten, program: nil, seekWindowSeconds: 600, behindLiveSeconds: 150
        )
        XCTAssertEqual(layout.start, ten.addingTimeInterval(-600))
        XCTAssertEqual(layout.aired, 1)
        XCTAssertEqual(layout.playing, 0.75, accuracy: 0.0001)
    }
}
#endif

#if DEBUG
final class LiveChannelTimelineScrubTests: XCTestCase {
    #if os(tvOS)
    @MainActor
    func testRemotePanCannotBeginWhenTheTimelineIsInactive() {
        let view = LiveChannelTimelineScrubPan.ObserverView()
        let pan = UIPanGestureRecognizer()
        XCTAssertFalse(view.gestureRecognizerShouldBegin(pan))
        view.isEnabled = true
        XCTAssertTrue(view.gestureRecognizerShouldBegin(pan))
        view.isEnabled = false
        XCTAssertFalse(view.gestureRecognizerShouldBegin(pan))
    }
    #endif
    func testHorizontalSwipePreviewsAndCommitsOnLift() throws {
        var scrub = LiveChannelTimelineScrub()
        scrub.begin(behindLive: 0)
        // Below the axis lock: nothing previews yet.
        scrub.change(translationX: -10, translationY: 0, speed: 100, windowSeconds: 3_600)
        XCTAssertNil(scrub.behindLive)
        // Left swipe: back into the window.
        scrub.change(translationX: -40, translationY: 2, speed: 100, windowSeconds: 3_600)
        scrub.change(translationX: -240, translationY: 4, speed: 100, windowSeconds: 3_600)
        let preview = try XCTUnwrap(scrub.behindLive)
        XCTAssertGreaterThan(preview, 0)
        XCTAssertEqual(scrub.end(), preview)
        XCTAssertNil(scrub.behindLive)
    }

    func testVerticalSwipeNeverScrubs() {
        var scrub = LiveChannelTimelineScrub()
        scrub.begin(behindLive: 30)
        scrub.change(translationX: 5, translationY: 60, speed: 100, windowSeconds: 3_600)
        scrub.change(translationX: 200, translationY: 80, speed: 100, windowSeconds: 3_600)
        XCTAssertNil(scrub.behindLive)
        XCTAssertNil(scrub.end())
    }

    func testScrubStaysInsideTheWindow() throws {
        var scrub = LiveChannelTimelineScrub()
        scrub.begin(behindLive: 50)
        scrub.change(translationX: -30, translationY: 0, speed: 5_000, windowSeconds: 60)
        scrub.change(translationX: -3_000, translationY: 0, speed: 5_000, windowSeconds: 60)
        XCTAssertEqual(try XCTUnwrap(scrub.behindLive), 60)
        scrub.change(translationX: 6_000, translationY: 0, speed: 5_000, windowSeconds: 60)
        XCTAssertEqual(try XCTUnwrap(scrub.behindLive), 0)
    }
}
#endif
