import XCTest

@MainActor
final class SetupSummaryRemoteTests: XCTestCase {
    func testPickerKeepsAllMethodsVisibleAndCancelReachable() {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--setup-picker-fixture"]
        app.launch()
        defer { app.terminate() }
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["iPhone or iPad"].isHittable)
        XCTAssertTrue(app.staticTexts["Nearby devices"].isHittable)
        XCTAssertTrue(app.staticTexts["Enter a code"].isHittable)
        for _ in 0..<4 where !focused(cancel) { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(focused(cancel), app.debugDescription)
        capture(app, name: "setup-picker-cancel")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["setup-closed"].waitForExistence(timeout: 5))
    }

    func testRemoteReachesLastServerAndProfileWithoutLosingDone() {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--setup-summary-fixture"]
        app.launch()
        defer { app.terminate() }
        let done = app.buttons["sync-setup-continue"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let footerFrame = done.frame
        XCTAssertTrue(app.frame.contains(footerFrame))
        let viewport = app.scrollViews.firstMatch.frame
        XCTAssertEqual(viewport.minY, app.frame.minY, accuracy: 1, "Scrolling must reach the page's top edge.")
        capture(app, name: "setup-summary-top")
        let lastServer = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Server 24")
        ).firstMatch
        var reachedServer = false
        let lastProfile = app.descendants(matching: .any)["setup-summary-profile-profile-39"].firstMatch
        for step in 0..<40 {
            if !reachedServer && lastServer.exists && viewport.contains(lastServer.frame) && lastServer.isHittable {
                reachedServer = true
            }
            if lastProfile.exists && viewport.contains(lastProfile.frame) && lastProfile.isHittable { break }
            XCUIRemote.shared.press(.down)
            if step == 5 { capture(app, name: "setup-summary-scrolling-to-page-edge") }
        }
        XCTAssertTrue(reachedServer, "Native focus must scroll through every server.")
        XCTAssertTrue(lastProfile.isHittable, "Native focus must reach the final profile row.")
        XCTAssertTrue(viewport.contains(lastProfile.frame), "The final profile must be fully inside the viewport.")
        XCTAssertEqual(done.frame.midY, footerFrame.midY, accuracy: 2)
        capture(app, name: "setup-summary-last-profiles")
        for _ in 0..<8 where !focused(done) { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(focused(done), app.debugDescription)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["setup-closed"].waitForExistence(timeout: 5))
    }

    private func focused(_ element: XCUIElement) -> Bool {
        element.hasFocus || element.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).count > 0
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
