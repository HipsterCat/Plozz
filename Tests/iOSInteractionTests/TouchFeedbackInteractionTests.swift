import UIKit
import XCTest

@MainActor
final class TouchFeedbackInteractionTests: XCTestCase {
    func testHeroWatchlistAcknowledgesImmediatelyAndOnlyFailureAddsFeedback() {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--watchlist-feedback-fixture"]
        app.launch()
        defer { app.terminate() }
        let add = app.buttons["Add to Watchlist"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertEqual(app.staticTexts["watchlist-taps"].label, "Taps 1")
        XCTAssertEqual(app.staticTexts["watchlist-confirmations"].label, "Confirmations 0")
        let errors = app.staticTexts["watchlist-errors"]
        XCTAssertEqual(errors.label, "Errors 0")
        let complete = app.buttons["Complete save"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        complete.tap()
        let confirmed = app.staticTexts["watchlist-confirmations"]
        let success = expectation(
            for: NSPredicate(format: "label == %@", "Saved yes"),
            evaluatedWith: app.staticTexts["watchlist-saved"]
        )
        wait(for: [success], timeout: 5)
        XCTAssertEqual(confirmed.label, "Confirmations 0")
        XCTAssertEqual(errors.label, "Errors 0")
        XCTAssertEqual(app.staticTexts["watchlist-taps"].label, "Taps 1")

        app.buttons["Remove from Watchlist"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["watchlist-taps"].label, "Taps 2")
        let fail = app.buttons["Fail save"]
        XCTAssertTrue(fail.waitForExistence(timeout: 10))
        fail.tap()
        let failure = expectation(for: NSPredicate(format: "label == %@", "Errors 1"), evaluatedWith: errors)
        wait(for: [failure], timeout: 5)
        XCTAssertTrue(app.buttons["Remove from Watchlist"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(confirmed.label, "Confirmations 0", "Failure must not emit a success haptic")
        XCTAssertEqual(app.staticTexts["watchlist-taps"].label, "Taps 2")
    }

    func testScrubGivesOneTickPerCommitAndPlaybackUpdatesStaySilent() throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--touch-feedback-fixture"]
        app.launch()
        defer { app.terminate() }
        let scrubber = app.otherElements["touch-scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let end = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 1")
        XCTAssertEqual(app.staticTexts["commit-count"].label, "Commits 1")
        let previews = try XCTUnwrap(Int(app.staticTexts["preview-count"].label.split(separator: " ").last ?? ""))
        XCTAssertGreaterThan(previews, 2, "The drag must cover multiple previews, not just a tap")
        app.buttons["Playback tick"].tap()
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 1")
        end.press(forDuration: 0.1, thenDragTo: start)
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 2")
        app.buttons["Unknown duration"].tap()
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 2")
    }

    func testPortraitSegmentedScrubDragsAcrossSuppressedCutsAndCommitsExactPosition() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native Liquid Glass requires iOS 26.") }
        try XCTSkipIf(UIAccessibility.isReduceTransparencyEnabled, "Native glass needs Reduce Transparency off.")
        let previousOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--touch-feedback-fixture", "--segmented-touch-feedback"]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = previousOrientation
        }
        let scrubber = app.otherElements["touch-scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 10))
        XCTAssertTrue(scrubber.isHittable)
        XCTAssertEqual(scrubber.label, "Playback position")
        let frame = scrubber.frame
        XCTAssertEqual(frame.width, 240, accuracy: 1)
        XCTAssertEqual(frame.height, 44, accuracy: 1)
        attachScrub(app, name: "Native portrait markers before dragging")

        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let end = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(app.staticTexts["commit-count"].label, "Commits 1")
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 1")
        XCTAssertEqual(app.staticTexts["scrubbing-active"].label, "no")
        XCTAssertEqual(try number(app, "committed-position"), 210, accuracy: 1.5)
        XCTAssertLessThan(try number(app, "gesture-minimum"), 75)
        XCTAssertGreaterThan(try number(app, "gesture-maximum"), 174.375)
        XCTAssertGreaterThan(try XCTUnwrap(Int(app.staticTexts["preview-count"].label.split(separator: " ").last ?? "")), 2)
        XCTAssertEqual(scrubber.frame, frame, "Dragging must preserve the timeline's hit area.")
        attachScrub(app, name: "Native portrait markers after forward commit")

        let insideTinyMarker = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.27, dy: 0.5))
        end.press(forDuration: 0.1, thenDragTo: insideTinyMarker)
        XCTAssertEqual(app.staticTexts["commit-count"].label, "Commits 2")
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 2")
        XCTAssertEqual(try number(app, "committed-position"), 81, accuracy: 1.5,
                       "A suppressed visual marker must not snap seeking to either of its endpoints.")
        XCTAssertEqual(app.staticTexts["scrubbing-active"].label, "no")
        attachScrub(app, name: "Native portrait commit inside suppressed marker")
        app.buttons["Playback tick"].tap()
        XCTAssertEqual(app.staticTexts["commit-count"].label, "Commits 2")
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 2")

        let rightEdge = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
        insideTinyMarker.press(forDuration: 0.1, thenDragTo: rightEdge)
        XCTAssertEqual(try number(app, "committed-position"), 300, accuracy: 1.5)
        XCTAssertEqual(app.staticTexts["commit-count"].label, "Commits 3")
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 3")
        attachScrub(app, name: "Native portrait fill at 100 percent without a playhead")

        let leftEdge = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
        end.press(forDuration: 0.1, thenDragTo: leftEdge)
        XCTAssertEqual(try number(app, "committed-position"), 0, accuracy: 1.5)
        XCTAssertEqual(app.staticTexts["commit-count"].label, "Commits 4")
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 4")
        XCTAssertEqual(app.staticTexts["scrubbing-active"].label, "no")
        XCTAssertEqual(scrubber.frame, frame)
        attachScrub(app, name: "Native portrait fill at zero without a playhead")
    }

    private func number(_ app: XCUIApplication, _ identifier: String) throws -> Double {
        try XCTUnwrap(Double(app.staticTexts[identifier].label), identifier)
    }

    private func attachScrub(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
