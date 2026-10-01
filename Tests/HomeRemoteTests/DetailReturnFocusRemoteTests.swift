import XCTest

@MainActor
final class DetailReturnFocusRemoteTests: XCTestCase {
    func testSequentialNativeLibraryDetailsNeverRetainADismissedPage() throws {
        try checkSequentialNativeDetails(waitForTrailer: false)
    }

    func testSequentialNativeLibraryTrailersBelongOnlyToTheCurrentDetail() throws {
        try checkSequentialNativeDetails(waitForTrailer: true)
    }

    private func checkSequentialNativeDetails(waitForTrailer: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = [
            "--production-home-fixture", "--native-sidebar-home", "--library-detail-sequence"
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        let routeDepth = app.staticTexts["detail-sequence-route-depth"]
        let pageDepth = app.staticTexts["detail-sequence-page-depth"]
        let trailerOwner = app.staticTexts["detail-sequence-trailer-owner"]
        let ready = NSPredicate { _, _ in
            app.descendants(matching: .any).matching(
                NSPredicate(format: "hasFocus == true AND label BEGINSWITH %@", "Fixture movie")
            ).firstMatch.exists
        }
        if app.buttons["Home"].firstMatch.hasFocus { XCUIRemote.shared.press(.select) }
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 3) != .completed {
            XCUIRemote.shared.press(.down)
        }
        XCTAssertEqual(XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10
        ), .completed)
        for visit in 0..<(waitForTrailer ? 4 : 8) {
            XCTAssertEqual(routeDepth.label, "0", "visit \(visit)")
            XCTAssertEqual(pageDepth.label, "0", "visit \(visit)")
            if visit > 0 { XCUIRemote.shared.press(visit.isMultiple(of: 2) ? .left : .right) }
            let card = app.descendants(matching: .any).matching(
                NSPredicate(format: "hasFocus == true AND label BEGINSWITH %@", "Fixture movie")
            ).firstMatch
            let title = card.label
            XCTAssertFalse(title.isEmpty)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts["Detail fixture \(title)"].waitForExistence(timeout: 10))
            XCTAssertEqual(routeDepth.label, "1")
            XCTAssertEqual(pageDepth.label, "1")
            if waitForTrailer {
                let index = try XCTUnwrap(title.split(separator: " ").last)
                let playing = NSPredicate { _, _ in trailerOwner.label == "home-movie-\(index)" }
                XCTAssertEqual(XCTWaiter.wait(
                    for: [XCTNSPredicateExpectation(predicate: playing, object: nil)], timeout: 8
                ), .completed, "Only the currently opened movie may own the trailer.")
            }
            if visit.isMultiple(of: 2) { Thread.sleep(forTimeInterval: 1.5) }
            XCUIRemote.shared.press(.menu)
            let returned = NSPredicate { _, _ in routeDepth.label == "0" && pageDepth.label == "0" }
            let result = XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: returned, object: nil)], timeout: 5
            )
            if result != .completed {
                let tree = XCTAttachment(string: app.debugDescription)
                tree.name = "stale-detail-after-visit-\(visit)"
                tree.lifetime = .keepAlways
                add(tree)
                let image = XCTAttachment(screenshot: app.screenshot())
                image.name = "detail-return-visit-\(visit)"
                image.lifetime = .keepAlways
                add(image)
            }
            XCTAssertEqual(result, .completed, "Back must remove the real route, not only its picture.")
            XCTAssertEqual(trailerOwner.label, "none", "A library return must not keep the dismissed trailer.")
            assertFocused(title, in: app)
        }
    }

    func testRepeatedDetailVisitsReturnToTheSelectedHomeCard() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--production-home-fixture", "--pinned-home"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        let hero = app.buttons["home-hero-action-row"]
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertTrue(hero.hasFocus)
        XCTAssertFalse(app.buttons["Navigation"].isEnabled, "Navigation must start closed while Home receives focus.")
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 1)
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 1)
        assertFocused("Fixture movie 24", in: app)
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.right)
        assertFocused("Fixture movie 26", in: app)
        for visit in 0..<5 {
            if visit == 3 { XCUIRemote.shared.press(.left) }
            let title = visit < 3 ? "Fixture movie 26" : "Fixture movie 25"
            assertFocused(title, in: app)
            XCUIRemote.shared.press(.select)
            let opened = app.staticTexts["Detail fixture \(title)"].waitForExistence(timeout: 10)
            if !opened {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "failed-detail-open"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            XCTAssertTrue(opened)
            Thread.sleep(forTimeInterval: 2)
            XCUIRemote.shared.press(.menu)
            assertFocused(title, in: app)
            XCTAssertFalse(app.buttons["Navigation"].isEnabled)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "home-focus-after-repeated-detail-visits"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertFocused(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let predicate = NSPredicate { _, _ in
            focused.exists && (focused.label == title || focused.staticTexts[title].exists)
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5)
        if result != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "failed-return-focus-\(title)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed, "Expected focus on \(title)", file: file, line: line)
    }
}
