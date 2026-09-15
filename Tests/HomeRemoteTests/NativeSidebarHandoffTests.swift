import XCTest

@MainActor
final class NativeSidebarHandoffTests: XCTestCase {
    func testProductionHomeDoesNotReclaimFocusDuringNativeSidebarSelection() {
        exerciseProductionHome(enterUsing: .select)
    }

    func testRightReturnsToProductionHomeWithoutSelectingTheHighlightedTab() {
        exerciseProductionHome(enterUsing: .right)
    }

    private func exerciseProductionHome(enterUsing button: XCUIRemote.Button) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--production-home-fixture", "--native-sidebar-home"]
        app.launchEnvironment["PLZHFOCUS_STDOUT"] = "1"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        let hero = app.buttons["home-hero-action-row"]
        XCTAssertTrue(hero.waitForExistence(timeout: 15), app.debugDescription)
        enterSelectedSidebarPage(hero, app: app)
        assertFocused(hero, app: app)
        XCUIRemote.shared.press(.left)
        assertFocused(app.buttons["Home"], app: app)
        XCUIRemote.shared.press(.playPause)
        XCTAssertEqual(app.staticTexts["native-production-armed"].label, "settings")
        XCUIRemote.shared.press(.down)
        assertFocused(app.buttons["Settings"], app: app)
        XCUIRemote.shared.press(button)
        if button == .right {
            assertFocused(hero, app: app)
            XCTAssertFalse(app.buttons["native-production-settings"].exists)
            XCTAssertEqual(app.staticTexts["native-production-premature-focus"].label, "1",
                           "The recorder must detect the intentional return to Home.")
            return
        }
        let destination = app.buttons["native-production-settings"]
        XCTAssertTrue(destination.waitForExistence(timeout: 10), app.debugDescription)
        // Select activates the highlighted tab; tvOS 27 may leave focus on the
        // sidebar chrome until Right moves into the newly presented page.
        enterSelectedSidebarPage(destination, app: app)
        assertFocused(destination, app: app)
        XCTAssertEqual(app.staticTexts["native-production-premature-focus"].label, "0", app.debugDescription)
    }

    func testNativeSidebarDoesNotVisitOutgoingContentWhenSelectingAnotherPage() {
        exerciseNativeSidebar(enterUsing: .select)
    }

    func testRightReturnsToCurrentNativePageWithoutSelectingTheHighlightedTab() {
        exerciseNativeSidebar(enterUsing: .right)
    }

    private func exerciseNativeSidebar(enterUsing button: XCUIRemote.Button) {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--native-sidebar-handoff-fixture"]
        app.launch()
        defer { app.terminate() }

        let home = app.buttons["native-page-home"]
        XCTAssertTrue(home.waitForExistence(timeout: 15), app.debugDescription)
        enterSelectedSidebarPage(home, app: app)
        assertFocused(home, app: app)
        XCUIRemote.shared.press(.left)
        assertFocused(app.buttons["Home"], app: app)
        XCUIRemote.shared.press(.playPause)
        XCUIRemote.shared.press(.down)
        assertFocused(app.buttons["Settings"], app: app)
        XCUIRemote.shared.press(button)
        if button == .right {
            assertFocused(home, app: app)
            XCTAssertFalse(app.buttons["native-page-settings"].exists)
            XCTAssertEqual(app.staticTexts["native-premature-focus-home"].label, "1")
            return
        }

        let settings = app.buttons["native-page-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        enterSelectedSidebarPage(settings, app: app)
        assertFocused(settings, app: app)
        XCTAssertEqual(app.staticTexts["native-premature-focus-settings"].label, "0", app.debugDescription)
        XCTAssertEqual(app.staticTexts["native-unpresented-focus-settings"].label, "0",
                       "Destination focus must wait for appearance and a rendered frame.")
        XCTAssertEqual(app.staticTexts["native-handoff-status"].label, "ready")

        XCUIRemote.shared.press(.left)
        assertFocused(app.buttons["Settings"], app: app)
        XCUIRemote.shared.press(.playPause)
        XCUIRemote.shared.press(.up)
        assertFocused(app.buttons["Home"], app: app)
        XCUIRemote.shared.press(.select)
        enterSelectedSidebarPage(home, app: app)
        assertFocused(home, app: app)
        XCTAssertEqual(app.staticTexts["native-premature-focus-home"].label, "0")
        XCTAssertEqual(app.staticTexts["native-unpresented-focus-home"].label, "0")
        XCTAssertEqual(app.staticTexts["native-handoff-status"].label, "ready")

        XCUIRemote.shared.press(.left)
        assertFocused(app.buttons["Home"], app: app)
        XCUIRemote.shared.press(.select)
        enterSelectedSidebarPage(home, app: app)
        assertFocused(home, app: app)
        XCTAssertEqual(app.staticTexts["native-handoff-status"].label, "ready")
    }

    /// tvOS 27 `TabView` + `.sidebarAdaptable` may leave focus on the sidebar
    /// chrome briefly after Select. Give the content focus requester a moment,
    /// then nudge Right if needed.
    private func enterSelectedSidebarPage(_ content: XCUIElement, app: XCUIApplication) {
        if isElementFocused(content, app: app) { return }
        let ready = app.staticTexts["native-handoff-status"]
        if ready.exists {
            let waitingDone = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in ready.label == "ready" },
                object: nil
            )
            _ = XCTWaiter.wait(for: [waitingDone], timeout: 3)
        }
        _ = content.waitForExistence(timeout: 5)
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.isElementFocused(content, app: app) },
            object: nil
        )
        if XCTWaiter.wait(for: [focused], timeout: 3) == .completed { return }
        for _ in 0..<4 {
            XCUIRemote.shared.press(.right)
            if isElementFocused(content, app: app) { return }
        }
        if content.exists, !isElementFocused(content, app: app) {
            XCUIRemote.shared.press(.select)
        }
    }

    private func isElementFocused(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        if element.hasFocus { return true }
        let focused = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).firstMatch
        guard focused.exists else { return false }
        if !element.label.isEmpty, focused.label == element.label { return true }
        return element.frame.intersects(focused.frame)
    }

    private func assertFocused(
        _ element: XCUIElement, app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.isElementFocused(element, app: app) },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed,
                       app.debugDescription, file: file, line: line)
    }
}
