import XCTest

@MainActor
final class PlexHomeOnboardingInteractionTests: XCTestCase {
    func testLongImportedListStartsWithVisibleFocusAndScrollsToTheLastUser() {
        let app = app
        app.launchArguments = ["--plex-home-onboarding-fixture", "--plex-home-long-list"]
        app.launch()
        defer { app.terminate() }
        activate(app.buttons["plex-home-add-all"])
        let parent = app.buttons["plex-home-user-parent"]
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        #if os(tvOS)
        waitForFocus(parent)
        #endif
        XCTAssertTrue(app.frame.contains(parent.frame), "Initial focus must be fully inside the viewport.")
        XCTAssertTrue(parent.isHittable)
        capture(app, name: "Long Plex Home list entry")
        let last = app.buttons["plex-home-user-viewer-13"]
        #if os(tvOS)
        for _ in 0..<15 { XCUIRemote.shared.press(.down) }
        waitForFocus(last)
        #else
        for _ in 0..<10 {
            if last.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        #endif
        XCTAssertTrue(last.isHittable)
        XCTAssertTrue(app.frame.contains(last.frame))
        capture(app, name: "Long Plex Home list last user")
        #if os(tvOS)
        XCUIRemote.shared.press(.select)
        #else
        last.tap()
        #endif
        let result = app.staticTexts["plex-home-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "viewer-13:all")
    }

    private var app: XCUIApplication {
        #if os(tvOS)
        XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        #else
        XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        #endif
    }

    func testAddAllTransitionsToUsersAndKeepsTheImportChoice() {
        let app = app
        app.launchArguments = ["--plex-home-onboarding-fixture"]
        app.launch()
        defer { app.terminate() }
        let addAll = app.buttons["plex-home-add-all"]
        XCTAssertTrue(addAll.waitForExistence(timeout: 10))
        #if os(tvOS)
        waitForFocus(addAll)
        #endif
        capture(app, name: "Plex Home import choice")
        activate(addAll)
        let parent = app.buttons["plex-home-user-parent"]
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["plex-home-result"].exists)
        #if os(tvOS)
        waitForFocus(parent)
        #endif
        capture(app, name: "Plex Home viewer choice")
        activate(parent)
        let result = app.staticTexts["plex-home-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "parent:all")
    }

    func testBackChangesImportChoiceWithoutCompletingSetup() {
        let app = app
        app.launchArguments = ["--plex-home-onboarding-fixture"]
        app.launch()
        defer { app.terminate() }
        activate(app.buttons["plex-home-just-me"])
        let parent = app.buttons["plex-home-user-parent"]
        XCTAssertTrue(parent.waitForExistence(timeout: 5))
        #if os(tvOS)
        XCUIRemote.shared.press(.menu)
        #else
        let back = app.buttons["plex-home-back"]
        if !back.waitForExistence(timeout: 2) { app.scrollViews.firstMatch.swipeUp() }
        activate(back)
        #endif
        activate(app.buttons["plex-home-add-all"])
        activate(app.buttons["plex-home-user-parent"])
        let result = app.staticTexts["plex-home-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "parent:all")
    }

    func testReducedMotionRetainsChoicesAndUserSelection() {
        let app = app
        app.launchArguments = ["--plex-home-onboarding-fixture", "--plex-home-reduce-motion"]
        app.launch()
        defer { app.terminate() }
        activate(app.buttons["plex-home-just-me"])
        activate(app.buttons["plex-home-user-child"])
        let result = app.staticTexts["plex-home-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "child:one")
    }

    private func activate(_ button: XCUIElement) {
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        #if os(tvOS)
        let defaultButton = button.identifier == "plex-home-just-me"
            || button.identifier == "plex-home-add-all"
            ? app.buttons["plex-home-add-all"]
            : app.buttons["plex-home-user-parent"]
        waitForFocus(defaultButton)
        if !button.hasFocus {
            XCUIRemote.shared.press(.down)
            waitForFocus(button)
        }
        XCUIRemote.shared.press(.select)
        #else
        button.tap()
        #endif
    }

    #if os(tvOS)
    private func waitForFocus(_ element: XCUIElement) {
        let focused = NSPredicate { _, _ in element.hasFocus }
        XCTAssertEqual(XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: focused, object: nil)], timeout: 5
        ), .completed)
    }
    #endif

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
