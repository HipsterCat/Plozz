import XCTest

@MainActor
final class DetailReturnFocusRemoteTests: XCTestCase {
    func testSingleRelatedItemCannotBeSkippedForCast() throws {
        try checkRelatedEntry(arguments: ["--related-single"], hasRelated: true)
    }

    func testEmptyRelatedRowDoesNotBlockCastEntry() throws {
        try checkRelatedEntry(arguments: ["--related-empty"], hasRelated: false)
    }

    func testShortRelatedRowCannotBeSkippedForCast() throws {
        try checkRelatedEntry(arguments: [], hasRelated: true)
    }

    func testRapidPassThroughEpisodesPreservesTheBrowsedEpisode() throws {
        try checkRelatedEntry(arguments: [], hasRelated: true, passesThroughHero: true)
    }

    private func checkRelatedEntry(
        arguments: [String], hasRelated: Bool, passesThroughHero: Bool = false
    ) throws {
        continueAfterFailure = false
        for style in ["system", "highlight", "outlined"] {
            let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
            app.launchArguments = ["--episode-breadcrumb-fixture", "--series-navigation", "--\(style)"] + arguments
            app.launch()
            defer { app.terminate() }
            let play = app.buttons["detail-hero-play"]
            XCTAssertTrue(play.waitForExistence(timeout: 20))
            // Row navigation starts after the separately covered cinematic entrance.
            Thread.sleep(forTimeInterval: 2)
            let focus = NSPredicate(format: "hasFocus == true")
            XCTAssertEqual(XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: focus, object: play)], timeout: 10
            ), .completed)
            XCUIRemote.shared.press(.down)
            if app.buttons["Season 2"].hasFocus { XCUIRemote.shared.press(.down) }
            assertSeriesRowFocused("Fixture Episode", in: app)
            let nextRow = hasRelated ? "Related Show" : "Character"
            XCTAssertTrue(app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", nextRow)
            ).firstMatch.waitForExistence(timeout: 10))
            let focused = app.descendants(matching: .any).matching(focus).firstMatch
            let horizontalMoves = passesThroughHero ? [0, 0, 3, 0] : [0, 2, 1, 5]
            for (roundTrip, moves) in horizontalMoves.enumerated() {
                for _ in 0..<moves { XCUIRemote.shared.press(.right) }
                assertSeriesRowFocused("Fixture Episode", in: app)
                let episodeNumber = roundTrip < 2 ? 1 : 4
                let rememberedEpisode = "E\(episodeNumber) · Fixture Episode \(episodeNumber),"
                if passesThroughHero { assertSeriesRowFocused(rememberedEpisode, in: app) }
                XCUIRemote.shared.press(.down)
                assertSeriesRowFocused(nextRow, in: app)
                assertSeriesFocusVisible(focused, in: app)
                if passesThroughHero {
                    for _ in 0..<(roundTrip % 3) { XCUIRemote.shared.press(.right) }
                    XCUIRemote.shared.press(.up)
                    XCUIRemote.shared.press(.up)
                    XCUIRemote.shared.press(.up)
                    XCTAssertTrue(play.hasFocus, "Rapid Up must reach the hero.")
                    XCUIRemote.shared.press(.down)
                    if app.buttons["Season 2"].hasFocus { XCUIRemote.shared.press(.down) }
                    assertSeriesRowFocused(rememberedEpisode, in: app)
                    assertSeriesFocusVisible(focused, in: app)
                    continue
                }
                XCUIRemote.shared.press(.up)
                assertSeriesRowFocused("Fixture Episode", in: app)
                assertSeriesFocusVisible(focused, in: app)
            }
            if hasRelated {
                XCUIRemote.shared.press(.down)
                assertSeriesRowFocused("Related Show", in: app)
                XCUIRemote.shared.press(.down)
                assertSeriesRowFocused("Character", in: app)
                XCUIRemote.shared.press(.up)
                assertSeriesRowFocused("Related Show", in: app)
                assertSeriesFocusVisible(focused, in: app)
            }
        }
    }

    func testEpisodeRelatedDirectionsRevealTheFocusedRow() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--episode-breadcrumb-fixture", "--series-navigation"]
        app.launch()
        defer { app.terminate() }
        let play = app.buttons["detail-hero-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        let focus = NSPredicate(format: "hasFocus == true")
        XCTAssertEqual(XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: focus, object: play)], timeout: 10
        ), .completed)
        XCUIRemote.shared.press(.down)
        if app.buttons["Season 2"].hasFocus { XCUIRemote.shared.press(.down) }
        let focused = app.descendants(matching: .any).matching(focus).firstMatch
        assertSeriesRowFocused("Fixture Episode", in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Related Show")
        ).firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<4 {
            XCUIRemote.shared.press(.down)
            assertSeriesRowFocused("Related Show", in: app)
            assertSeriesFocusVisible(focused, in: app)
            XCUIRemote.shared.press(.up)
            assertSeriesRowFocused("Fixture Episode", in: app)
            assertSeriesFocusVisible(focused, in: app)
        }
    }

    private func assertSeriesFocusVisible(
        _ focused: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let visible = NSPredicate { _, _ in focused.exists && app.frame.contains(focused.frame) }
        XCTAssertEqual(XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: visible, object: nil)], timeout: 2
        ), .completed, "The focused row must come fully onscreen.", file: file, line: line)
    }

    private func assertSeriesRowFocused(
        _ label: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let matches = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label))
        let ownsFocus = matches.allElementsBoundByIndex.contains {
            $0.hasFocus || $0.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists
        }
        if !ownsFocus {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "series-navigation-missing-\(label)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(ownsFocus, "Expected native focus in \(label)", file: file, line: line)
    }

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
