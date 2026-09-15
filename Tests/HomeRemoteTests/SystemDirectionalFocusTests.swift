import XCTest

@MainActor
final class SystemDirectionalFocusTests: XCTestCase {
    func testRemoteDirectionsDoNotRestoreThePreviousCardOrHero() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        try FocusStyleSettingsCaptureTests.withFocusStyle("Default") { _ in
            for borderless in [false, true] {
                add(try Self.exerciseDirections(in: app, borderless: borderless))
            }
        }
        #else
        throw XCTSkip("This regression uses an isolated simulator fixture.")
        #endif
    }

    static func exerciseDirections(in app: XCUIApplication, borderless: Bool) throws -> XCTAttachment {
        app.launchArguments = ["--focus-navigation-fixture"] + (borderless ? ["--borderless"] : [])
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Navigation fixture ready"].waitForExistence(timeout: 15))
        let hero = app.buttons["navigation-hero"]
        XCTAssertTrue(hero.hasFocus)
        XCUIRemote.shared.press(.down)
        try assertFocus("Row 0 Item 0", in: app)
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 0 Item 1", in: app)
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 0 Item 2", in: app)
        XCUIRemote.shared.press(.left)
        try assertFocus("Row 0 Item 1", in: app)
        for index in 2...6 {
            XCUIRemote.shared.press(.right)
            try assertFocus("Row 0 Item \(index)", in: app)
        }
        for index in stride(from: 5, through: 0, by: -1) {
            XCUIRemote.shared.press(.left)
            try assertFocus("Row 0 Item \(index)", in: app)
        }
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 0 Item 1", in: app)
        XCUIRemote.shared.press(.down)
        try assertFocus("Row 1 Item 1", in: app)
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 1 Item 2", in: app)
        XCUIRemote.shared.press(.up)
        try assertFocus("Row 0 Item 2", in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "native-directions-\(borderless ? "borderless" : "framed")"
        screenshot.lifetime = .keepAlways
        return screenshot
    }

    private static func assertFocus(_ label: String, in app: XCUIApplication) throws {
        // System / highlight styles may put focus on an inner container rather
        // than the Button whose accessibility label is the title.
        let focused = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let predicate = NSPredicate { _, _ in
            focused.exists && (focused.label == label || focused.staticTexts[label].exists
                || focused.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", label)).count > 0)
        }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 3),
            .completed,
            "Expected \(label). \(app.debugDescription)"
        )
        Thread.sleep(forTimeInterval: 0.35)
        let still = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let stillOnTarget = still.exists && (still.label == label || still.staticTexts[label].exists
            || still.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", label)).count > 0)
        XCTAssertTrue(stillOnTarget, "Focus bounced away from \(label). \(app.debugDescription)")
    }
}
