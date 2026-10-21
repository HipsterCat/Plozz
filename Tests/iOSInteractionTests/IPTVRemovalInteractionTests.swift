import XCTest

@MainActor
final class IPTVRemovalInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
    }

    override func tearDown() {
        if let testRun, testRun.failureCount > 0, app.state == .runningForeground {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.terminate()
        app = nil
        super.tearDown()
    }

    func testSourceRetryShowsProgressWithoutOpeningDetailsAndWorksWithinDetails() {
        app.launchArguments = ["--source-retry-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let retry = app.buttons["live-tv-source-retry-source"]
        let progress = app.descendants(matching: .any)
            .matching(identifier: "live-tv-source-retry-progress-source").firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        for count in 1...2 {
            if count == 2 {
                app.buttons["live-tv-source-details-source"].tap()
                XCTAssertTrue(app.switches["live-tv-source-enabled-source"].waitForExistence(timeout: 5))
            }
            retry.tap()
            let loading = NSPredicate { _, _ in
                progress.exists && progress.label.contains("Loading channels and guide") && !retry.exists
            }
            XCTAssertEqual(XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: loading, object: nil)], timeout: 2
            ), .completed, app.debugDescription)
            XCTAssertFalse(app.staticTexts["Loading channels"].exists)
            XCTAssertFalse(app.staticTexts["Refreshing sources"].exists)
            XCTAssertEqual(app.progressIndicators.count, 0, "Only the inline, accessibility-hidden spinner should be visible.")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "source-retry-loading-\(count)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.buttons["fixture-finish-retry"].tap()
            let finished = NSPredicate { _, _ in retry.exists && retry.isEnabled && !progress.exists }
            XCTAssertEqual(XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: finished, object: nil)], timeout: 5
            ), .completed, app.debugDescription)
            if count == 1 {
                XCTAssertTrue(app.buttons["live-tv-source-details-source"].exists, app.debugDescription)
                XCTAssertEqual(app.staticTexts["fixture-source-retries"].label, "Retries: 1")
            }
        }
    }

    func testRemovingAdditionalGuidesKeepsTheOtherRowsAndAllowsAddingAgain() {
        verifyRemoval(
            arguments: [], field: "Additional guide URL", remove: "Remove guide", add: "Add guide",
            values: (2...4).map { "https://guide.example.test/\($0).xml" }
        )
    }

    func testSourceSwitchUsesAnActionLabelInBothStates() {
        app.launchArguments = [
            "--source-retry-fixture", "--allow-source-changes",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        let details = app.buttons["live-tv-source-details-source"]
        XCTAssertTrue(details.waitForExistence(timeout: 10), app.debugDescription)
        details.tap()
        let sourceSwitch = app.switches["live-tv-source-enabled-source"]
        XCTAssertTrue(sourceSwitch.waitForExistence(timeout: 5))
        XCTAssertEqual(sourceSwitch.label, "Use this source")
        XCTAssertEqual(sourceSwitch.value as? String, "1")
        sourceSwitch.tap()
        XCTAssertEqual(sourceSwitch.value as? String, "0")
        XCTAssertEqual(sourceSwitch.label, "Use this source")
        sourceSwitch.tap()
        XCTAssertEqual(sourceSwitch.value as? String, "1")
        XCTAssertEqual(sourceSwitch.label, "Use this source")
    }

    func testRemovingPlaylistHeadersKeepsTheOtherRowsAndAllowsAddingAgain() {
        verifyRemoval(
            arguments: ["--playlist-headers"], field: "Header name", remove: "Remove header", add: "Add header",
            values: (1...3).map { "X-Guide-\($0)" }
        )
    }

    func testRemovingGuideHeadersKeepsTheOtherRowsAndAllowsAddingAgain() {
        verifyRemoval(
            arguments: ["--guide-headers"], field: "Header name", remove: "Remove header", add: "Add header",
            values: (1...3).map { "X-Guide-\($0)" }
        )
    }

    private func verifyRemoval(arguments: [String], field: String, remove: String, add: String, values: [String]) {
        app.launchArguments = ["--iptv-removal-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        app.launch()
        let advanced = app.buttons["iptv-advanced-options"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(advanced.value as? String, "Expanded")
        let fields = app.textFields.matching(identifier: field)
        let buttons = app.buttons.matching(identifier: remove)
        waitForCount(fields, 3)
        XCTAssertEqual(fields.allElementsBoundByIndex.compactMap { $0.value as? String }, values)

        // Remove the middle, last, then first row so shifted bindings are exercised.
        var remaining = values
        for index in [1, 1, 0] {
            let button = buttons.element(boundBy: index)
            reveal(button)
            button.tap()
            remaining.remove(at: index)
            waitForCount(fields, remaining.count)
            XCTAssertEqual(fields.allElementsBoundByIndex.compactMap { $0.value as? String }, remaining)
            XCTAssertEqual(app.state, .runningForeground)
        }
        let addButton = app.buttons.matching(identifier: add).element(
            boundBy: arguments.contains("--guide-headers") ? 1 : 0
        )
        reveal(addButton)
        addButton.tap()
        waitForCount(fields, 1)
        reveal(buttons.firstMatch)
        buttons.firstMatch.tap()
        waitForCount(fields, 0)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.textFields["EPG URL (optional)"].exists)
    }

    private func waitForCount(_ query: XCUIElementQuery, _ count: Int) {
        let predicate = NSPredicate { _, _ in query.count == count }
        XCTAssertEqual(XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5
        ), .completed, app.debugDescription)
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 {
            let safeFrame = app.windows.firstMatch.frame.insetBy(dx: 0, dy: 90)
            if element.exists && element.isHittable && safeFrame.contains(element.frame) { return }
            if element.exists && element.frame.midY < app.windows.firstMatch.frame.midY {
                app.scrollViews.firstMatch.swipeDown()
            } else {
                app.scrollViews.firstMatch.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
}
