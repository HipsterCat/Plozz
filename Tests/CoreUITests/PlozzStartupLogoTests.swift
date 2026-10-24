#if canImport(SwiftUI)
import SwiftUI
import XCTest
@testable import PlozzCoreUI

@MainActor
final class PlozzStartupLogoTests: XCTestCase {
    private var timeline: KeyframeTimeline<PlozzStartupLogoMotion.Pose> {
        KeyframeTimeline(initialValue: .rest) {
            PlozzStartupLogoMotion.keyframes
        }
    }

    func testLoopReturnsToTheSameFaceAndOrientation() {
        XCTAssertEqual(timeline.duration, 8, accuracy: 0.0001)
        let start = timeline.value(time: 0)
        let end = timeline.value(time: timeline.duration)
        XCTAssertEqual(start, .rest)
        XCTAssertEqual(end.primaryOpacity, start.primaryOpacity)
        XCTAssertEqual(end.secondaryOpacity, start.secondaryOpacity)
        XCTAssertEqual(end.tilt, start.tilt)
        XCTAssertEqual(end.turn.truncatingRemainder(dividingBy: 360), start.turn)
    }

    func testExpressionsHaveQuietHoldsBeforeAndAfterTheTurn() {
        XCTAssertEqual(timeline.value(time: 0.1), .rest)
        XCTAssertEqual(timeline.value(time: 0.5).primaryOpacity, 1)
        XCTAssertEqual(timeline.value(time: 1.3).primaryOpacity, 0)
        XCTAssertEqual(timeline.value(time: 2.5).secondaryOpacity, 1)
        XCTAssertEqual(timeline.value(time: 2.5).turn, 0)
        XCTAssertEqual(timeline.value(time: 5).secondaryOpacity, 1)
        XCTAssertEqual(timeline.value(time: 5).turn, 360)
        XCTAssertEqual(timeline.value(time: 7).secondaryOpacity, 0)
    }

    func testFirstExpressionStartsAtQuarterSecondAndIsVisibleBeforeIntroCompletes() {
        XCTAssertEqual(timeline.value(time: 0.25).primaryOpacity, 0)
        XCTAssertGreaterThan(timeline.value(time: 0.3).primaryOpacity, 0)
        XCTAssertEqual(timeline.value(time: 0.4).primaryOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(timeline.value(time: 0.699).introCompleted, 0)
        XCTAssertEqual(timeline.value(time: 0.701).introCompleted, 1)
        XCTAssertEqual(timeline.value(time: 0.7).primaryOpacity, 1)
        XCTAssertEqual(PlozzStartupLogoMotion.minimumDisplayDuration, 0.7)
    }

    func testMotionStaysBoundedWithoutOpacityOvershoot() {
        for tick in 0...480 {
            let pose = timeline.value(time: Double(tick) / 60)
            XCTAssertTrue((0...1).contains(pose.primaryOpacity))
            XCTAssertTrue((0...1).contains(pose.secondaryOpacity))
            XCTAssertTrue((-6.0001...0.0001).contains(pose.tilt))
            XCTAssertTrue((-12.0001...360.0001).contains(pose.turn))
        }
    }

    func testReduceMotionAndInactiveScenesDoNotAnimate() {
        for phase in [ScenePhase.active, .inactive, .background] {
            XCTAssertFalse(PlozzStartupLogoMotion.shouldAnimate(reduceMotion: true, scenePhase: phase))
        }
        XCTAssertFalse(PlozzStartupLogoMotion.shouldAnimate(reduceMotion: false, scenePhase: .inactive))
        XCTAssertFalse(PlozzStartupLogoMotion.shouldAnimate(reduceMotion: false, scenePhase: .background))
        XCTAssertTrue(PlozzStartupLogoMotion.shouldAnimate(reduceMotion: false, scenePhase: .active))
    }

    func testLaunchesRotateThroughEveryExpressionAndPersistTheChoice() throws {
        let suite = "PlozzStartupLogoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let expected: [PlozzStartupExpression] = [.wink, .delight, .surprise, .wink, .delight, .surprise]
        for expression in expected {
            let restoredDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            XCTAssertEqual(PlozzStartupExpression.nextLaunch(defaults: restoredDefaults), expression)
        }
    }

    func testCurrentLaunchKeepsTheSameExpressionAcrossReads() {
        let expression = PlozzStartupExpression.currentLaunch
        for _ in 0..<10 {
            XCTAssertEqual(PlozzStartupExpression.currentLaunch, expression)
        }
    }

    #if canImport(UIKit)
    func testOriginalFacesRenderAtPixelAlignedSizes() throws {
        var renderedImages: Set<Data> = []
        for (name, pose, expression) in [
            ("smile", PlozzStartupLogoMotion.Pose.rest, PlozzStartupExpression.wink),
            ("wink", .init(primaryOpacity: 1), .wink),
            ("delight", .init(primaryOpacity: 1), .delight),
            ("surprise", .init(primaryOpacity: 1), .surprise)
        ] {
            let renderer = ImageRenderer(
                content: PlozzStartupLogoArtwork(pose: pose, expression: expression)
                    .frame(width: 192, height: 192)
            )
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage, name)
            XCTAssertEqual(image.size.width, 192)
            XCTAssertEqual(image.size.height, 192)
            let data = try XCTUnwrap(image.pngData())
            XCTAssertTrue(renderedImages.insert(data).inserted, "Each expression must render different artwork")
            let attachment = XCTAttachment(image: image)
            attachment.name = "Startup logo — \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testEveryExpressionStartsFromTheSameSmile() throws {
        var smile: Data?
        for expression in PlozzStartupExpression.allCases {
            let renderer = ImageRenderer(
                content: PlozzStartupLogoArtwork(pose: .rest, expression: expression)
                    .frame(width: 192, height: 192)
            )
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage?.pngData())
            if let smile { XCTAssertEqual(image, smile) }
            smile = image
        }
    }
    #endif
}
#endif
