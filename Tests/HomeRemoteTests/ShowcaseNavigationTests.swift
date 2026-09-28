import XCTest

@MainActor
final class ShowcaseNavigationTests: XCTestCase {
    func testScheduleBadgeClearsTallLogoDuringHorizontalNavigation() throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = [
            "--production-home-fixture", "--pinned-home", "--immersive-home",
            "--showcase-schedule-fixture",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        try enterMediaRow(in: app)
        for _ in 0..<4 {
            let badge = app.descendants(matching: .any)["showcase-schedule"].firstMatch
            let logo = app.images["showcase-title-logo"].firstMatch
            XCTAssertTrue(badge.waitForExistence(timeout: 5))
            XCTAssertTrue(logo.waitForExistence(timeout: 5), "Measure decoded artwork, not the fallback title.")
            XCTAssertLessThanOrEqual(logo.frame.height, 124.5)
            XCTAssertGreaterThanOrEqual(logo.frame.minY - badge.frame.maxY, 15.5)
            XCTAssertGreaterThanOrEqual(badge.frame.minY, app.frame.minY)
            XCUIRemote.shared.press(.right)
            Thread.sleep(forTimeInterval: 0.2)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "showcase-schedule-above-tall-logo"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLargerPostersAndCompactHeadingsWithNativeFocus() throws {
        try checkGeometry(focusStyle: "system")
    }

    func testLargerPostersAndCompactHeadingsWithHighlightFocus() throws {
        try checkGeometry(focusStyle: "highlight")
    }

    func testDelayedHomeLoadFinishesAfterBackgrounding() throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = [
            "--production-home-fixture", "--pinned-home", "--immersive-home", "--slow-home-load",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.scrollViews["showcase-rows"].label, "Loading")
        XCUIRemote.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 20))
        try enterMediaRow(in: app)
        XCTAssertTrue(focusedCard(in: app).label.contains("Fixture movie"))
        XCTAssertLessThan(app.staticTexts["Continue Watching"].frame.maxY, focusedCard(in: app).frame.minY)
    }

    func testNativeVerticalReversalsKeepAnchorsAndHorizontalFocus() throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = [
            "--production-home-fixture", "--pinned-home", "--immersive-home",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        try enterMediaRow(in: app)
        let viewport = app.scrollViews["showcase-rows"]
        XCTAssertTrue(viewport.exists, "Rows move inside a native scroll viewport, not a translated stack.")
        XCTAssertEqual(viewport.frame.maxY, app.frame.maxY, accuracy: 0.5)
        XCTAssertTrue(viewport.staticTexts.matching(identifier: "media-row-title").count >= 2)
        for _ in 0..<8 { XCUIRemote.shared.press(.right) }
        let first = focusedCard(in: app)
        let firstLabel = first.label
        let firstFrame = first.frame
        let firstHeading = app.staticTexts["Continue Watching"].frame
        let description = app.staticTexts["A locally supplied movie for measuring the production Home view."].firstMatch
        let firstHeroY = description.frame.minY
        XCUIRemote.shared.press(.down)
        for _ in 0..<3 { XCUIRemote.shared.press(.right) }
        let second = focusedCard(in: app)
        let secondLabel = second.label
        let secondFrame = second.frame
        let secondHeading = app.staticTexts["Recently Added"].frame
        let secondHeroY = description.frame.minY
        XCTAssertNotEqual(firstLabel, secondLabel)
        for _ in 0..<3 {
            XCUIRemote.shared.press(.down)
            XCTAssertEqual(focusedCard(in: app).label, secondLabel, "The last row must retain focus without drift.")
        }
        for _ in 0..<8 {
            XCUIRemote.shared.press(.up)
            XCUIRemote.shared.press(.down)
        }
        XCTAssertEqual(focusedCard(in: app).label, secondLabel)
        XCTAssertEqual(focusedCard(in: app).frame.minX, secondFrame.minX, accuracy: 0.5)
        XCTAssertEqual(focusedCard(in: app).frame.minY, secondFrame.minY, accuracy: 0.5)
        XCTAssertEqual(app.staticTexts["Recently Added"].frame.minY, secondHeading.minY, accuracy: 0.5)
        XCTAssertEqual(description.frame.minY, secondHeroY, accuracy: 0.5)
        XCUIRemote.shared.press(.up)
        XCTAssertEqual(focusedCard(in: app).label, firstLabel)
        XCTAssertEqual(focusedCard(in: app).frame.minX, firstFrame.minX, accuracy: 0.5)
        XCTAssertEqual(focusedCard(in: app).frame.minY, firstFrame.minY, accuracy: 0.5)
        XCTAssertEqual(app.staticTexts["Continue Watching"].frame.minY, firstHeading.minY, accuracy: 0.5)
        XCTAssertEqual(description.frame.minY, firstHeroY, accuracy: 0.5)

        XCUIRemote.shared.press(.down)
        let detailLabel = focusedCard(in: app).label
        XCTAssertNotEqual(detailLabel, firstLabel)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Detail fixture \(detailLabel)"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.menu)
        let returned = NSPredicate { [self] _, _ in focusedCard(in: app).label == detailLabel }
        XCTAssertEqual(XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: returned, object: nil)], timeout: 10
        ), .completed, "Returning from detail preserves the same card and horizontal window.")
        XCTAssertEqual(app.staticTexts["Recently Added"].frame.minY, secondHeading.minY, accuracy: 0.5)
    }

    func testEnteringFromSidebarPinsTheRowWhereReturningDoes() throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--production-home-fixture", "--pinned-home", "--immersive-home"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        let heading = app.staticTexts["Continue Watching"]
        XCTAssertTrue(heading.waitForExistence(timeout: 20))
        let resting = heading.frame.minY
        if focusedCard(in: app).elementType == .button { XCUIRemote.shared.press(.left) }
        XCUIRemote.shared.press(.right)
        Thread.sleep(forTimeInterval: 1)
        let entered = heading.frame.minY
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 1)
        XCUIRemote.shared.press(.up)
        Thread.sleep(forTimeInterval: 1)
        let returned = heading.frame.minY
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "showcase-entered-from-sidebar"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertEqual(entered, returned, accuracy: 0.5, "resting=\(resting) entered=\(entered) returned=\(returned)")
        XCTAssertEqual(resting, returned, accuracy: 0.5, "resting=\(resting) entered=\(entered) returned=\(returned)")
    }

    func testHorizontalNavigationHitches() throws {
        try measureNavigation(vertical: false)
    }

    func testVerticalNavigationHitches() throws {
        try measureNavigation(vertical: true)
    }

    func testHorizontalRowAndHeroAnchorsStayFixed() throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = [
            "--production-home-fixture", "--pinned-home", "--immersive-home",
            "--home-performance-fixture", "--distinct-home-artwork",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        try enterMediaRow(in: app)
        let title = app.staticTexts["Continue Watching"]
        let description = app.staticTexts["A locally supplied movie for measuring the production Home view."].firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        var rowPositions = [title.frame.minY]
        var heroPositions = [description.frame.minY]
        for direction in [XCUIRemote.Button.right, .left] {
            for _ in 0..<16 {
                XCUIRemote.shared.press(direction)
                Thread.sleep(forTimeInterval: 0.65)
                rowPositions.append(title.frame.minY)
                heroPositions.append(description.frame.minY)
            }
        }
        let evidence = XCTAttachment(string: "rowY=\(rowPositions)\nheroY=\(heroPositions)")
        evidence.name = "showcase-horizontal-anchors"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertLessThanOrEqual((rowPositions.max() ?? 0) - (rowPositions.min() ?? 0), 0.5)
        XCTAssertLessThanOrEqual((heroPositions.max() ?? 0) - (heroPositions.min() ?? 0), 0.5)
    }

    func testDeepHorizontalTraversalKeepsRowAndHeroAnchorsFixed() throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = [
            "--production-home-fixture", "--pinned-home", "--immersive-home",
            "--home-performance-fixture", "--distinct-home-artwork",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        try enterMediaRow(in: app)
        let heading = app.staticTexts["Continue Watching"]
        let description = app.staticTexts["A locally supplied movie for measuring the production Home view."].firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        let headingY = heading.frame.minY
        let heroY = description.frame.minY
        let initialLabel = focusedCard(in: app).label
        for _ in 0..<3 {
            XCUIRemote.shared.press(.right, forDuration: 4)
            Thread.sleep(forTimeInterval: 0.3)
            XCTAssertEqual(heading.frame.minY, headingY, accuracy: 0.5)
            XCTAssertEqual(description.frame.minY, heroY, accuracy: 0.5)
        }
        XCTAssertEqual(focusedCard(in: app).label, "Fixture movie 74",
                       "Traverse the entire long row, beyond its initially realized native posters.")
        for _ in 0..<3 {
            XCUIRemote.shared.press(.left, forDuration: 4)
            Thread.sleep(forTimeInterval: 0.3)
            XCTAssertEqual(heading.frame.minY, headingY, accuracy: 0.5)
            XCTAssertEqual(description.frame.minY, heroY, accuracy: 0.5)
        }
        XCTAssertEqual(focusedCard(in: app).label, initialLabel)
    }

    private func measureNavigation(vertical: Bool) throws {
        guard #available(tvOS 26.0, *) else {
            throw XCTSkip("Presented-frame measurements require tvOS 26.")
        }
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = [
            "--production-home-fixture", "--pinned-home", "--immersive-home",
            "--home-performance-fixture", "--distinct-home-artwork",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        try enterMediaRow(in: app)
        let first = focusedCard(in: app)
        let originalLabel = first.label
        XCTAssertTrue(originalLabel.contains("Fixture movie"), "The workload must start on a real card.")
        XCUIRemote.shared.press(.down)
        XCTAssertNotEqual(focusedCard(in: app).label, originalLabel, "The lower row must be reachable.")
        XCUIRemote.shared.press(.up)
        XCTAssertEqual(focusedCard(in: app).label, originalLabel)

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            startMeasuring()
            if vertical {
                for _ in 0..<6 {
                    XCUIRemote.shared.press(.down)
                    XCUIRemote.shared.press(.up)
                }
            } else {
                XCUIRemote.shared.press(.right, forDuration: 3)
            }
            stopMeasuring()
            if !vertical {
                XCTAssertNotEqual(focusedCard(in: app).label, originalLabel)
                XCUIRemote.shared.press(.left, forDuration: 4)
            }
            XCTAssertEqual(focusedCard(in: app).label, originalLabel, "Navigation must return to the same card.")
        }
    }

    private func checkGeometry(focusStyle: String) throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = [
            "--production-home-fixture", "--pinned-home", "--immersive-home",
            "--focus-style=\(focusStyle)",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Production Home ready"].waitForExistence(timeout: 30))
        try enterMediaRow(in: app)
        let first = focusedCard(in: app)
        let initialLabel = first.label
        let currentTitle = app.staticTexts["Continue Watching"]
        XCTAssertLessThan(currentTitle.frame.maxY, first.frame.minY, "The active title must clear focused artwork.")
        let inactiveTitle = app.staticTexts["Recently Added"]
        let preview = app.buttons.allElementsBoundByIndex
            .filter {
                $0.frame.height > 100 && $0.frame.width > 200 && $0.frame.width < 400
                    && $0.frame.minY > inactiveTitle.frame.minY
                    && $0.frame.minY < inactiveTitle.frame.maxY + 100
            }
            .min { $0.frame.minX < $1.frame.minX }
        let next = try XCTUnwrap(preview)
        let inactiveGap = next.frame.minY - inactiveTitle.frame.maxY
        let gapAboveHeading = inactiveTitle.frame.minY - first.frame.maxY
        // Native button frames include 20pt vertical focus margins at rest.
        XCTAssertEqual(gapAboveHeading, focusStyle == "system" ? 30 : 44, accuracy: 0.5)
        XCTAssertEqual(inactiveGap, focusStyle == "system" ? -10 : 10, accuracy: 0.5)
        let previewScreenshot = XCTAttachment(screenshot: app.screenshot())
        previewScreenshot.name = "showcase-preview-spacing-\(focusStyle)"
        previewScreenshot.lifetime = .keepAlways
        add(previewScreenshot)
        XCTAssertGreaterThan(app.frame.maxY - next.frame.minY, 20, "Down needs real visible card area.")
        XCUIRemote.shared.press(.down)
        let poster = focusedCard(in: app)
        let activeGap = poster.frame.minY - inactiveTitle.frame.maxY
        XCTAssertGreaterThanOrEqual(poster.frame.width, 280, "Showcase uses full-size posters instead of 70% artwork.")
        // A 280pt slot includes two 10pt side margins; the 2:3 artwork is 260x390.
        // Native focus expands its AX frame; custom focus keeps the layout frame.
        XCTAssertGreaterThanOrEqual(poster.frame.height, 390)
        XCTAssertEqual(poster.label, "Fixture movie 24", "Hidden captions must retain the media title.")
        XCTAssertGreaterThan(activeGap, 8, "Focus growth must leave clear space beneath the row label.")
        XCTAssertEqual(activeGap, focusStyle == "system" ? 10 : 30, accuracy: 0.5,
                       "More resting space must preserve the existing focused heading clearance.")
        XCTAssertGreaterThan(activeGap, inactiveGap, "The active heading makes room for focus; previews stay compact.")
        let spacing = XCTAttachment(string: "above=\(gapAboveHeading)\nbelow=\(inactiveGap)\nactive=\(activeGap)")
        spacing.name = "showcase-heading-spacing-\(focusStyle)"
        spacing.lifetime = .keepAlways
        add(spacing)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "showcase-poster-\(focusStyle)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        for _ in 0..<4 {
            XCUIRemote.shared.press(.up)
            XCTAssertEqual(focusedCard(in: app).label, initialLabel)
            XCUIRemote.shared.press(.down)
            XCTAssertEqual(focusedCard(in: app).label, poster.label)
        }
    }

    private func enterMediaRow(in app: XCUIApplication) throws {
        if focusedCard(in: app).elementType != .button {
            XCUIRemote.shared.press(.right)
        }
        let ready = NSPredicate { [self] _, _ in focusedCard(in: app).elementType == .button }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 5)
        XCTAssertEqual(result, .completed, "The workload requires actual media focus.")
        if result != .completed {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "showcase-focus-tree"
            tree.lifetime = .keepAlways
            add(tree)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "showcase-focus-failure"
            image.lifetime = .keepAlways
            add(image)
            throw NSError(domain: "ShowcaseNavigationTests", code: 1)
        }
    }

    private func focusedCard(in app: XCUIApplication) -> XCUIElement {
        return app.buttons.allElementsBoundByIndex
            .filter {
                $0.label.contains("Fixture movie") && $0.frame.width > 100 && $0.frame.height > 100
                    && ($0.hasFocus || $0.descendants(matching: .any)
                        .matching(NSPredicate(format: "hasFocus == true")).count > 0)
            }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height } ?? app
    }
}
