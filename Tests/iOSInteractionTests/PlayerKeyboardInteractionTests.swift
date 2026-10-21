import XCTest

@MainActor
final class PlayerKeyboardInteractionTests: XCTestCase {
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
        XCTAssertTrue(app.buttons["Dismiss Up Next"].waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "1.0", timeout: 5))
    }

    override func tearDown() async throws {
        if testRun?.failureCount ?? 0 > 0 {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "Keyboard playback failure"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        app = nil
        try await super.tearDown()
    }

    func testSpacePausesAndResumesWhileUpNextIsVisibleAndAfterDismissal() {
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "0.0", timeout: 3),
                      "Space must pause the actual renderer, not activate Up Next. \(app.debugDescription)")
        XCTAssertTrue(app.buttons["Dismiss Up Next"].exists)
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "1.0", timeout: 3))
        app.buttons["Dismiss Up Next"].tap()
        XCTAssertFalse(app.buttons["Dismiss Up Next"].exists)
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "0.0", timeout: 3))
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "1.0", timeout: 3))
    }

    func testArrowsUseConfiguredIntervalsAndRenderCumulativeFeedbackWithUpNext() {
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        let feedback = app.staticTexts["player-gesture-skip-total"]
        XCTAssertTrue(feedback.exists, app.debugDescription)
        XCTAssertEqual(feedback.label, "+5")
        XCTAssertTrue(app.otherElements["player-timeline"].exists)
        XCTAssertFalse(app.buttons["Pause"].exists)
        XCTAssertTrue(app.buttons["Dismiss Up Next"].exists)
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        XCTAssertEqual(feedback.label, "+10")
        app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: [])
        XCTAssertEqual(feedback.label, "-30")
        XCTAssertTrue(app.buttons["Dismiss Up Next"].exists)
        XCTAssertTrue(feedback.waitForNonExistence(timeout: 3))
        app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: [])
        XCTAssertEqual(feedback.label, "-30")
        XCTAssertTrue(app.buttons["Dismiss Up Next"].waitForNonExistence(timeout: 3),
                      "Rewinding outside the next-episode window must update playback.")
    }

    func testSheetOwnsKeyboardAndClosingItRestoresPlaybackShortcuts() {
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "0.0", timeout: 3),
                      app.debugDescription)
        app.buttons["Dismiss Up Next"].tap()
        app.buttons["Playback options"].tap()
        app.buttons["Playback Speed"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3), app.debugDescription)
        app.typeKey(" ", modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        XCTAssertEqual(app.staticTexts["gesture-rate"].label, "0.0")
        XCTAssertFalse(app.staticTexts["player-gesture-skip-total"].exists)
        app.buttons["Done"].tap()
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "1.0", timeout: 3))
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        XCTAssertEqual(app.staticTexts["player-gesture-skip-total"].label, "+5")
    }
}
