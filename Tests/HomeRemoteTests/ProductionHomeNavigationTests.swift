import XCTest

@MainActor
final class ProductionHomeNavigationTests: XCTestCase {
    func testContinueWatchingPlayPauseAlwaysPlaysWhileSelectFollowsPreference() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let configurations: [[String]] = [
            ["--hero-disabled-home", "--focus-style=outline", "--episode-home-artwork"],
            [],
            ["--immersive-home", "--continue-watching-posters"],
            ["--hero-disabled-home", "--framed-cards", "--focus-style=highlight"]
        ]
        for configuration in configurations {
            for opensDetails in [false, true] {
                let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
                app.launchArguments = [
                    "--production-home-fixture", "--continue-watching-action-probe"
                ] + configuration + (opensDetails ? ["--continue-watching-open-details"] : [])
                app.launch()
                defer { app.terminate() }
                XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
                XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
                let first = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@ AND hasFocus == true", "Fixture movie 0")).firstMatch
                if configuration.isEmpty { XCUIRemote.shared.press(.down) }
                XCTAssertTrue(first.waitForExistence(timeout: 10))

                let playback = app.staticTexts["home-playback-probe"]
                let depth = app.staticTexts["home-detail-depth-probe"]
                XCUIRemote.shared.press(.playPause)
                waitForLabel("1:home-movie-0", on: playback)
                XCTAssertEqual(depth.label, "0", "Play/Pause must never push details.")
                XCTAssertTrue(first.hasFocus)

                XCUIRemote.shared.press(.right)
                let second = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@ AND hasFocus == true", "Fixture movie 1")).firstMatch
                XCTAssertTrue(second.waitForExistence(timeout: 10))
                XCUIRemote.shared.press(.playPause)
                waitForLabel("2:home-movie-1", on: playback)
                XCTAssertEqual(depth.label, "0", "Play/Pause must use the focused card, not the hero or previous card.")

                XCUIRemote.shared.press(.select)
                if opensDetails {
                    waitForLabel("1", on: depth)
                    XCTAssertTrue(app.staticTexts["Detail fixture Fixture movie 1"].waitForExistence(timeout: 15))
                    XCTAssertEqual(playback.label, "2:home-movie-1", "Opening details must not also play.")
                } else {
                    waitForLabel("3:home-movie-1", on: playback)
                    XCTAssertEqual(depth.label, "0", "The default center-button action remains playback.")
                }
            }
        }
        #else
        throw XCTSkip("Uses an isolated simulator with local fixture data.")
        #endif
    }

    private func waitForLabel(
        _ label: String, on element: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        let result = XCTWaiter.wait(for: [updated], timeout: 10)
        if result != .completed {
            let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "continue-watching-command-failure"
            tree.lifetime = .keepAlways
            add(tree)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertEqual(result, .completed, file: file, line: line)
    }

    func testNavigateProductionHomeWithNativeCards() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let attach = ProcessInfo.processInfo.environment["PLOZZ_PERFORMANCE_ATTACH"] == "1"
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        if attach {
            XCTAssertEqual(app.state, .runningForeground, "The profiling runner must own the already-running fixture.")
        } else {
            app.launchArguments = ["--production-home-fixture"]
            app.launchEnvironment["PLZPERF_ANIMATIONS"] = "1"
            app.launch()
        }
        defer { if !attach { app.terminate() } }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        let hero = app.buttons["home-hero-action-row"]
        XCTAssertTrue(hero.waitForExistence(timeout: 20))
        XCTAssertTrue(hero.hasFocus)
        print("PRODUCTION_HOME_READY \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 8)
        for cycle in 0..<3 {
            print("PRODUCTION_HOME_CYCLE \(cycle) \(Date().timeIntervalSince1970)")
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 1)
            XCTAssertFalse(hero.hasFocus)
            for _ in 0..<4 {
                XCUIRemote.shared.press(.right)
                Thread.sleep(forTimeInterval: 0.2)
            }
            for _ in 0..<4 {
                XCUIRemote.shared.press(.left)
                Thread.sleep(forTimeInterval: 0.2)
            }
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 1)
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: 1)
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(hero.hasFocus)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "production-home-after-navigation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        #else
        throw XCTSkip("This uses an isolated simulator with local fixture data.")
        #endif
    }
}
