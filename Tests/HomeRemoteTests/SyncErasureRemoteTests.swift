import XCTest

@MainActor
final class SyncErasureRemoteTests: XCTestCase {
    func testRemoteRequiresReviewAndFinalConfirmation() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--sync-erasure-fixture"]
        app.launch()
        defer { app.terminate() }
        let review = app.buttons["Review Erasure"]
        assertFocused(review)
        XCUIRemote.shared.press(.select)
        let proceed = app.buttons["cloud-sync-erase-continue"]
        assertFocused(proceed)
        XCTAssertEqual(proceed.label, "Erase Sync Data…")
        let heading = app.staticTexts.matching(identifier: "Erase Sync Data")
        XCTAssertEqual(heading.count, 1)
        XCTAssertLessThan(heading.firstMatch.frame.height, 50)
        XCTAssertTrue(app.staticTexts["From iCloud"].exists)
        XCTAssertTrue(app.staticTexts["From this device"].exists)
        XCTAssertTrue(app.staticTexts["Not affected"].exists)
        capture(app, name: "sync-erasure-tv-review")
        let dialog = app.otherElements["cloud-sync-erase-dialog"].firstMatch
        XCTAssertTrue(dialog.exists)
        XCTAssertGreaterThan(dialog.frame.minY, app.frame.minY)
        XCTAssertLessThan(dialog.frame.height, app.frame.height)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCUIRemote.shared.press(.down)
        assertFocused(app.buttons["cloud-sync-erase-cancel"])
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["fixture-erasure-count"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["fixture-erasure-count"].label, "Erasures: 0")
        assertFocused(review)
        XCUIRemote.shared.press(.select)
        assertFocused(proceed)
        XCUIRemote.shared.press(.menu)
        assertFocused(review)
        XCTAssertEqual(app.staticTexts["fixture-erasure-count"].label, "Erasures: 0")
        XCUIRemote.shared.press(.select)
        assertFocused(proceed)
        XCUIRemote.shared.press(.select)
        let alert = app.alerts["Erase sync data?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "sync-erasure-tv-confirmation"
        attachment.lifetime = .keepAlways
        add(attachment)
        assertFocused(alert.buttons.matching(identifier: "Cancel"))
        XCUIRemote.shared.press(.select)
        assertFocused(proceed)
        XCUIRemote.shared.press(.select)
        assertFocused(alert.buttons.matching(identifier: "Cancel"))
        XCUIRemote.shared.press(.right)
        let focusAttachment = XCTAttachment(string: app.debugDescription)
        focusAttachment.name = "sync-erasure-tv-alert-focus"
        focusAttachment.lifetime = .keepAlways
        add(focusAttachment)
        assertFocused(alert.buttons.matching(identifier: "Erase Data"))
        XCUIRemote.shared.press(.select)
        assertFocused(app.buttons["cloud-sync-erase-cancel"])
        XCTAssertFalse(proceed.isEnabled)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["fixture-erasure-count"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["fixture-erasure-count"].label, "Erasures: 1")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testUnauthorizedRemoteReviewHasNoDestructiveFocusTarget() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--sync-erasure-fixture", "--sync-erasure-denied"]
        app.launch()
        defer { app.terminate() }
        assertFocused(app.buttons["Review Erasure"])
        XCUIRemote.shared.press(.select)
        assertFocused(app.buttons["cloud-sync-erase-cancel"])
        XCTAssertFalse(app.buttons["cloud-sync-erase-continue"].isEnabled)
        XCUIRemote.shared.press(.up)
        assertFocused(app.buttons["cloud-sync-erase-cancel"])
        XCUIRemote.shared.press(.select)
        XCTAssertEqual(app.staticTexts["fixture-erasure-count"].label, "Erasures: 0")
    }

    private func assertFocused(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in element.exists && element.hasFocus },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expected], timeout: 8), .completed,
            "Expected native focus on \(element).", file: file, line: line
        )
    }

    private func assertFocused(_ elements: XCUIElementQuery, file: StaticString = #filePath, line: UInt = #line) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in elements.allElementsBoundByIndex.contains { $0.hasFocus } },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expected], timeout: 8), .completed,
            "Expected native focus on a matching alert action.", file: file, line: line
        )
    }
}
