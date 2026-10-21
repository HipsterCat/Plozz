import XCTest

@MainActor
final class PlayerUpNextInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = [
            "--rotation-player-fixture", "--gesture-player-fixture",
            "--keyboard-up-next-fixture", "--auto"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Open rotation player"].waitForExistence(timeout: 10))
        app.buttons["Open rotation player"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 25), app.debugDescription)
        if !app.buttons["Pause"].exists { backgroundPoint.tap() }
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "0.0", timeout: 3))
    }

    override func tearDown() async throws {
        if testRun?.failureCount ?? 0 > 0 { capture("up-next-failure") }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        app = nil
        try await super.tearDown()
    }

    func testCardStaysAboveTransportInLandscapeAndPortrait() {
        assertCardClearsTransport()
        XCTAssertFalse(card.buttons["Play"].exists, "The episode card replaces the separate Play button.")
        XCTAssertTrue(app.buttons["player-up-next"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["Dismiss Up Next"].frame.height + 0.000_001, 44)
        capture("up-next-landscape")

        XCUIDevice.shared.orientation = .portrait
        let portrait = NSPredicate { [self] _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.height > frame.width
        }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: portrait, evaluatedWith: app)], timeout: 5), .completed)
        assertCardClearsTransport()
        capture("up-next-portrait")
    }

    func testCardAnchorSurvivesHiddenControlsAndDismissDoesNotAdvance() {
        assertCardClearsTransport()
        let initialFrame = card.frame
        backgroundPoint.tap()
        XCTAssertTrue(app.otherElements["player-timeline"].waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Subtitles"].isHittable)
        XCTAssertTrue(card.exists)
        XCTAssertEqual(card.frame.minY, initialFrame.minY, accuracy: 1)
        XCTAssertEqual(card.frame.maxY, initialFrame.maxY, accuracy: 1)
        capture("up-next-controls-hidden")

        backgroundPoint.tap()
        XCTAssertTrue(app.otherElements["player-timeline"].waitForExistence(timeout: 3))
        assertCardClearsTransport()
        XCTAssertEqual(card.frame.maxY, initialFrame.maxY, accuracy: 1)
        app.buttons["Dismiss Up Next"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Keyboard episode 1"))
            .firstMatch.exists, "Resolving the next episode for prefetch must not be mistaken for advancing.")
        XCTAssertEqual(app.staticTexts["gesture-rate"].label, "0.0")
    }

    func testTappingEpisodeCardAdvancesWithoutASeparatePlayButton() {
        app.buttons["player-up-next"].tap()
        XCTAssertTrue(app.staticTexts["rotation-load-count"].wait(for: \.label, toEqual: "Loads 2", timeout: 10))
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "1.0", timeout: 10))
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pause"].waitForNonExistence(timeout: 8))
        backgroundPoint.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Keyboard episode 2"))
            .firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    func testCardFitsPortraitAtAccessibilityTextSize() {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments.append("--large-player-text")
        app.launch()
        XCTAssertTrue(app.buttons["Open rotation player"].waitForExistence(timeout: 10))
        app.buttons["Open rotation player"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 25))
        if !app.buttons["Pause"].exists { backgroundPoint.tap() }
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "0.0", timeout: 3))
        assertCardClearsTransport()
        XCTAssertTrue(app.buttons["player-up-next"].isHittable)
        XCTAssertTrue(app.buttons["Dismiss Up Next"].isHittable)
        capture("up-next-accessibility-portrait")
    }

    func testWrappedTitleKeepsTheCardBetweenPlaybackControlsAndTimeline() {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments.append("--long-up-next-title")
        app.launch()
        XCTAssertTrue(app.buttons["Open rotation player"].waitForExistence(timeout: 10))
        app.buttons["Open rotation player"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 25))
        if !app.buttons["Pause"].exists { backgroundPoint.tap() }
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "0.0", timeout: 3))
        assertCardClearsTransport()
        XCTAssertTrue(app.buttons["player-up-next"].isHittable)
        XCTAssertTrue(app.buttons["Dismiss Up Next"].isHittable)
        capture("up-next-wrapped-title")
    }

    private var card: XCUIElement { app.otherElements["player-up-next-card"] }

    private var backgroundPoint: XCUICoordinate {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.3))
    }

    private func assertCardClearsTransport(file: StaticString = #filePath, line: UInt = #line) {
        let trackControls = app.buttons["Subtitles"]
        let playPause = app.buttons["Play"]
        let settled = NSPredicate { [self] _, _ in
            guard card.exists, trackControls.exists, playPause.exists,
                  app.otherElements["player-timeline"].exists else { return false }
            return card.frame.maxY + 12 <= trackControls.frame.minY
                && playPause.frame.maxY + 12 <= card.frame.minY
                && !card.frame.intersects(app.otherElements["player-timeline"].frame)
                && app.windows.firstMatch.frame.contains(card.frame)
        }
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation(for: settled, evaluatedWith: app)], timeout: 5),
            .completed, file: file, line: line
        )
        XCTAssertTrue(trackControls.exists, file: file, line: line)
        XCTAssertLessThanOrEqual(playPause.frame.maxY + 12, card.frame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(card.frame.maxY + 12, trackControls.frame.minY, file: file, line: line)
        XCTAssertFalse(card.frame.intersects(app.otherElements["player-timeline"].frame), file: file, line: line)
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(card.frame), "Up Next must fit inside the player.", file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
