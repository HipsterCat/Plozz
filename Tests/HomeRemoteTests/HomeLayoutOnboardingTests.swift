import XCTest

@MainActor
final class HomeLayoutOnboardingTests: XCTestCase {
    func testSelectionPersistsAndDownReachesContinueFromEitherCard() {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--home-layout-onboarding-fixture"]
        app.launch()
        defer { app.terminate() }
        let fullscreen = app.buttons["home-layout-carousel"]
        let showcase = app.buttons["home-layout-followsFocus"]
        waitForFocus(fullscreen)
        XCTAssertTrue(fullscreen.isSelected)
        XCUIRemote.shared.press(.down)
        waitForFocus(app.buttons["Continue"])
        XCUIRemote.shared.press(.up)
        waitForFocus(fullscreen)
        XCUIRemote.shared.press(.right)
        waitForFocus(showcase)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(showcase.isSelected)
        XCTAssertFalse(fullscreen.isSelected)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Navigation-neutral Home layout choices"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIRemote.shared.press(.down)
        waitForFocus(app.buttons["Continue"])
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["saved-home-layout"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["saved-home-layout"].label, "Saved layout: followsFocus")

        app.terminate()
        app.launchArguments.append("--restore-home-layout")
        app.launch()
        waitForFocus(showcase)
        XCTAssertTrue(showcase.isSelected)
        XCUIRemote.shared.press(.left)
        waitForFocus(fullscreen)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.down)
        waitForFocus(app.buttons["Continue"])
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["saved-home-layout"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["saved-home-layout"].label, "Saved layout: carousel")
    }

    func testMenuAcceptsCurrentSelectionWithoutResettingIt() {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--home-layout-onboarding-fixture", "--selected-showcase"]
        app.launch()
        defer { app.terminate() }
        waitForFocus(app.buttons["home-layout-followsFocus"])
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["saved-home-layout"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["saved-home-layout"].label, "Saved layout: followsFocus")
    }

    private func waitForFocus(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let focused = NSPredicate { _, _ in element.hasFocus }
        XCTAssertEqual(XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: focused, object: nil)], timeout: 5
        ), .completed)
    }
}
