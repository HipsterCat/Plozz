import XCTest

@MainActor
final class GuideVerticalNavigationRemoteTests: XCTestCase {
    func testVerticalBrowsingKeepsCurrentProgramsDespiteWideMovies() {
        let app = launchGuide()
        defer { app.terminate() }
        for row in 1..<7 {
            XCUIRemote.shared.press(.down)
            assertSelected("Current \(row)", in: app)
        }
        XCUIRemote.shared.press(.down)
        assertSelected("channel-7", in: app)
        for row in (0..<7).reversed() {
            XCUIRemote.shared.press(.up)
            assertSelected("Current \(row)", in: app)
        }
    }

    func testHorizontalBrowsingHandsOffToNativeUntilNowResetsIt() {
        let app = launchGuide()
        defer { app.terminate() }
        XCUIRemote.shared.press(.down)
        assertSelected("Current 1", in: app)
        XCUIRemote.shared.press(.right)
        assertSelected("Future 1.1", in: app)
        XCUIRemote.shared.press(.down)
        assertSelected("Future 2.1", in: app)
        for _ in 0..<12 where !app.buttons["guide-now"].hasFocus {
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(app.buttons["guide-now"].hasFocus)
        XCUIRemote.shared.press(.select)
        // Now clears native spatial mode and focuses the current programme of
        // whatever row is active — not necessarily channel 0. The Now button may
        // keep UIKit focus; nudge into the guide until a Current * cell wins.
        for _ in 0..<8 where app.buttons["guide-now"].hasFocus {
            XCUIRemote.shared.press(.down)
        }
        assertSelectedCurrent(in: app)
        let afterNow = app.staticTexts["guide-focus-probe"].label
        XCUIRemote.shared.press(.down)
        let afterDown = app.staticTexts["guide-focus-probe"]
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in afterDown.exists && afterDown.label != afterNow },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 8), .completed,
                       "Down after Now must advance from \(afterNow)")
    }

    private func assertSelectedCurrent(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let probe = app.staticTexts["guide-focus-probe"]
        let predicate = NSPredicate { _, _ in
            probe.exists && probe.label.hasPrefix("Current ")
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 8)
        if result != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "unexpected-guide-focus"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed,
                       "Expected a Current * programme after Now, got \(probe.label)",
                       file: file, line: line)
    }

    private func launchGuide() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--guide-navigation-fixture"]
        app.launch()
        let probe = app.staticTexts["guide-focus-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 15), app.debugDescription)
        // Restoration can leave focus on chrome or the channel column; nudge until
        // a Current programme is selected.
        for _ in 0..<12 where probe.label != "Current 0" {
            XCUIRemote.shared.press(.down)
            if probe.label == "Current 0" { break }
            Thread.sleep(forTimeInterval: 0.15)
        }
        if probe.label != "Current 0" {
            for _ in 0..<8 where probe.label != "Current 0" {
                XCUIRemote.shared.press(.up)
                if probe.label.hasPrefix("Current ") { break }
            }
        }
        assertSelected("Current 0", in: app)
        return app
    }

    private func assertSelected(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let probe = app.staticTexts["guide-focus-probe"]
        let predicate = NSPredicate { _, _ in probe.exists && probe.label == title }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 8)
        if result != .completed {
            let hierarchy = XCTAttachment(string: "probe=\(probe.label)\n\(app.debugDescription)")
            hierarchy.name = "unexpected-guide-focus"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed, "Expected \(title), got \(probe.label)", file: file, line: line)
    }
}
