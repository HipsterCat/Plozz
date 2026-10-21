import XCTest

@MainActor
final class DeviceSetupInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
    }

    override func tearDown() async throws {
        if app.state == .runningForeground {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.terminate()
        app = nil
        try await super.tearDown()
    }

    func testOfferRetainsProgressFailureAndRetryUntilClosed() {
        launch()
        app.buttons["setup-send-confirm"].tap()
        XCTAssertTrue(app.staticTexts["Setting up the other device…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["setup-send-retry"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Setup didn’t finish"].exists)
        XCTAssertFalse(app.buttons["Show setup offer"].isHittable)
        app.buttons["setup-send-retry"].tap()
        XCTAssertTrue(app.staticTexts["Setting up the other device…"].waitForExistence(timeout: 3))
        app.buttons["setup-send-cancel"].tap()
        XCTAssertTrue(app.staticTexts["Offer consumed"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.staticTexts["setup-fixture-attempts"].label, "Attempts: 2")
        XCTAssertFalse(app.buttons["setup-send-confirm"].exists)
    }

    func testAuthorizationLossDisablesRetryButKeepsCancelAvailable() {
        launch(["--revoke-setup-authorization"])
        app.buttons["setup-send-confirm"].tap()
        XCTAssertTrue(app.buttons["setup-send-retry"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["setup-send-retry"].isEnabled)
        app.buttons["setup-send-cancel"].tap()
        XCTAssertTrue(app.staticTexts["Offer consumed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["setup-fixture-attempts"].label, "Attempts: 1")
    }

    private func launch(_ arguments: [String] = []) {
        app.launchArguments = ["--device-setup-fixture"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["Show setup offer"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["setup-send-confirm"].exists, "The offer must wait for readiness.")
        XCTAssertEqual(app.staticTexts["setup-fixture-offer"].label, "Offer retained")
        app.buttons["Show setup offer"].tap()
        XCTAssertTrue(app.buttons["setup-send-confirm"].waitForExistence(timeout: 5), app.debugDescription)
    }
}
